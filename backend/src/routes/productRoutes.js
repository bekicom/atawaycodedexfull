import { Router } from "express";
import { authMiddleware } from "../authMiddleware.js";
import { Product } from "../models/Product.js";
import { Category } from "../models/Category.js";
import { Supplier } from "../models/Supplier.js";
import { Purchase } from "../models/Purchase.js";
import { AppSettings } from "../models/AppSettings.js";
import { SyncTransfer } from "../models/SyncTransfer.js";
import { tenantFilter, withTenant } from "../tenant.js";

const router = Router();
const PRODUCT_UNITS = ["dona", "kg", "blok", "pachka", "qop"];
const PRICING_MODES = ["keep_old", "replace_all", "average"];

function roundMoney(value) {
  return Math.round(Number(value) * 100) / 100;
}

function normalizeUnit(unit) {
  const normalized = String(unit || "").trim().toLowerCase();
  return PRODUCT_UNITS.includes(normalized) ? normalized : "dona";
}

function toNumber(value, fallback = 0) {
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : fallback;
}

function normalizeBarcode(value) {
  return String(value || "").trim();
}

function normalizeBarcodeAliases(value) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.map((item) => normalizeBarcode(item)).filter(Boolean))];
}

function normalizeBarcodeSet(primaryRaw, aliasesRaw) {
  const allCodes = [
    normalizeBarcode(primaryRaw),
    ...normalizeBarcodeAliases(aliasesRaw)
  ].filter(Boolean);
  const uniqueCodes = [...new Set(allCodes)];
  const barcode = uniqueCodes[0] || "";
  const barcodeAliases = uniqueCodes.slice(1);
  return { barcode, barcodeAliases };
}

async function getUsdRate(tenantId) {
  const settings = await AppSettings.findOne({ tenantId }).lean();
  const rate = Number(settings?.usdRate || 0);
  return Number.isFinite(rate) && rate > 0 ? rate : 12171;
}

function convertToUzs(value, priceCurrency, usdRate) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return NaN;
  if (priceCurrency === "usd") return roundMoney(numeric * usdRate);
  return roundMoney(numeric);
}

function parsePayload(body, usdRate) {
  const allowPieceSale = Boolean(body?.allowPieceSale);
  const paymentType = String(body?.paymentType || "naqd").toLowerCase();
  const priceCurrency = String(body?.priceCurrency || "uzs").toLowerCase();
  const quantity = Number(body?.quantity);
  const purchasePrice = convertToUzs(body?.purchasePrice, priceCurrency, usdRate);
  const totalPurchaseCost = roundMoney(quantity * purchasePrice);
  const rawPaid = convertToUzs(body?.paidAmount, priceCurrency, usdRate);
  const paidAmount = paymentType === "naqd"
    ? totalPurchaseCost
    : paymentType === "qarz"
      ? 0
      : rawPaid;
  const debtAmount = Math.max(0, totalPurchaseCost - (Number.isNaN(paidAmount) ? 0 : paidAmount));

  return {
    name: String(body?.name || "").trim(),
    model: String(body?.model || "").trim(),
    barcode: normalizeBarcode(body?.barcode),
    barcodeAliases: normalizeBarcodeAliases(body?.barcodeAliases),
    categoryId: String(body?.categoryId || "").trim(),
    supplierId: String(body?.supplierId || "").trim(),
    purchasePrice,
    priceCurrency,
    usdRateUsed: usdRate,
    totalPurchaseCost: Number.isFinite(totalPurchaseCost) ? totalPurchaseCost : 0,
    retailPrice: convertToUzs(body?.retailPrice, priceCurrency, usdRate),
    wholesalePrice: convertToUzs(body?.wholesalePrice, priceCurrency, usdRate),
    paymentType,
    paidAmount: Number.isFinite(paidAmount) ? paidAmount : 0,
    debtAmount,
    quantity,
    unit: String(body?.unit || "").trim().toLowerCase(),
    allowPieceSale,
    pieceUnit: String(body?.pieceUnit || "kg").trim().toLowerCase(),
    pieceQtyPerBase: Number(body?.pieceQtyPerBase),
    piecePrice: convertToUzs(body?.piecePrice, priceCurrency, usdRate)
  };
}

