import { Product } from "../models/Product.js";
import { Purchase } from "../models/Purchase.js";
import { Supplier } from "../models/Supplier.js";
import { SupplierPayment } from "../models/SupplierPayment.js";
import { asyncHandler } from "../utils/asyncHandler.js";
import { convertToUzs, escapeRegex, generateCode, roundMoney } from "../utils/inventory.js";

function mapSupplierStats(purchases, payments) {
  const totals = purchases.reduce(
    (acc, item) => {
      acc.totalPurchase += Number(item.totalCost || 0);
      acc.totalPaid += Number(item.paidAmount || 0);
      acc.totalDebt += Number(item.debtAmount || 0);
      return acc;
    },
    { totalPurchase: 0, totalPaid: 0, totalDebt: 0 },
  );

  const supplierPaid = payments.reduce((sum, item) => sum + Number(item.amount || 0), 0);

  return {
    totalPurchase: roundMoney(totals.totalPurchase),
    totalPaid: roundMoney(totals.totalPaid),
    totalDebt: roundMoney(totals.totalDebt),
    supplierPaid: roundMoney(supplierPaid),
  };
}

export const listSuppliers = asyncHandler(async (_req, res) => {
  const suppliers = await Supplier.find().sort({ name: 1 }).lean();

  const suppliersWithStats = await Promise.all(
    suppliers.map(async (supplier) => {
      const purchases = await Purchase.find({ supplierId: supplier._id }).lean();
      const payments = await SupplierPayment.find({ supplierId: supplier._id }).lean();
      return {
        ...supplier,
        stats: mapSupplierStats(purchases, payments),
      };
    }),
  );

  return res.json({ suppliers: suppliersWithStats });
});

export const getSupplierById = asyncHandler(async (req, res) => {
  const supplier = await Supplier.findById(req.params.id).lean();
  if (!supplier) {
    return res.status(404).json({ message: "Yetkazib beruvchi topilmadi" });
  }

  const purchases = await Purchase.find({ supplierId: supplier._id }).sort({ purchasedAt: -1 }).lean();
  const payments = await SupplierPayment.find({ supplierId: supplier._id }).sort({ paidAt: -1 }).lean();

  return res.json({
    supplier: {
      ...supplier,
      stats: mapSupplierStats(purchases, payments),
    },
    purchases,
    payments,
  });
});

export const createSupplier = asyncHandler(async (req, res) => {
  const name = String(req.body?.name || "").trim();
  const phone = String(req.body?.phone || "").trim();
  const address = String(req.body?.address || "").trim();
  const note = String(req.body?.note || "").trim();
  const openingBalanceAmount = Number(req.body?.openingBalanceAmount || 0);
  const openingBalanceCurrency = String(req.body?.openingBalanceCurrency || "uzs").trim().toLowerCase();
  const usdRate = Number(req.body?.usdRateUsed || process.env.DEFAULT_USD_RATE || 12600);

  if (!name) {
    return res.status(400).json({ message: "Yetkazib beruvchi nomi kerak" });
  }

  const exists = await Supplier.exists({
    name: { $regex: `^${escapeRegex(name)}$`, $options: "i" },
  });
  if (exists) {
    return res.status(409).json({ message: "Bu yetkazib beruvchi mavjud" });
  }

  const supplier = await Supplier.create({
    name,
    phone,
    address,
    note,
    code: generateCode("SUP"),
  });

  if (openingBalanceAmount > 0) {
    const totalCost = convertToUzs(openingBalanceAmount, openingBalanceCurrency, usdRate);
    await Purchase.create({
      entryType: "opening_balance",
      invoiceNumber: generateCode("BAL"),
      supplierId: supplier._id,
      productId: null,
      productName: "Boshlang'ich qarz",
      productModel: "-",
      quantity: 0,
      unit: "dona",
      variants: [],
      purchasePrice: totalCost,
      priceCurrency: openingBalanceCurrency,
      usdRateUsed: usdRate,
      totalCost,
      paidAmount: 0,
      debtAmount: totalCost,
      paymentType: "qarz",
      pricingMode: "keep_old",
      retailPrice: 0,
      wholesalePrice: 0,
      piecePrice: 0,
      note: "Supplier boshlang'ich qarzi",
      createdBy: req.user.username,
    });
  }

  return res.status(201).json({ supplier });
});

export const updateSupplier = asyncHandler(async (req, res) => {
  const name = String(req.body?.name || "").trim();
  const phone = String(req.body?.phone || "").trim();
  const address = String(req.body?.address || "").trim();
  const note = String(req.body?.note || "").trim();
  const isActive =
    typeof req.body?.isActive === "boolean" ? req.body.isActive : true;

  if (!name) {
    return res.status(400).json({ message: "Yetkazib beruvchi nomi kerak" });
  }

  const duplicate = await Supplier.exists({
    _id: { $ne: req.params.id },
    name: { $regex: `^${escapeRegex(name)}$`, $options: "i" },
  });
  if (duplicate) {
    return res.status(409).json({ message: "Bu yetkazib beruvchi mavjud" });
  }

  const supplier = await Supplier.findByIdAndUpdate(
    req.params.id,
    { name, phone, address, note, isActive },
    { new: true, runValidators: true },
  );

  if (!supplier) {
    return res.status(404).json({ message: "Yetkazib beruvchi topilmadi" });
  }

  return res.json({ supplier });
});

export const createSupplierPayment = asyncHandler(async (req, res) => {
  const supplier = await Supplier.findById(req.params.id).lean();
  if (!supplier) {
    return res.status(404).json({ message: "Yetkazib beruvchi topilmadi" });
  }

  const amount = Number(req.body?.amount || 0);
  const note = String(req.body?.note || "").trim();
  if (!Number.isFinite(amount) || amount <= 0) {
    return res.status(400).json({ message: "To'lov summasi noto'g'ri" });
  }

  const purchases = await Purchase.find({
    supplierId: supplier._id,
    debtAmount: { $gt: 0 },
  }).sort({ purchasedAt: 1, _id: 1 });

  if (!purchases.length) {
    return res.status(400).json({ message: "Ochiq qarz topilmadi" });
  }

  let remaining = amount;
  const allocations = [];

  for (const purchase of purchases) {
    if (remaining <= 0) break;
    const currentDebt = Number(purchase.debtAmount || 0);
    const appliedAmount = Math.min(currentDebt, remaining);

    purchase.debtAmount = roundMoney(currentDebt - appliedAmount);
    purchase.paidAmount = roundMoney(Number(purchase.paidAmount || 0) + appliedAmount);
    purchase.paymentType = purchase.debtAmount > 0 ? "qisman" : "naqd";
    await purchase.save();

    allocations.push({
      purchaseId: purchase._id,
      invoiceNumber: purchase.invoiceNumber,
      appliedAmount,
    });

    remaining = roundMoney(remaining - appliedAmount);
  }

  const payment = await SupplierPayment.create({
    supplierId: supplier._id,
    amount: roundMoney(amount - remaining),
    note,
    allocations,
    createdBy: req.user.username,
  });

  return res.status(201).json({ payment });
});

export const deleteSupplier = asyncHandler(async (req, res) => {
  const used = await Product.exists({ supplierId: req.params.id });
  if (used) {
    return res.status(400).json({
      message: "Bu yetkazib beruvchi mahsulotlarga bog'langan",
    });
  }

  const supplier = await Supplier.findByIdAndDelete(req.params.id);
  if (!supplier) {
    return res.status(404).json({ message: "Yetkazib beruvchi topilmadi" });
  }

  return res.json({ ok: true });
});
