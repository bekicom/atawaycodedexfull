import { Product } from "../models/Product.js";
import { Store } from "../models/Store.js";
import { Transfer } from "../models/Transfer.js";
import { asyncHandler } from "../utils/asyncHandler.js";
import { generateCode, roundMoney } from "../utils/inventory.js";

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

function applyRequestedVariants(currentStocks, requestedStocks) {
  const bucket = new Map(
    (currentStocks || []).map((item) => [`${item.size}::${item.color}`, {
      size: item.size,
      color: item.color,
      quantity: Number(item.quantity || 0),
    }]),
  );

  for (const requested of requestedStocks || []) {
    const key = `${requested.size}::${requested.color}`;
    const current = bucket.get(key);
    if (!current) {
      return { error: `${requested.size} / ${requested.color} varianti topilmadi` };
    }
    if (current.quantity < requested.quantity) {
      return { error: `${requested.size} / ${requested.color} variant qoldig'i yetarli emas` };
    }
    current.quantity -= requested.quantity;
    bucket.set(key, current);
  }

  return { nextStocks: [...bucket.values()].filter((item) => item.quantity > 0) };
}

export const listTransfers = asyncHandler(async (req, res) => {
  const q = String(req.query?.q || "").trim();
  const storeName = String(req.query?.storeName || "").trim();

  const query = {};
  if (storeName) {
    query.storeName = { $regex: storeName, $options: "i" };
  }
  if (q) {
    query.$or = [
      { transferNumber: { $regex: q, $options: "i" } },
      { storeName: { $regex: q, $options: "i" } },
      { "items.name": { $regex: q, $options: "i" } },
      { "items.barcode": { $regex: q, $options: "i" } },
      { "items.barcodeAliases": { $regex: q, $options: "i" } },
    ];
  }

  const transfers = await Transfer.find(query).sort({ sentAt: -1, createdAt: -1 }).lean();
  return res.json({ transfers });
});

export const createTransfer = asyncHandler(async (req, res) => {
  const storeName = String(req.body?.storeName || "").trim();
  const storeId = String(req.body?.storeId || "").trim();
  const storeCode = String(req.body?.storeCode || "").trim();
  const note = String(req.body?.note || "").trim();
  const items = Array.isArray(req.body?.items) ? req.body.items : [];

  if (!storeName) {
    return res.status(400).json({ message: "Do'kon nomini kiriting" });
  }
  if (!items.length) {
    return res.status(400).json({ message: "Kamida bitta mahsulot qo'shing" });
  }

  if (storeId) {
    const storeExists = await Store.exists({ _id: storeId });
    if (!storeExists) {
      return res.status(400).json({ message: "Do'kon topilmadi" });
    }
  }

  const normalizedItems = items.map((item) => ({
    productId: String(item?.productId || "").trim(),
    quantity: Number(item?.quantity || 0),
    variants: normalizeRequestedVariants(item?.variantStocks || item?.variants),
  }));

  if (
    normalizedItems.some((item) => !item.productId || (!item.variants.length && (!Number.isFinite(item.quantity) || item.quantity <= 0)))
  ) {
    return res.status(400).json({ message: "Transfer miqdorlari noto'g'ri" });
  }

  const productIds = [...new Set(normalizedItems.map((item) => item.productId))];
  const products = await Product.find({ _id: { $in: productIds } });
  const productMap = new Map(products.map((item) => [String(item._id), item]));

  if (productMap.size !== productIds.length) {
    return res.status(404).json({ message: "Ba'zi mahsulotlar topilmadi" });
  }

  const transferItems = [];
  let totalQuantity = 0;
  let totalValue = 0;

  for (const item of normalizedItems) {
    const product = productMap.get(item.productId);
    const isVariantProduct = Array.isArray(product.variantStocks) && product.variantStocks.length > 0;
    const requestedQty = isVariantProduct
      ? item.variants.reduce((sum, variant) => sum + Number(variant.quantity || 0), 0)
      : Number(item.quantity);
    const currentQty = Number(product.quantity || 0);

    if (!Number.isFinite(requestedQty) || requestedQty <= 0) {
      return res.status(400).json({ message: `${product.name} uchun miqdor noto'g'ri` });
    }

    if (requestedQty > currentQty) {
      return res.status(400).json({
        message: `${product.name} mahsulotida yetarli qoldiq yo'q`,
      });
    }

    product.quantity = currentQty - requestedQty;

    if (isVariantProduct) {
      if (!item.variants.length) {
        return res.status(400).json({
          message: `${product.name} uchun variantlarni kiriting`,
        });
      }

      const allocation = applyRequestedVariants(product.variantStocks, item.variants);
      if (allocation.error) {
        return res.status(400).json({ message: allocation.error });
      }
      product.variantStocks = allocation.nextStocks;
    }

    await product.save();

    const itemTotalValue = roundMoney(Number(product.purchasePrice || 0) * requestedQty);
    totalQuantity += requestedQty;
    totalValue += itemTotalValue;

    transferItems.push({
      productId: product._id,
      name: product.name,
      model: product.code,
      barcode: product.barcode,
      barcodeAliases: Array.isArray(product.barcodeAliases)
        ? product.barcodeAliases.filter((item) => String(item || "").trim() !== "")
        : [],
      unit: product.unit,
      quantity: requestedQty,
      variants: item.variants,
      purchasePrice: Number(product.purchasePrice || 0),
      retailPrice: Number(product.retailPrice || 0),
      wholesalePrice: Number(product.wholesalePrice || 0),
      totalValue: itemTotalValue,
    });
  }

  const transfer = await Transfer.create({
    transferNumber: generateCode("TRF"),
    storeId: storeId || null,
    storeCode,
    storeName,
    status: "sent",
    totalQuantity,
    totalValue: roundMoney(totalValue),
    items: transferItems,
    note,
    createdBy: req.user.username,
    sentAt: new Date(),
  });

  return res.status(201).json({ transfer });
});
