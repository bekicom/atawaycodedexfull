import { Purchase } from "../models/Purchase.js";
import { Product } from "../models/Product.js";
import { Supplier } from "../models/Supplier.js";
import { asyncHandler } from "../utils/asyncHandler.js";
import { generateCode, roundMoney } from "../utils/inventory.js";

export const listPurchases = asyncHandler(async (req, res) => {
  const query = {};
  const supplierId = String(req.query.supplierId || "").trim();
  const productId = String(req.query.productId || "").trim();
  const entryType = String(req.query.entryType || "").trim();
  const search = String(req.query.q || "").trim();
  const dateFrom = String(req.query.dateFrom || "").trim();
  const dateTo = String(req.query.dateTo || "").trim();

  if (supplierId) query.supplierId = supplierId;
  if (productId) query.productId = productId;
  if (entryType) query.entryType = entryType;
  if (dateFrom || dateTo) {
    query.purchasedAt = {};
    if (dateFrom) query.purchasedAt.$gte = new Date(`${dateFrom}T00:00:00.000Z`);
    if (dateTo) query.purchasedAt.$lte = new Date(`${dateTo}T23:59:59.999Z`);
  }
  if (search) {
    query.$or = [
      { invoiceNumber: { $regex: search, $options: "i" } },
      { productName: { $regex: search, $options: "i" } },
      { productModel: { $regex: search, $options: "i" } },
      { note: { $regex: search, $options: "i" } },
    ];
  }

  const purchases = await Purchase.find(query)
    .populate({ path: "supplierId", select: "name code" })
    .populate({ path: "productId", select: "name code barcode" })
    .sort({ purchasedAt: -1, createdAt: -1 })
    .lean();

  return res.json({ purchases });
});

export const getSupplierPurchaseReport = asyncHandler(async (req, res) => {
  const supplier = await Supplier.findById(req.params.id).lean();
  if (!supplier) {
    return res.status(404).json({ message: "Yetkazib beruvchi topilmadi" });
  }

  const purchases = await Purchase.find({ supplierId: supplier._id })
    .sort({ purchasedAt: -1 })
    .lean();

  const daily = purchases.reduce((acc, item) => {
    const key = new Date(item.purchasedAt).toISOString().slice(0, 10);
    const current = acc.get(key) || {
      date: key,
      totalCost: 0,
      totalPaid: 0,
      totalDebt: 0,
      items: 0,
      quantity: 0,
    };
    current.totalCost += Number(item.totalCost || 0);
    current.totalPaid += Number(item.paidAmount || 0);
    current.totalDebt += Number(item.debtAmount || 0);
    current.items += 1;
    current.quantity += Number(item.quantity || 0);
    acc.set(key, current);
    return acc;
  }, new Map());

  return res.json({
    supplier,
    purchases,
    daily: [...daily.values()].sort((a, b) => b.date.localeCompare(a.date)),
  });
});

function reduceVariantStocks(variantStocks = [], quantityToReduce = 0) {
  let remaining = Number(quantityToReduce || 0);
  const next = (variantStocks || []).map((item) => ({
    size: String(item.size || "").trim(),
    color: String(item.color || "").trim(),
    quantity: Number(item.quantity || 0),
  }));

  for (const item of next) {
    if (remaining <= 0) break;
    const available = Number(item.quantity || 0);
    if (available <= 0) continue;
    const diff = Math.min(available, remaining);
    item.quantity = roundMoney(available - diff);
    remaining = roundMoney(remaining - diff);
  }

  return {
    remaining,
    variantStocks: next.filter((item) => Number(item.quantity || 0) > 0),
  };
}

function normalizeRequestedVariants(value) {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => ({
      size: String(item?.size || "").trim(),
      color: String(item?.color || "").trim(),
      quantity: Number(item?.quantity || 0),
    }))
    .filter((item) => item.size && item.color && Number.isFinite(item.quantity) && item.quantity > 0);
}

