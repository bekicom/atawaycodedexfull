import { Category } from "../models/Category.js";
import { Product } from "../models/Product.js";
import { Purchase } from "../models/Purchase.js";
import { Section } from "../models/Section.js";
import { SectionAllocation } from "../models/SectionAllocation.js";
import { Supplier } from "../models/Supplier.js";
import { asyncHandler } from "../utils/asyncHandler.js";
import {
  convertToUzs,
  generateCode,
  isVariantProductUnit,
  mergeVariantStocks,
  normalizeBarcode,
  normalizeProductCode,
  parseProductPayload,
  PRICING_MODES,
  roundMoney,
  validateProductPayload,
} from "../utils/inventory.js";

const DEFAULT_USD_RATE = Number(process.env.DEFAULT_USD_RATE || 12600);

async function generateUniqueProductCode(excludeId = null) {
  for (let attempt = 0; attempt < 80; attempt += 1) {
    const code = String(Math.floor(1000 + Math.random() * 9000));
    const exists = await Product.exists({
      code,
      ...(excludeId ? { _id: { $ne: excludeId } } : {}),
    });
    if (!exists) return code;
  }

  throw new Error("Mahsulot kodi yaratib bo'lmadi");
}

async function resolveProductCode(preferredCode, fallbackCode = "", excludeId = null) {
  const normalizedPreferred = normalizeProductCode(preferredCode);
  if (normalizedPreferred.length === 4) {
    const preferredExists = await Product.exists({
      code: normalizedPreferred,
      ...(excludeId ? { _id: { $ne: excludeId } } : {}),
    });
    if (!preferredExists) return normalizedPreferred;
  }

  const normalizedFallback = normalizeProductCode(fallbackCode);
  if (normalizedFallback.length === 4) {
    const fallbackExists = await Product.exists({
      code: normalizedFallback,
      ...(excludeId ? { _id: { $ne: excludeId } } : {}),
    });
    if (!fallbackExists) return normalizedFallback;
  }

  return generateUniqueProductCode(excludeId);
}

async function ensureRelations(categoryId, supplierId) {
  const [categoryExists, supplierExists] = await Promise.all([
    Category.exists({ _id: categoryId }),
    Supplier.exists({ _id: supplierId }),
  ]);

  if (!categoryExists) return "Kategoriya topilmadi";
  if (!supplierExists) return "Yetkazib beruvchi topilmadi";
  return null;
}

async function ensureSection(sectionId) {
  const normalized = String(sectionId || "").trim();
  if (!normalized) return "Bo'lim tanlang";

  const exists = await Section.exists({ _id: normalized, isActive: true });
  if (!exists) return "Bo'lim topilmadi";
  return null;
}

async function ensureUniqueBarcode(barcode, excludeId = null) {
  const normalized = normalizeBarcode(barcode);
  if (!normalized) {
    for (let attempt = 0; attempt < 20; attempt += 1) {
      const generated = generateCode("BAR").replace(/\D/g, "").slice(-13);
      const exists = await Product.exists({
        barcode: generated,
        ...(excludeId ? { _id: { $ne: excludeId } } : {}),
      });
      if (!exists) return { barcode: generated };
    }
    return { error: "Shtixkod yaratib bo'lmadi" };
  }

  const duplicate = await Product.exists({
    barcode: normalized,
    ...(excludeId ? { _id: { $ne: excludeId } } : {}),
  });
  if (duplicate) {
    return { error: "Bu shtixkod allaqachon mavjud" };
  }

  return { barcode: normalized };
}