function validatePayload(payload) {
  if (!payload.name || !payload.model || !payload.unit || !payload.categoryId || !payload.supplierId) {
    return "Barcha maydonlarni to'ldiring";
  }
  if ([payload.purchasePrice, payload.retailPrice, payload.wholesalePrice, payload.quantity, payload.paidAmount].some((n) => Number.isNaN(n) || n < 0)) {
    return "Narx va miqdor manfiy bo'lmasligi kerak";
  }
  if (!["uzs", "usd"].includes(payload.priceCurrency)) return "Valyuta noto'g'ri";
  if (!["naqd", "qarz", "qisman"].includes(payload.paymentType)) return "To'lov turi noto'g'ri";
  if (payload.paidAmount > payload.totalPurchaseCost) return "To'langan summa umumiy summadan katta bo'lmasin";
  if (!PRODUCT_UNITS.includes(payload.unit)) {
    return "Birlik faqat: dona, kg, blok, pachka, qop";
  }
  if (payload.allowPieceSale) {
    if (!PRODUCT_UNITS.includes(payload.pieceUnit)) {
      return "Parcha birlik noto'g'ri";
    }
    if (
      Number.isNaN(payload.pieceQtyPerBase) ||
      payload.pieceQtyPerBase <= 0 ||
      Number.isNaN(payload.piecePrice) ||
      payload.piecePrice <= 0
    ) {
      return "Parcha sotuv uchun miqdor va narx 0 dan katta bo'lishi kerak";
    }
  }
  return null;
}

async function getOrCreateProductSettings(tenantId) {
  let settings = await AppSettings.findOne({ tenantId });
  if (!settings) {
    settings = await AppSettings.create({ tenantId, topProductIds: [] });
  } else if (!Array.isArray(settings.topProductIds)) {
    settings.topProductIds = [];
    await settings.save();
  }
  return settings;
}

async function findBarcodeConflict(req, codes, excludeId = null) {
  const normalizedCodes = [...new Set((codes || []).map((item) => normalizeBarcode(item)).filter(Boolean))];
  if (!normalizedCodes.length) return null;

  const query = tenantFilter(req, {
    $or: [
      { barcode: { $in: normalizedCodes } },
      { barcodeAliases: { $in: normalizedCodes } }
    ]
  });
  if (excludeId) query._id = { $ne: excludeId };

  return Product.findOne(query).select("_id name barcode barcodeAliases").lean();
}

router.get("/", authMiddleware, async (req, res) => {
  const query = tenantFilter(req);
  if (req.query.categoryId) {
    query.categoryId = req.query.categoryId;
  }
  const search = String(req.query.q || "").trim();
  if (search) {
    const safe = search.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    query.$or = [
      { barcode: search },
      { barcodeAliases: search },
      { name: { $regex: safe, $options: "i" } },
      { model: { $regex: safe, $options: "i" } }
    ];
  }

  let products = await Product.find(query)
    .populate({ path: "categoryId", select: "name" })
    .populate({ path: "supplierId", select: "name phone address" })
    .sort({ createdAt: -1 })
    .lean();

  if (search) {
    const exactMatches = products.filter((item) => {
      const barcode = String(item?.barcode || "").trim();
      const aliases = Array.isArray(item?.barcodeAliases)
        ? item.barcodeAliases.map((alias) => String(alias || "").trim())
        : [];
      return barcode === search || aliases.includes(search);
    });
    if (exactMatches.length > 0) {
      products = exactMatches;
    }
  }
  res.json({ products });
});

router.get("/top", authMiddleware, async (req, res) => {
  const settings = await getOrCreateProductSettings(req.user.tenantId);
  const ids = (settings.topProductIds || []).map((item) => String(item));
  if (!ids.length) {
    return res.json({ products: [] });
  }

  const products = await Product.find(tenantFilter(req, { _id: { $in: ids } }))
    .populate({ path: "categoryId", select: "name" })
    .populate({ path: "supplierId", select: "name phone address" })
    .lean();

  const ordered = ids
    .map((id) => products.find((product) => String(product._id) === id))
    .filter(Boolean);

  res.json({ products: ordered });
});

