import { Section } from "../models/Section.js";
import { SectionAllocation } from "../models/SectionAllocation.js";
import { Product } from "../models/Product.js";
import { asyncHandler } from "../utils/asyncHandler.js";
import { escapeRegex, roundMoney } from "../utils/inventory.js";

function normalizeItems(items = []) {
  if (!Array.isArray(items)) return [];
  return items
    .map((item) => ({
      productId: String(item?.productId || "").trim(),
      quantity: Number(item?.quantity || 0),
    }))
    .filter((item) => item.productId && Number.isFinite(item.quantity) && item.quantity > 0);
}

async function buildSectionSummary() {
  const [sections, allocations, products] = await Promise.all([
    Section.find({ isActive: true }).sort({ name: 1 }).lean(),
    SectionAllocation.find().lean(),
    Product.find().select("name code model quantity purchasePrice retailPrice unit").lean(),
  ]);

  const productMap = new Map(products.map((item) => [String(item._id), item]));
  const allocationsBySection = new Map();
  for (const allocation of allocations) {
    const sectionId = String(allocation.sectionId);
    if (!allocationsBySection.has(sectionId)) allocationsBySection.set(sectionId, []);
    allocationsBySection.get(sectionId).push(allocation);
  }

  return sections.map((section) => {
    const rows = allocationsBySection.get(String(section._id)) || [];
    let totalQuantity = 0;
    let totalPurchaseValue = 0;
    let totalRetailValue = 0;
    const items = [];

    for (const row of rows) {
      const product = productMap.get(String(row.productId));
      if (!product) continue;
      const quantity = Number(row.quantity || 0);
      const purchaseValue = roundMoney(quantity * Number(product.purchasePrice || 0));
      const retailValue = roundMoney(quantity * Number(product.retailPrice || 0));
      totalQuantity += quantity;
      totalPurchaseValue += purchaseValue;
      totalRetailValue += retailValue;
      items.push({
        allocationId: String(row._id),
        productId: String(product._id),
        name: product.name,
        code: product.code || product.model || "",
        unit: product.unit,
        warehouseQuantity: Number(product.quantity || 0),
        quantity,
        purchasePrice: Number(product.purchasePrice || 0),
        retailPrice: Number(product.retailPrice || 0),
        purchaseValue,
        retailValue,
      });
    }

    return {
      _id: String(section._id),
      name: section.name,
      description: section.description || "",
      productCount: items.length,
      totalQuantity: roundMoney(totalQuantity),
      totalPurchaseValue: roundMoney(totalPurchaseValue),
      totalRetailValue: roundMoney(totalRetailValue),
      items,
    };
  });
}

export const listSections = asyncHandler(async (_req, res) => {
  const sections = await buildSectionSummary();
  return res.json({ sections });
});

export const createSection = asyncHandler(async (req, res) => {
  const name = String(req.body?.name || "").trim();
  const description = String(req.body?.description || "").trim();
  if (!name) {
    return res.status(400).json({ message: "Bo'lim nomi kerak" });
  }

  const exists = await Section.exists({
    name: { $regex: `^${escapeRegex(name)}$`, $options: "i" },
  });
  if (exists) {
    return res.status(409).json({ message: "Bu bo'lim allaqachon mavjud" });
  }

  const section = await Section.create({ name, description });
  return res.status(201).json({ section });
});

export const updateSection = asyncHandler(async (req, res) => {
  const name = String(req.body?.name || "").trim();
  const description = String(req.body?.description || "").trim();
  const isActive =
    typeof req.body?.isActive === "boolean"
      ? req.body.isActive
      : true;

  if (!name) {
    return res.status(400).json({ message: "Bo'lim nomi kerak" });
  }

  const duplicate = await Section.exists({
    _id: { $ne: req.params.id },
    name: { $regex: `^${escapeRegex(name)}$`, $options: "i" },
  });
  if (duplicate) {
    return res.status(409).json({ message: "Bu bo'lim allaqachon mavjud" });
  }

  const section = await Section.findByIdAndUpdate(
    req.params.id,
    { name, description, isActive },
    { new: true, runValidators: true },
  );
  if (!section) {
    return res.status(404).json({ message: "Bo'lim topilmadi" });
  }

  return res.json({ section });
});

export const deleteSection = asyncHandler(async (req, res) => {
  const section = await Section.findByIdAndDelete(req.params.id);
  if (!section) {
    return res.status(404).json({ message: "Bo'lim topilmadi" });
  }
  await SectionAllocation.deleteMany({ sectionId: section._id });
  return res.json({ ok: true });
});

export const getSectionAllocations = asyncHandler(async (req, res) => {
  const section = await Section.findById(req.params.id).lean();
  if (!section) {
    return res.status(404).json({ message: "Bo'lim topilmadi" });
  }

  const rows = await SectionAllocation.find({ sectionId: section._id })
    .populate({ path: "productId", select: "name code model quantity unit purchasePrice retailPrice barcode" })
    .sort({ createdAt: -1 })
    .lean();

  const items = rows
    .filter((row) => row.productId && typeof row.productId === "object")
    .map((row) => ({
      _id: String(row._id),
      productId: String(row.productId._id),
      quantity: Number(row.quantity || 0),
      product: row.productId,
    }));

  return res.json({ section, items });
});

export const setSectionAllocations = asyncHandler(async (req, res) => {
  const section = await Section.findById(req.params.id);
  if (!section) {
    return res.status(404).json({ message: "Bo'lim topilmadi" });
  }

  const items = normalizeItems(req.body?.items);
  const productIds = [...new Set(items.map((item) => item.productId))];
  const products = await Product.find({ _id: { $in: productIds } })
    .select("name quantity")
    .lean();
  const productMap = new Map(products.map((item) => [String(item._id), item]));

  if (productMap.size !== productIds.length) {
    return res.status(400).json({ message: "Ba'zi mahsulotlar topilmadi" });
  }

  const existing = await SectionAllocation.find({ productId: { $in: productIds } }).lean();
  const currentSectionId = String(section._id);
  const allocatedByProductOutside = new Map();
  for (const row of existing) {
    const productId = String(row.productId);
    const sectionId = String(row.sectionId);
    if (sectionId === currentSectionId) continue;
    const prev = Number(allocatedByProductOutside.get(productId) || 0);
    allocatedByProductOutside.set(productId, roundMoney(prev + Number(row.quantity || 0)));
  }

  for (const item of items) {
    const product = productMap.get(item.productId);
    const outside = Number(allocatedByProductOutside.get(item.productId) || 0);
    const maxAllowed = roundMoney(Number(product.quantity || 0) - outside);
    if (item.quantity > maxAllowed) {
      return res.status(400).json({
        message: `${product.name} uchun bo'limga biriktirish miqdori oshib ketdi (maksimum ${maxAllowed})`,
      });
    }
  }

  await SectionAllocation.deleteMany({ sectionId: section._id });
  if (items.length) {
    await SectionAllocation.insertMany(
      items.map((item) => ({
        sectionId: section._id,
        productId: item.productId,
        quantity: roundMoney(item.quantity),
      })),
    );
  }

  const summary = await buildSectionSummary();
  const updated = summary.find((item) => item._id === String(section._id));
  return res.json({ section: updated || null });
});