async function ensureUniqueBarcodeSet(primaryBarcode, barcodeAliases = [], excludeId = null) {
  const primaryResult = await ensureUniqueBarcode(primaryBarcode, excludeId);
  if (primaryResult.error) return primaryResult;

  const aliasList = [...new Set((barcodeAliases || []).map((item) => normalizeBarcode(item)).filter(Boolean))];
  const allCodes = [primaryResult.barcode, ...aliasList];
  if (new Set(allCodes).size !== allCodes.length) {
    return { error: "Shtixkodlar orasida bir xil qiymat bor" };
  }

  if (!aliasList.length) {
    return { barcode: primaryResult.barcode, barcodeAliases: [] };
  }

  const duplicate = await Product.findOne({
    _id: excludeId ? { $ne: excludeId } : { $exists: true },
    $or: [
      { barcode: { $in: allCodes } },
      { barcodeAliases: { $in: allCodes } },
    ],
  })
    .select("_id name barcode barcodeAliases")
    .lean();

  if (duplicate) {
    return { error: "Kiritilgan shtixkodlardan biri allaqachon mavjud" };
  }

  return {
    barcode: primaryResult.barcode,
    barcodeAliases: aliasList,
  };
}

export const listProducts = asyncHandler(async (req, res) => {
  const query = {};
  const search = String(req.query.q || "").trim();
  const categoryId = String(req.query.categoryId || "").trim();
  const supplierId = String(req.query.supplierId || "").trim();

  if (categoryId) query.categoryId = categoryId;
  if (supplierId) query.supplierId = supplierId;
  if (search) {
    const barcode = normalizeBarcode(search);
    const code = normalizeProductCode(search);
    query.$or = [
      { barcode },
      { barcodeAliases: barcode },
      { code },
      { name: { $regex: search, $options: "i" } },
      { model: { $regex: search, $options: "i" } },
    ];
  }

  const products = await Product.find(query)
    .populate({ path: "categoryId", select: "name code" })
    .populate({ path: "supplierId", select: "name code phone" })
    .sort({ createdAt: -1 })
    .lean();

  return res.json({ products });
});

export const getProductById = asyncHandler(async (req, res) => {
  const product = await Product.findById(req.params.id)
    .populate({ path: "categoryId", select: "name code" })
    .populate({ path: "supplierId", select: "name code phone address" })
    .lean();

  if (!product) {
    return res.status(404).json({ message: "Mahsulot topilmadi" });
  }

  const purchases = await Purchase.find({ productId: product._id })
    .sort({ purchasedAt: -1 })
    .lean();

  return res.json({ product, purchases });
});

export const createProduct = asyncHandler(async (req, res) => {
  const sectionId = String(req.body?.sectionId || "").trim();
  const payload = parseProductPayload(req.body, DEFAULT_USD_RATE);
  const invalid = validateProductPayload(payload);
  if (invalid) {
    return res.status(400).json({ message: invalid });
  }

  const relationError = await ensureRelations(payload.categoryId, payload.supplierId);
  if (relationError) {
    return res.status(400).json({ message: relationError });
  }

  const sectionError = await ensureSection(sectionId);
  if (sectionError) {
    return res.status(400).json({ message: sectionError });
  }

  const barcodeResult = await ensureUniqueBarcodeSet(payload.barcode, payload.barcodeAliases);
  if (barcodeResult.error) {
    return res.status(409).json({ message: barcodeResult.error });
  }

  const code = await resolveProductCode(payload.code);

  const product = await Product.create({
    ...payload,
    code,
    barcode: barcodeResult.barcode,
    barcodeAliases: barcodeResult.barcodeAliases,
    lastRestockedAt: new Date(),
  });

  await Purchase.create({
    entryType: "initial",
    invoiceNumber: generateCode("PRD"),
    supplierId: product.supplierId,
    productId: product._id,
    productName: product.name,
    productModel: product.code,
    quantity: product.quantity,
    unit: product.unit,
    variants: product.variantStocks,
    purchasePrice: product.purchasePrice,
    priceCurrency: product.priceCurrency,
    usdRateUsed: product.usdRateUsed,
    totalCost: product.totalPurchaseCost,
    paidAmount: product.paidAmount,
    debtAmount: product.debtAmount,
    paymentType: product.paymentType,
    pricingMode: "replace_all",
    retailPrice: product.retailPrice,
    wholesalePrice: product.wholesalePrice,
    piecePrice: product.piecePrice,
    note: product.note,
    createdBy: req.user.username,
  });

  await SectionAllocation.create({
    sectionId,
    productId: product._id,
    quantity: Number(product.quantity || 0),
  });

  return res.status(201).json({ product });
});