router.put("/top", authMiddleware, async (req, res) => {
  const productIdsRaw = Array.isArray(req.body?.productIds)
    ? req.body.productIds
    : [];
  const productIds = [
    ...new Set(
      productIdsRaw
        .map((item) => String(item || "").trim())
        .filter(Boolean)
    )
  ].slice(0, 24);

  if (productIds.length) {
    const matchedProducts = await Product.countDocuments(
      tenantFilter(req, { _id: { $in: productIds } })
    );
    if (matchedProducts !== productIds.length) {
      return res.status(400).json({ message: "TOP mahsulotlardan biri topilmadi" });
    }
  }

  const settings = await getOrCreateProductSettings(req.user.tenantId);
  settings.topProductIds = productIds;
  await settings.save();

  const products = await Product.find(tenantFilter(req, { _id: { $in: productIds } }))
    .populate({ path: "categoryId", select: "name" })
    .populate({ path: "supplierId", select: "name phone address" })
    .lean();

  const ordered = productIds
    .map((id) => products.find((product) => String(product._id) === id))
    .filter(Boolean);

  res.json({ products: ordered });
});

router.post("/", authMiddleware, async (req, res) => {
  const usdRate = await getUsdRate(req.user.tenantId);
  const payload = parsePayload(req.body, usdRate);
  const barcodeSet = normalizeBarcodeSet(payload.barcode, payload.barcodeAliases);
  payload.barcode = barcodeSet.barcode;
  payload.barcodeAliases = barcodeSet.barcodeAliases;
  const invalid = validatePayload(payload);
  if (invalid) return res.status(400).json({ message: invalid });

  const categoryExists = await Category.exists(tenantFilter(req, { _id: payload.categoryId }));
  if (!categoryExists) return res.status(400).json({ message: "Kategoriya topilmadi" });
  const supplierExists = await Supplier.exists(tenantFilter(req, { _id: payload.supplierId }));
  if (!supplierExists) return res.status(400).json({ message: "Yetkazib beruvchi topilmadi" });

  const exists = await Product.exists(tenantFilter(req, { name: payload.name, model: payload.model, categoryId: payload.categoryId }));
  if (exists) return res.status(409).json({ message: "Bu mahsulot allaqachon mavjud" });
  const barcodeConflict = await findBarcodeConflict(
    req,
    [payload.barcode, ...(payload.barcodeAliases || [])]
  );
  if (barcodeConflict) {
    return res.status(409).json({ message: "Shtixkod boshqa mahsulotga biriktirilgan" });
  }

  const product = await Product.create(withTenant(req, payload));
  await Purchase.create(withTenant(req, {
    entryType: "initial",
    supplierId: payload.supplierId,
    productId: product._id,
    productName: payload.name,
    productModel: payload.model,
    quantity: payload.quantity,
    unit: payload.unit,
    purchasePrice: payload.purchasePrice,
    priceCurrency: payload.priceCurrency,
    usdRateUsed: payload.usdRateUsed,
    totalCost: payload.totalPurchaseCost,
    paidAmount: payload.paidAmount,
    debtAmount: payload.debtAmount,
    paymentType: payload.paymentType,
    pricingMode: "replace_all"
  }));
  res.status(201).json({ product });
});

