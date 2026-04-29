import { Router } from "express";
import { authMiddleware } from "../authMiddleware.js";
import { Product } from "../models/Product.js";
import { Section } from "../models/Section.js";
import { tenantFilter, withTenant } from "../tenant.js";

const router = Router();

function roundMoney(value) {
  return Math.round(Number(value || 0) * 100) / 100;
}

async function buildSectionResponse(req, sections) {
  const productIds = [
    ...new Set(
      sections.flatMap((section) => (section.items || []).map((item) => String(item.productId || "")).filter(Boolean)),
    ),
  ];

  const products = productIds.length
    ? await Product.find(tenantFilter(req, { _id: { $in: productIds } }))
      .select("_id name code model barcode quantity unit purchasePrice retailPrice")
      .lean()
    : [];

  const productMap = new Map(products.map((item) => [String(item._id), item]));

  return sections.map((section) => {
    const items = (section.items || [])
      .map((item) => {
        const product = productMap.get(String(item.productId || ""));
        if (!product) return null;
        const assignedQuantity = Number(item.quantity || 0);
        return {
          productId: String(product._id),
          name: product.name,
          code: product.code || product.model || "",
          barcode: product.barcode || "",
          warehouseQuantity: Number(product.quantity || 0),
          quantity: assignedQuantity,
          unit: product.unit,
          purchasePrice: Number(product.purchasePrice || 0),
          retailPrice: Number(product.retailPrice || 0),
        };
      })
      .filter(Boolean);

    const totalQuantity = items.reduce((sum, item) => sum + Number(item.quantity || 0), 0);
    const totalPurchaseValue = roundMoney(
      items.reduce((sum, item) => sum + (Number(item.quantity || 0) * Number(item.purchasePrice || 0)), 0),
    );
    const totalRetailValue = roundMoney(
      items.reduce((sum, item) => sum + (Number(item.quantity || 0) * Number(item.retailPrice || 0)), 0),
    );

    return {
      _id: section._id,
      name: section.name,
      description: section.description || "",
      items,
      productCount: items.length,
      totalQuantity,
      totalPurchaseValue,
      totalRetailValue,
      createdAt: section.createdAt,
      updatedAt: section.updatedAt,
    };
  });
}

router.get("/", authMiddleware, async (req, res) => {
  const sections = await Section.find(tenantFilter(req)).sort({ createdAt: 1 }).lean();
  res.json({ sections: await buildSectionResponse(req, sections) });
});

router.post("/", authMiddleware, async (req, res) => {
  const name = String(req.body?.name || "").trim();
  const description = String(req.body?.description || "").trim();

  if (!name) {
    return res.status(400).json({ message: "Bo'lim nomi kerak" });
  }

  const exists = await Section.exists(tenantFilter(req, { name }));
  if (exists) {
    return res.status(409).json({ message: "Bu nomdagi bo'lim mavjud" });
  }

  const section = await Section.create(withTenant(req, { name, description }));
  const [fullSection] = await buildSectionResponse(req, [section.toObject()]);
  return res.status(201).json({ section: fullSection });
});

router.put("/:id", authMiddleware, async (req, res) => {
  const name = String(req.body?.name || "").trim();
  const description = String(req.body?.description || "").trim();

  if (!name) {
    return res.status(400).json({ message: "Bo'lim nomi kerak" });
  }

  const duplicate = await Section.exists(tenantFilter(req, { name, _id: { $ne: req.params.id } }));
  if (duplicate) {
    return res.status(409).json({ message: "Bu nomdagi bo'lim mavjud" });
  }

  const section = await Section.findOneAndUpdate(
    tenantFilter(req, { _id: req.params.id }),
    { name, description },
    { new: true, runValidators: true },
  ).lean();

  if (!section) {
    return res.status(404).json({ message: "Bo'lim topilmadi" });
  }

  const [fullSection] = await buildSectionResponse(req, [section]);
  return res.json({ section: fullSection });
});

router.delete("/:id", authMiddleware, async (req, res) => {
  const deleted = await Section.findOneAndDelete(tenantFilter(req, { _id: req.params.id }));
  if (!deleted) {
    return res.status(404).json({ message: "Bo'lim topilmadi" });
  }
  return res.json({ ok: true });
});

router.get("/:id/allocations", authMiddleware, async (req, res) => {
  const section = await Section.findOne(tenantFilter(req, { _id: req.params.id })).lean();
  if (!section) {
    return res.status(404).json({ message: "Bo'lim topilmadi" });
  }
  const [fullSection] = await buildSectionResponse(req, [section]);
  return res.json({ section: fullSection, items: fullSection.items || [] });
});

router.put("/:id/allocations", authMiddleware, async (req, res) => {
  const section = await Section.findOne(tenantFilter(req, { _id: req.params.id }));
  if (!section) {
    return res.status(404).json({ message: "Bo'lim topilmadi" });
  }

  const rawItems = Array.isArray(req.body?.items) ? req.body.items : [];
  const items = rawItems
    .map((item) => ({
      productId: String(item?.productId || "").trim(),
      quantity: Number(item?.quantity || 0),
    }))
    .filter((item) => item.productId && Number.isFinite(item.quantity) && item.quantity > 0);

  const ids = [...new Set(items.map((item) => item.productId))];
  const products = ids.length
    ? await Product.find(tenantFilter(req, { _id: { $in: ids } })).select("_id quantity").lean()
    : [];
  const productMap = new Map(products.map((item) => [String(item._id), Number(item.quantity || 0)]));

  for (const item of items) {
    if (!productMap.has(item.productId)) {
      return res.status(400).json({ message: "Mahsulotlardan biri topilmadi" });
    }
    if (item.quantity > productMap.get(item.productId)) {
      return res.status(400).json({ message: "Bo'lim miqdori ombordagi astatkadan katta bo'lmasin" });
    }
  }

  section.items = items.map((item) => ({
    productId: item.productId,
    quantity: item.quantity,
  }));
  await section.save();

  const [fullSection] = await buildSectionResponse(req, [section.toObject()]);
  return res.json({ section: fullSection, items: fullSection.items || [] });
});

export default router;