export const updateProduct = asyncHandler(async (req, res) => {
  const payload = parseProductPayload(req.body, DEFAULT_USD_RATE);
  const invalid = validateProductPayload(payload);
  if (invalid) {
    return res.status(400).json({ message: invalid });
  }

  const relationError = await ensureRelations(payload.categoryId, payload.supplierId);
  if (relationError) {
    return res.status(400).json({ message: relationError });
  }

  const barcodeResult = await ensureUniqueBarcodeSet(
    payload.barcode,
    payload.barcodeAliases,
    req.params.id,
  );
  if (barcodeResult.error) {
    return res.status(409).json({ message: barcodeResult.error });
  }

  const currentProduct = await Product.findById(req.params.id);
  if (!currentProduct) {
    return res.status(404).json({ message: "Mahsulot topilmadi" });
  }
  const previousQuantity = Number(currentProduct.quantity || 0);

  const code = await resolveProductCode(payload.code, currentProduct.code, req.params.id);

  const product = await Product.findByIdAndUpdate(
    req.params.id,
    {
      ...payload,
      code,
      barcode: barcodeResult.barcode,
      barcodeAliases: barcodeResult.barcodeAliases,
    },
    { new: true, runValidators: true },
  );

  if (!product) {
    return res.status(404).json({ message: "Mahsulot topilmadi" });
  }

  const nextQuantity = Number(product.quantity || 0);
  const quantityDelta = roundMoney(nextQuantity - previousQuantity);
  if (quantityDelta !== 0) {
    await Purchase.create({
      entryType: "opening_balance",
      invoiceNumber: generateCode("ADJ"),
      supplierId: product.supplierId,
      productId: product._id,
      productName: product.name,
      productModel: product.code,
      quantity: quantityDelta,
      unit: product.unit,
      variants: product.variantStocks,
      purchasePrice: product.purchasePrice,
      priceCurrency: product.priceCurrency,
      usdRateUsed: DEFAULT_USD_RATE,
      totalCost: 0,
      paidAmount: 0,
      debtAmount: 0,
      paymentType: "naqd",
      pricingMode: "keep_old",
      retailPrice: product.retailPrice,
      wholesalePrice: product.wholesalePrice,
      piecePrice: product.piecePrice,
      note: "edit orqali qoldiq tuzatildi",
      createdBy: req.user.username,
    });
  }

  return res.json({ product });
});