function applyRequestedVariants(currentStocks = [], requestedStocks = []) {
  const bucket = new Map(
    (currentStocks || []).map((item) => [
      `${String(item.size || "").trim()}::${String(item.color || "").trim()}`,
      {
        size: String(item.size || "").trim(),
        color: String(item.color || "").trim(),
        quantity: Number(item.quantity || 0),
      },
    ]),
  );

  for (const requested of requestedStocks) {
    const key = `${requested.size}::${requested.color}`;
    const current = bucket.get(key);
    if (!current) {
      return { error: `${requested.size} / ${requested.color} varianti topilmadi` };
    }
    if (Number(current.quantity || 0) < Number(requested.quantity || 0)) {
      return { error: `${requested.size} / ${requested.color} variant qoldig'i yetarli emas` };
    }
    current.quantity = roundMoney(Number(current.quantity || 0) - Number(requested.quantity || 0));
    bucket.set(key, current);
  }

  return {
    variantStocks: [...bucket.values()].filter((item) => Number(item.quantity || 0) > 0),
  };
}

async function createStockOutRecord({
  productId,
  quantity: rawQuantity,
  note = "",
  requestedVariantStocks = [],
  username = "admin",
}) {
  const quantity = roundMoney(Number(rawQuantity || 0));
  if (!productId) {
    return { error: "Mahsulot tanlang", status: 400 };
  }
  if (!Number.isFinite(quantity) || quantity <= 0) {
    return { error: "Chiqim miqdori 0 dan katta bo'lishi kerak", status: 400 };
  }

  const product = await Product.findById(productId);
  if (!product) {
    return { error: "Mahsulot topilmadi", status: 404 };
  }

  const currentQty = Number(product.quantity || 0);
  if (quantity > currentQty) {
    return {
      error: `${product.name} uchun qoldiq yetarli emas (${currentQty})`,
      status: 400,
    };
  }

  const normalizedRequestedVariants = normalizeRequestedVariants(requestedVariantStocks);
  let consumedVariants = [];
  if (Array.isArray(product.variantStocks) && product.variantStocks.length) {
    if (normalizedRequestedVariants.length) {
      const requestedTotal = roundMoney(
        normalizedRequestedVariants.reduce((sum, item) => sum + Number(item.quantity || 0), 0),
      );
      if (requestedTotal !== quantity) {
        return {
          error: "Variantlar bo'yicha jami miqdor umumiy miqdorga teng bo'lishi kerak",
          status: 400,
        };
      }
      const reduced = applyRequestedVariants(product.variantStocks, normalizedRequestedVariants);
      if (reduced.error) {
        return { error: reduced.error, status: 400 };
      }
      product.variantStocks = reduced.variantStocks;
      consumedVariants = normalizedRequestedVariants;
    } else {
      const beforeStocks = product.variantStocks.map((item) => ({
        size: String(item.size || "").trim(),
        color: String(item.color || "").trim(),
        quantity: Number(item.quantity || 0),
      }));
      const reduced = reduceVariantStocks(beforeStocks, quantity);
      if (reduced.remaining > 0) {
        return {
          error: `${product.name} variant qoldig'i yetarli emas`,
          status: 400,
        };
      }
      consumedVariants = beforeStocks
        .map((item) => {
          const nextItem = reduced.variantStocks.find(
            (next) => next.size === item.size && next.color === item.color,
          );
          const nextQty = Number(nextItem?.quantity || 0);
          const diff = roundMoney(Number(item.quantity || 0) - nextQty);
          if (diff <= 0) return null;
          return {
            size: item.size,
            color: item.color,
            quantity: diff,
          };
        })
        .filter(Boolean);
      product.variantStocks = reduced.variantStocks;
    }
  } else if (normalizedRequestedVariants.length) {
    return {
      error: `${product.name} uchun rang/variant tanlash shart emas`,
      status: 400,
    };
  }

  product.quantity = roundMoney(currentQty - quantity);
  await product.save();

  const totalCost = roundMoney(quantity * Number(product.purchasePrice || 0));
  const stockOut = await Purchase.create({
    entryType: "stock_out",
    invoiceNumber: generateCode("CHQ"),
    supplierId: product.supplierId,
    productId: product._id,
    productName: product.name,
    productModel: product.code,
    quantity,
    unit: product.unit,
    variants: consumedVariants,
    purchasePrice: Number(product.purchasePrice || 0),
    priceCurrency: product.priceCurrency || "uzs",
    usdRateUsed: Number(product.usdRateUsed || 12600),
    totalCost,
    paidAmount: totalCost,
    debtAmount: 0,
    paymentType: "naqd",
    pricingMode: "keep_old",
    retailPrice: Number(product.retailPrice || 0),
    wholesalePrice: Number(product.wholesalePrice || 0),
    piecePrice: Number(product.piecePrice || 0),
    note: String(note || "").trim() || "Mahsulot chiqimi (qaytarildi)",
    createdBy: username,
    purchasedAt: new Date(),
  });

  return { stockOut, product };
}