router.post("/:id/restock", authMiddleware, async (req, res) => {
  const product = await Product.findOne(tenantFilter(req, { _id: req.params.id }));
  if (!product) return res.status(404).json({ message: "Mahsulot topilmadi" });

  const supplierId = String(req.body?.supplierId || "").trim();
  const incomingQuantity = Number(req.body?.quantity);
  const purchasePrice = Number(req.body?.purchasePrice);
  const priceCurrency = String(req.body?.priceCurrency || "uzs").toLowerCase();
  const pricingMode = String(req.body?.pricingMode || "keep_old").toLowerCase();
  const paymentType = String(req.body?.paymentType || "naqd").toLowerCase();
  const usdRate = await getUsdRate(req.user.tenantId);
  const purchasePriceUzs = convertToUzs(purchasePrice, priceCurrency, usdRate);
  const retailPriceNew = convertToUzs(req.body?.retailPrice, priceCurrency, usdRate);
  const wholesalePriceNew = convertToUzs(req.body?.wholesalePrice, priceCurrency, usdRate);
  const piecePriceNew = convertToUzs(req.body?.piecePrice, priceCurrency, usdRate);
  const rawPaid = convertToUzs(req.body?.paidAmount, priceCurrency, usdRate);

  if (!supplierId) return res.status(400).json({ message: "Yetkazib beruvchi tanlang" });
  if (!Number.isFinite(incomingQuantity) || incomingQuantity <= 0) {
    return res.status(400).json({ message: "Kirim miqdori 0 dan katta bo'lishi kerak" });
  }
  if (!["uzs", "usd"].includes(priceCurrency)) {
    return res.status(400).json({ message: "Valyuta noto'g'ri" });
  }
  if (!Number.isFinite(purchasePriceUzs) || purchasePriceUzs < 0) {
    return res.status(400).json({ message: "Kelish narxi noto'g'ri" });
  }
  if (!PRICING_MODES.includes(pricingMode)) {
    return res.status(400).json({ message: "Narx strategiyasi noto'g'ri" });
  }
  if (!["naqd", "qarz", "qisman"].includes(paymentType)) {
    return res.status(400).json({ message: "To'lov turi noto'g'ri" });
  }

  const supplierExists = await Supplier.exists(tenantFilter(req, { _id: supplierId }));
  if (!supplierExists) return res.status(400).json({ message: "Yetkazib beruvchi topilmadi" });

  if (pricingMode !== "keep_old") {
    if (!Number.isFinite(retailPriceNew) || retailPriceNew < 0) {
      return res.status(400).json({ message: "Yangi chakana narx noto'g'ri" });
    }
    if (!Number.isFinite(wholesalePriceNew) || wholesalePriceNew < 0) {
      return res.status(400).json({ message: "Yangi optom narx noto'g'ri" });
    }
    if (product.allowPieceSale && (!Number.isFinite(piecePriceNew) || piecePriceNew <= 0)) {
      return res.status(400).json({ message: "Yangi parcha narx noto'g'ri" });
    }
  }

  const incomingTotal = roundMoney(incomingQuantity * purchasePriceUzs);
  const paidAmount = paymentType === "naqd" ? incomingTotal : paymentType === "qarz" ? 0 : rawPaid;
  if (!Number.isFinite(paidAmount) || paidAmount < 0 || paidAmount > incomingTotal) {
    return res.status(400).json({ message: "To'langan summa noto'g'ri" });
  }
  const debtAmount = incomingTotal - paidAmount;

  const oldQty = Number(product.quantity) || 0;
  const newQty = oldQty + incomingQuantity;

  const oldRetail = Number(product.retailPrice) || 0;
  const oldWholesale = Number(product.wholesalePrice) || 0;
  const oldPiecePrice = Number(product.piecePrice) || 0;

  let retailPrice = oldRetail;
  let wholesalePrice = oldWholesale;
  let piecePrice = oldPiecePrice;

  if (pricingMode === "replace_all") {
    retailPrice = retailPriceNew;
    wholesalePrice = wholesalePriceNew;
    if (product.allowPieceSale) piecePrice = piecePriceNew;
  } else if (pricingMode === "average") {
    retailPrice = (oldRetail + retailPriceNew) / 2;
    wholesalePrice = (oldWholesale + wholesalePriceNew) / 2;
    if (product.allowPieceSale) piecePrice = (oldPiecePrice + piecePriceNew) / 2;
  }

  const oldCost = Number(product.purchasePrice) || 0;
  const weightedPurchasePrice = newQty > 0
    ? ((oldCost * oldQty) + incomingTotal) / newQty
    : purchasePriceUzs;

  product.quantity = newQty;
  product.purchasePrice = weightedPurchasePrice;
  product.priceCurrency = priceCurrency;
  product.usdRateUsed = usdRate;
  product.totalPurchaseCost = incomingTotal;
  product.retailPrice = retailPrice;
  product.wholesalePrice = wholesalePrice;
  if (product.allowPieceSale) {
    product.piecePrice = piecePrice;
  }
  product.supplierId = supplierId;
  product.paymentType = paymentType;
  product.paidAmount = paidAmount;
  product.debtAmount = debtAmount;

  await product.save();

  await Purchase.create(withTenant(req, {
    entryType: "restock",
    supplierId,
    productId: product._id,
    productName: product.name,
    productModel: product.model,
    quantity: incomingQuantity,
    unit: product.unit,
    purchasePrice: purchasePriceUzs,
    priceCurrency,
    usdRateUsed: usdRate,
    totalCost: incomingTotal,
    paidAmount,
    debtAmount,
    paymentType,
    pricingMode
  }));

  return res.json({ product });
});

