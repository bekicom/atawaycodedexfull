import { Category } from "../models/Category.js";
import { Product } from "../models/Product.js";
import { asyncHandler } from "../utils/asyncHandler.js";
import { escapeRegex, generateCode } from "../utils/inventory.js";

export const listCategories = asyncHandler(async (_req, res) => {
  const categories = await Category.find().sort({ name: 1 }).lean();
  return res.json({ categories });
});

export const createCategory = asyncHandler(async (req, res) => {
  const name = String(req.body?.name || "").trim();
  const description = String(req.body?.description || "").trim();

  if (!name) {
    return res.status(400).json({ message: "Kategoriya nomi kerak" });
  }

  const exists = await Category.exists({
    name: { $regex: `^${escapeRegex(name)}$`, $options: "i" },
  });
  if (exists) {
    return res.status(409).json({ message: "Bu kategoriya mavjud" });
  }

  const category = await Category.create({
    name,
    description,
    code: generateCode("CAT"),
  });

  return res.status(201).json({ category });
});

export const updateCategory = asyncHandler(async (req, res) => {
  const name = String(req.body?.name || "").trim();
  const description = String(req.body?.description || "").trim();
  const isActive =
    typeof req.body?.isActive === "boolean" ? req.body.isActive : true;

  if (!name) {
    return res.status(400).json({ message: "Kategoriya nomi kerak" });
  }

  const duplicate = await Category.exists({
    _id: { $ne: req.params.id },
    name: { $regex: `^${escapeRegex(name)}$`, $options: "i" },
  });
  if (duplicate) {
    return res.status(409).json({ message: "Bu kategoriya mavjud" });
  }

  const category = await Category.findByIdAndUpdate(
    req.params.id,
    { name, description, isActive },
    { new: true, runValidators: true },
  );

  if (!category) {
    return res.status(404).json({ message: "Kategoriya topilmadi" });
  }

  return res.json({ category });
});

export const deleteCategory = asyncHandler(async (req, res) => {
  const used = await Product.exists({ categoryId: req.params.id });
  if (used) {
    return res
      .status(400)
      .json({ message: "Bu kategoriyada mahsulot bor, o'chirib bo'lmaydi" });
  }

  const category = await Category.findByIdAndDelete(req.params.id);
  if (!category) {
    return res.status(404).json({ message: "Kategoriya topilmadi" });
  }

  return res.json({ ok: true });
});