export const listStockOuts = asyncHandler(async (req, res) => {
  const query = { entryType: "stock_out" };
  const supplierId = String(req.query.supplierId || "").trim();
  const productId = String(req.query.productId || "").trim();
  const search = String(req.query.q || "").trim();
  const dateFrom = String(req.query.dateFrom || "").trim();
  const dateTo = String(req.query.dateTo || "").trim();

  if (supplierId) query.supplierId = supplierId;
  if (productId) query.productId = productId;
  if (dateFrom || dateTo) {
    query.purchasedAt = {};
    if (dateFrom) query.purchasedAt.$gte = new Date(`${dateFrom}T00:00:00.000Z`);
    if (dateTo) query.purchasedAt.$lte = new Date(`${dateTo}T23:59:59.999Z`);
  }
  if (search) {
    query.$or = [
      { invoiceNumber: { $regex: search, $options: "i" } },
      { productName: { $regex: search, $options: "i" } },
      { productModel: { $regex: search, $options: "i" } },
      { note: { $regex: search, $options: "i" } },
    ];
  }

  const stockOuts = await Purchase.find(query)
    .populate({ path: "supplierId", select: "name code" })
    .populate({ path: "productId", select: "name code barcode quantity unit" })
    .sort({ purchasedAt: -1, createdAt: -1 })
    .lean();

  return res.json({ stockOuts });
});

export const createStockOut = asyncHandler(async (req, res) => {
  const payload = await createStockOutRecord({
    productId: String(req.body?.productId || "").trim(),
    quantity: Number(req.body?.quantity || 0),
    note: String(req.body?.note || "").trim(),
    requestedVariantStocks: req.body?.variantStocks || [],
    username: req.user.username,
  });
  if (payload.error) {
    return res.status(payload.status || 400).json({ message: payload.error });
  }
  return res.status(201).json(payload);
});

export const createStockOutBulk = asyncHandler(async (req, res) => {
  const items = Array.isArray(req.body?.items) ? req.body.items : [];
  const commonNote = String(req.body?.note || "").trim();
  if (!items.length) {
    return res.status(400).json({ message: "Kamida bitta mahsulot kiriting" });
  }

  const created = [];
  let totalQuantity = 0;
  let totalCost = 0;

  for (const rawItem of items) {
    const item = {
      productId: String(rawItem?.productId || "").trim(),
      quantity: Number(rawItem?.quantity || 0),
      note: String(rawItem?.note || "").trim() || commonNote,
      variantStocks: rawItem?.variantStocks || [],
    };

    const payload = await createStockOutRecord({
      productId: item.productId,
      quantity: item.quantity,
      note: item.note,
      requestedVariantStocks: item.variantStocks,
      username: req.user.username,
    });
    if (payload.error) {
      return res.status(payload.status || 400).json({ message: payload.error });
    }

    created.push(payload.stockOut);
    totalQuantity += Number(payload.stockOut.quantity || 0);
    totalCost += Number(payload.stockOut.totalCost || 0);
  }

  return res.status(201).json({
    stockOuts: created,
    summary: {
      count: created.length,
      totalQuantity: roundMoney(totalQuantity),
      totalCost: roundMoney(totalCost),
    },
  });
});