router.put("/:id", authMiddleware, async (req, res) => {
  const usdRate = await getUsdRate(req.user.tenantId);
  const payload = parsePayload(req.body, usdRate);
  const barcodeSet = normalizeBarcodeSet(payload.barcode, payload.barcodeAliases);
  payload.barcode = barcodeSet.barcode;
  payload.barcodeAliases = barcodeSet.barcodeAliases;
  const invalid = validatePayload(payload);
  if (invalid) return res.status(400).json({ message: invalid });

  const categoryExists = await Category.exists(tenantFilter(req, { _id: payload.categoryId }));
  if (!categoryExists) return res.status(400).json({ message: "Kategoriya topilmadi" });
  const supplierExists = await Supplier.exists(tenantFilter(req, { _id: payload.supplierId }));
  if (!supplierExists) return res.status(400).json({ message: "Yetkazib beruvchi topilmadi" });

  const duplicate = await Product.exists(tenantFilter(req, { name: payload.name, model: payload.model, categoryId: payload.categoryId, _id: { $ne: req.params.id } }));
  if (duplicate) return res.status(409).json({ message: "Bu mahsulot allaqachon mavjud" });
  const barcodeConflict = await findBarcodeConflict(
    req,
    [payload.barcode, ...(payload.barcodeAliases || [])],
    req.params.id
  );
  if (barcodeConflict) {
    return res.status(409).json({ message: "Shtixkod boshqa mahsulotga biriktirilgan" });
  }

  const existing = await Product.findOne(tenantFilter(req, { _id: req.params.id })).lean();
  if (!existing) return res.status(404).json({ message: "Mahsulot topilmadi" });

  const oldQty = Number(existing.quantity) || 0;
  const nextQty = Number(payload.quantity) || 0;
  const qtyDelta = roundMoney(nextQty - oldQty);

  if (qtyDelta < 0) {
    return res.status(400).json({
      message: "Miqdorni kamaytirish uchun sotuv yoki qaytaruvdan foydalaning. Edit faqat oshirishga ruxsat beradi."
    });
  }

  const updated = await Product.findOneAndUpdate(tenantFilter(req, { _id: req.params.id }), payload, { new: true, runValidators: true });
  if (!updated) return res.status(404).json({ message: "Mahsulot topilmadi" });

  if (qtyDelta > 0) {
    const incomingTotal = roundMoney(qtyDelta * (Number(payload.purchasePrice) || 0));
    const paidAmount = payload.paymentType === "naqd"
      ? incomingTotal
      : payload.paymentType === "qarz"
        ? 0
        : Math.min(incomingTotal, Number(payload.paidAmount) || 0);
    const debtAmount = Math.max(0, incomingTotal - paidAmount);

    await Purchase.create(withTenant(req, {
      entryType: "restock",
      supplierId: payload.supplierId,
      productId: updated._id,
      productName: payload.name,
      productModel: payload.model,
      quantity: qtyDelta,
      unit: payload.unit,
      purchasePrice: payload.purchasePrice,
      priceCurrency: payload.priceCurrency,
      usdRateUsed: payload.usdRateUsed,
      totalCost: incomingTotal,
      paidAmount,
      debtAmount,
      paymentType: payload.paymentType,
      pricingMode: "replace_all"
    }));
  }

  res.json({ product: updated });
});