export const restockProduct = asyncHandler(async (req, res) => {
  const product = await Product.findById(req.params.id);
  if (!product) {
    return res.status(404).json({ message: "Mahsulot topilmadi" });
  }

  const supplierId = String(req.body?.supplierId || product.supplierId).trim();
  const relationError = await ensureRelations(product.categoryId, supplierId);
  if (relationError) {
    return res.status(400).json({ message: relationError });
  }

  const quantity = Number(req.body?.quantity || 0);
  const paymentType = String(req.body?.paymentType || "naqd").trim().toLowerCase();
  const priceCurrency = String(req.body?.priceCurrency || "uzs").trim().toLowerCase();
  const pricingMode = String(req.body?.pricingMode || "keep_old").trim().toLowerCase();
  const purchasePrice = convertToUzs(req.body?.purchasePrice || 0, priceCurrency, DEFAULT_USD_RATE);
  const retailPriceNew = convertToUzs(req.body?.retailPrice || 0, priceCurrency, DEFAULT_USD_RATE);
  const wholesalePriceNew = convertToUzs(req.body?.wholesalePrice || 0, priceCurrency, DEFAULT_USD_RATE);
  const piecePriceNew = convertToUzs(req.body?.piecePrice || 0, priceCurrency, DEFAULT_USD_RATE);
  const rawPaidAmount = convertToUzs(req.body?.paidAmount || 0, priceCurrency, DEFAULT_USD_RATE);
  const variantStocks = isVariantProductUnit(product.unit) ? req.body?.variantStocks || [] : [];
  const normalizedVariants = isVariantProductUnit(product.unit) ? mergeVariantStocks([], variantStocks) : [];
  const incomingQuantity =
    isVariantProductUnit(product.unit)
      ? normalizedVariants.reduce((sum, item) => sum + Number(item.quantity || 0), 0)
      : quantity;

  if (!Number.isFinite(incomingQuantity) || incomingQuantity <= 0) {
    return res.status(400).json({ message: "Kirim miqdori 0 dan katta bo'lishi kerak" });
  }
  if (!Number.isFinite(purchasePrice) || purchasePrice < 0) {
    return res.status(400).json({ message: "Kelish narxi noto'g'ri" });
  }
  if (!["uzs", "usd"].includes(priceCurrency)) {
    return res.status(400).json({ message: "Valyuta noto'g'ri" });
  }
  if (!["naqd", "qarz", "qisman"].includes(paymentType)) {
    return res.status(400).json({ message: "To'lov turi noto'g'ri" });
  }
  if (!PRICING_MODES.includes(pricingMode)) {
    return res.status(400).json({ message: "Narx strategiyasi noto'g'ri" });
  }

  const incomingTotal = roundMoney(incomingQuantity * purchasePrice);
  const paidAmount =
    paymentType === "naqd"
      ? incomingTotal
      : paymentType === "qarz"
        ? 0
        : rawPaidAmount;
  if (!Number.isFinite(paidAmount) || paidAmount < 0 || paidAmount > incomingTotal) {
    return res.status(400).json({ message: "To'langan summa noto'g'ri" });
  }
  const debtAmount = roundMoney(incomingTotal - paidAmount);

  const oldQty = Number(product.quantity || 0);
  const nextQty = oldQty + incomingQuantity;
  const oldPurchaseValue = Number(product.purchasePrice || 0) * oldQty;
  const nextPurchasePrice =
    nextQty > 0 ? roundMoney((oldPurchaseValue + incomingTotal) / nextQty) : purchasePrice;

  product.quantity = nextQty;
  product.purchasePrice = nextPurchasePrice;
  product.priceCurrency = priceCurrency;
  product.usdRateUsed = DEFAULT_USD_RATE;
  product.totalPurchaseCost = incomingTotal;
  product.paymentType = paymentType;
  product.paidAmount = paidAmount;
  product.debtAmount = debtAmount;
  product.supplierId = supplierId;
  product.lastRestockedAt = new Date();

  if (pricingMode === "replace_all") {
    product.retailPrice = retailPriceNew;
    product.wholesalePrice = wholesalePriceNew;
    if (product.allowPieceSale) {
      product.piecePrice = piecePriceNew;
    }
  } else if (pricingMode === "average") {
    product.retailPrice = roundMoney((Number(product.retailPrice || 0) + retailPriceNew) / 2);
    product.wholesalePrice = roundMoney(
      (Number(product.wholesalePrice || 0) + wholesalePriceNew) / 2,
    );
    if (product.allowPieceSale) {
      product.piecePrice = roundMoney((Number(product.piecePrice || 0) + piecePriceNew) / 2);
    }
  }

  if (isVariantProductUnit(product.unit)) {
    product.variantStocks = mergeVariantStocks(product.variantStocks, normalizedVariants);
  }

  await product.save();

  const purchase = await Purchase.create({
    entryType: "restock",
    invoiceNumber: generateCode("PRH"),
    supplierId,
    productId: product._id,
    productName: product.name,
    productModel: product.code,
    quantity: incomingQuantity,
    unit: product.unit,
    variants: normalizedVariants,
    purchasePrice,
    priceCurrency,
    usdRateUsed: DEFAULT_USD_RATE,
    totalCost: incomingTotal,
    paidAmount,
    debtAmount,
    paymentType,
    pricingMode,
    retailPrice: product.retailPrice,
    wholesalePrice: product.wholesalePrice,
    piecePrice: product.piecePrice,
    note: String(req.body?.note || "").trim(),
    createdBy: req.user.username,
  });

  return res.json({ product, purchase });
});

export const deleteProduct = asyncHandler(async (req, res) => {
  const product = await Product.findByIdAndDelete(req.params.id);
  if (!product) {
    return res.status(404).json({ message: "Mahsulot topilmadi" });
  }

  return res.json({ ok: true });
});