router.delete("/:id", authMiddleware, async (req, res) => {
  const deleted = await Product.findOneAndDelete(tenantFilter(req, { _id: req.params.id }));
  if (!deleted) return res.status(404).json({ message: "Mahsulot topilmadi" });
  res.json({ ok: true });
});

router.post("/sync-central", authMiddleware, async (req, res) => {
  try {
  const centralBaseUrl = String(process.env.CENTRAL_API_BASE_URL || "").trim();
  const centralUsername = String(process.env.CENTRAL_SYNC_USERNAME || "").trim();
  const centralPassword = String(process.env.CENTRAL_SYNC_PASSWORD || "").trim();
  const storeCode = String(req.body?.storeCode || process.env.STORE_CODE || "").trim();
  const storeName = String(req.body?.storeName || process.env.STORE_NAME || "").trim().toLowerCase();

  if (!centralBaseUrl || !centralUsername || !centralPassword) {
    return res.status(400).json({ message: "Markaziy sinxron sozlamalari to'liq emas" });
  }
  if (!storeCode && !storeName) {
    return res.status(400).json({ message: "Do'kon kodi yoki nomi kiritilmagan" });
  }

  const headers = { "Content-Type": "application/json", Accept: "application/json" };
  const loginResponse = await fetch(`${centralBaseUrl}/auth/login`, {
    method: "POST",
    headers,
    body: JSON.stringify({
      username: centralUsername,
      password: centralPassword
    })
  });

  if (!loginResponse.ok) {
    return res.status(502).json({ message: "Markaziy serverga login bo'lmadi" });
  }

  const loginPayload = await loginResponse.json();
  const centralToken = String(loginPayload?.token || "").trim();
  if (!centralToken) {
    return res.status(502).json({ message: "Markaziy server token qaytarmadi" });
  }

  const transfersResponse = await fetch(`${centralBaseUrl}/transfers`, {
    method: "GET",
    headers: { ...headers, Authorization: `Bearer ${centralToken}` }
  });

  if (!transfersResponse.ok) {
    return res.status(502).json({ message: "Markaziy transferlar olinmadi" });
  }

  const transfersPayload = await transfersResponse.json();
  const transferList = Array.isArray(transfersPayload?.transfers)
    ? transfersPayload.transfers
    : [];

  const matchedTransfers = transferList.filter((transfer) => {
    const status = String(transfer?.status || "").trim().toLowerCase();
    const transferCode = String(transfer?.storeCode || "").trim();
    const transferName = String(transfer?.storeName || "").trim().toLowerCase();
    if (status !== "sent") return false;
    if (storeCode && transferCode === storeCode) return true;
    if (storeName && transferName === storeName) return true;
    return false;
  });

  if (!matchedTransfers.length) {
    return res.json({
      syncedTransfers: 0,
      syncedProducts: 0,
      skippedTransfers: 0,
      message: "Sinxron uchun yangi transfer topilmadi"
    });
  }

  const remoteIds = matchedTransfers
    .map((item) => String(item?._id || "").trim())
    .filter(Boolean);

  const existingSynced = await SyncTransfer.find(
    tenantFilter(req, { remoteTransferId: { $in: remoteIds } })
  )
    .select({ remoteTransferId: 1 })
    .lean();

  const syncedIds = new Set(
    existingSynced.map((item) => String(item.remoteTransferId || "").trim()).filter(Boolean)
  );

  const pendingTransfers = [];
  for (const transfer of matchedTransfers) {
    const transferId = String(transfer?._id || "").trim();
    if (!transferId) continue;

    if (!syncedIds.has(transferId)) {
      pendingTransfers.push(transfer);
      continue;
    }

    const transferItems = Array.isArray(transfer?.items) ? transfer.items : [];
    let needsResync = false;

    for (const rawItem of transferItems) {
      const item = rawItem || {};
      const itemName = String(item.name || "Transfer mahsulot").trim() || "Transfer mahsulot";
      const itemBarcodeSet = normalizeBarcodeSet(item.barcode, item.barcodeAliases);
      const itemCodes = [itemBarcodeSet.barcode, ...itemBarcodeSet.barcodeAliases].filter(Boolean);
      const itemModel = String(item.model || "-").trim() || "-";
      const exists = await Product.exists(tenantFilter(req, {
        $or: [
          ...(itemCodes.length
            ? [{ barcode: { $in: itemCodes } }, { barcodeAliases: { $in: itemCodes } }]
            : []),
          { name: itemName, model: itemModel }
        ]
      }));
      if (!exists) {
        needsResync = true;
        break;
      }
    }

    if (needsResync) {
      pendingTransfers.push(transfer);
    }
  }

  if (!pendingTransfers.length) {
    return res.json({
      syncedTransfers: 0,
      syncedProducts: 0,
      skippedTransfers: matchedTransfers.length,
      message: "Barcha transferlar oldin sinxron qilingan"
    });
  }

  const supplierName = "Sklad transfer";
  const categoryName = "Sinxron kategoriya";

  let supplier = await Supplier.findOne(tenantFilter(req, { name: supplierName }));
  if (!supplier) {
    supplier = await Supplier.create(
      withTenant(req, { name: supplierName, address: "Sklad transfer", phone: "" })
    );
  }

  let category = await Category.findOne(tenantFilter(req, { name: categoryName }));
  if (!category) {
    category = await Category.create(withTenant(req, { name: categoryName }));
  }

  let syncedTransfers = 0;
  let syncedProducts = 0;

  for (const transfer of pendingTransfers) {
    const transferId = String(transfer?._id || "").trim();
    const transferNumber = String(transfer?.transferNumber || transfer?.number || transferId).trim();
    const transferItems = Array.isArray(transfer?.items) ? transfer.items : [];

    let transferItemCount = 0;

    for (const rawItem of transferItems) {
      const item = rawItem || {};
      const incomingQuantity = toNumber(item.quantity, 0);
      if (incomingQuantity <= 0) continue;

      const name = String(item.name || "Transfer mahsulot").trim() || "Transfer mahsulot";
      const model = String(item.model || "-").trim() || "-";
      const incomingBarcodeSet = normalizeBarcodeSet(item.barcode, item.barcodeAliases);
      const incomingCodes = [incomingBarcodeSet.barcode, ...incomingBarcodeSet.barcodeAliases].filter(Boolean);
      const unit = normalizeUnit(item.unit);
      const purchasePrice = Math.max(0, roundMoney(toNumber(item.purchasePrice, 0)));
      const rawRetailPrice = Number(item.retailPrice);
      const rawWholesalePrice = Number(item.wholesalePrice);
      const incomingTotal = roundMoney(incomingQuantity * purchasePrice);

      let product = null;
      if (incomingCodes.length) {
        product = await Product.findOne(
          tenantFilter(req, {
            $or: [
              { barcode: { $in: incomingCodes } },
              { barcodeAliases: { $in: incomingCodes } }
            ]
          })
        );
      }
      if (!product) {
        product = await Product.findOne(
          tenantFilter(req, {
            name,
            model,
            categoryId: category._id
          })
        );
      }

      const fallbackBarcode = incomingCodes[0] || `${transferNumber}-${transferItemCount + 1}-${Date.now()}`;

      if (!product) {
        const retailPrice = Number.isFinite(rawRetailPrice)
          ? Math.max(0, roundMoney(rawRetailPrice))
          : purchasePrice;
        const wholesalePrice = Number.isFinite(rawWholesalePrice)
          ? Math.max(0, roundMoney(rawWholesalePrice))
          : retailPrice;

        const createBarcode = incomingCodes[0] || fallbackBarcode;
        const createAliases = incomingCodes.filter((code) => code !== createBarcode);
        const createConflict = await findBarcodeConflict(req, [createBarcode, ...createAliases]);
        const safeBarcode = createConflict ? fallbackBarcode : createBarcode;
        const safeAliases = createConflict ? [] : createAliases;
        product = await Product.create(
          withTenant(req, {
            name,
            model,
            barcode: safeBarcode,
            barcodeAliases: safeAliases,
            categoryId: category._id,
            supplierId: supplier._id,
            purchasePrice,
            priceCurrency: "uzs",
            usdRateUsed: 12171,
            totalPurchaseCost: incomingTotal,
            retailPrice,
            wholesalePrice,
            paymentType: "naqd",
            paidAmount: incomingTotal,
            debtAmount: 0,
            quantity: incomingQuantity,
            unit
          })
        );

        await Purchase.create(
          withTenant(req, {
            entryType: "initial",
            supplierId: supplier._id,
            productId: product._id,
            productName: product.name,
            productModel: product.model,
            quantity: incomingQuantity,
            unit: product.unit,
            purchasePrice,
            priceCurrency: "uzs",
            usdRateUsed: 12171,
            totalCost: incomingTotal,
            paidAmount: incomingTotal,
            debtAmount: 0,
            paymentType: "naqd",
            pricingMode: "replace_all"
          })
        );
      } else {
        const oldQty = toNumber(product.quantity, 0);
        const newQty = roundMoney(oldQty + incomingQuantity);
        const oldCost = toNumber(product.purchasePrice, 0);
        const existingRetailPrice = Math.max(0, roundMoney(toNumber(product.retailPrice, purchasePrice)));
        const existingWholesalePrice = Math.max(0, roundMoney(toNumber(product.wholesalePrice, existingRetailPrice)));
        const retailPrice = Number.isFinite(rawRetailPrice)
          ? Math.max(0, roundMoney(rawRetailPrice))
          : existingRetailPrice;
        const wholesalePrice = Number.isFinite(rawWholesalePrice)
          ? Math.max(0, roundMoney(rawWholesalePrice))
          : existingWholesalePrice;
        const weightedPurchasePrice = newQty > 0
          ? roundMoney(((oldCost * oldQty) + incomingTotal) / newQty)
          : purchasePrice;

        product.quantity = newQty;
        product.purchasePrice = weightedPurchasePrice;
        product.totalPurchaseCost = incomingTotal;
        product.retailPrice = retailPrice;
        product.wholesalePrice = wholesalePrice;
        product.paymentType = "naqd";
        product.paidAmount = incomingTotal;
        product.debtAmount = 0;
        product.supplierId = supplier._id;
        product.unit = unit;

        const mergedCodes = [...new Set([
          ...incomingCodes,
          normalizeBarcode(product.barcode),
          ...normalizeBarcodeAliases(product.barcodeAliases)
        ].filter(Boolean))];
        const primaryBarcode = normalizeBarcode(product.barcode) || mergedCodes[0] || fallbackBarcode;
        const nextAliases = mergedCodes.filter((code) => code !== primaryBarcode);
        const updateConflict = await findBarcodeConflict(req, [primaryBarcode, ...nextAliases], String(product._id));
        if (!updateConflict) {
          product.barcode = primaryBarcode;
          product.barcodeAliases = nextAliases;
        }

        await product.save();

        await Purchase.create(
          withTenant(req, {
            entryType: "restock",
            supplierId: supplier._id,
            productId: product._id,
            productName: product.name,
            productModel: product.model,
            quantity: incomingQuantity,
            unit: product.unit,
            purchasePrice,
            priceCurrency: "uzs",
            usdRateUsed: 12171,
            totalCost: incomingTotal,
            paidAmount: incomingTotal,
            debtAmount: 0,
            paymentType: "naqd",
            pricingMode: "replace_all"
          })
        );
      }

      transferItemCount += 1;
      syncedProducts += 1;
    }

    try {
      await SyncTransfer.create(
        withTenant(req, {
          remoteTransferId: transferId,
          remoteTransferNumber: transferNumber,
          storeCode: String(transfer?.storeCode || storeCode || "").trim(),
          syncedAt: new Date(),
          itemCount: transferItemCount
        })
      );
    } catch (error) {
      if (error?.code !== 11000) throw error;
    }

    syncedTransfers += 1;
  }

  return res.json({
    syncedTransfers,
    syncedProducts,
    skippedTransfers: matchedTransfers.length - pendingTransfers.length,
    message: `${syncedTransfers} ta transfer sinxron qilindi`
  });
  } catch (error) {
    console.error("sync-central error:", error);
    return res.status(500).json({ message: "Sinxron xatoligi", detail: error?.message || "" });
  }
});

export default router;
