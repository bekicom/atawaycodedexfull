import { Router } from "express";
import bcrypt from "bcryptjs";
import { authMiddleware } from "../authMiddleware.js";
import { User } from "../models/User.js";
import { Product } from "../models/Product.js";
import { Category } from "../models/Category.js";
import { Supplier } from "../models/Supplier.js";
import { Purchase } from "../models/Purchase.js";
import { Section } from "../models/Section.js";
import { tenantFilter, withTenant } from "../tenant.js";

const router = Router();
const ROLES = ["admin", "cashier"];
const escapeRegex = (str) => str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

function requireAdmin(req, res, next) {
  if (req.user?.role !== "admin") {
    return res.status(403).json({ message: "Faqat admin uchun" });
  }
  next();
}

function roundMoney(value) {
  return Math.round(Number(value || 0) * 100) / 100;
}

router.get("/overview", authMiddleware, async (req, res) => {
  const [users, productsCount, categoriesCount, suppliersCount, purchasesCount, sections, products] = await Promise.all([
    User.countDocuments(tenantFilter(req)),
    Product.countDocuments(tenantFilter(req)),
    Category.countDocuments(tenantFilter(req)),
    Supplier.countDocuments(tenantFilter(req)),
    Purchase.countDocuments(tenantFilter(req)),
    Section.find(tenantFilter(req)).lean(),
    Product.find(tenantFilter(req))
      .populate({ path: "categoryId", select: "name" })
      .select("name model code gender barcode quantity unit purchasePrice retailPrice categoryId")
      .lean(),
  ]);

  const totalPurchaseValue = roundMoney(
    products.reduce((sum, item) => sum + (Number(item.quantity || 0) * Number(item.purchasePrice || 0)), 0),
  );
  const totalRetailValue = roundMoney(
    products.reduce((sum, item) => sum + (Number(item.quantity || 0) * Number(item.retailPrice || 0)), 0),
  );
  const totalQuantity = roundMoney(
    products.reduce((sum, item) => sum + Number(item.quantity || 0), 0),
  );

  const categoryMap = new Map();
  for (const product of products) {
    const categoryName = typeof product.categoryId === "object" ? product.categoryId?.name || "-" : "-";
    const key = String(typeof product.categoryId === "object" ? product.categoryId?._id || categoryName : categoryName);
    const current = categoryMap.get(key) || {
      name: categoryName,
      productCount: 0,
      quantity: 0,
      purchaseValue: 0,
      retailValue: 0,
      products: [],
    };
    current.productCount += 1;
    current.quantity += Number(product.quantity || 0);
    current.purchaseValue += Number(product.quantity || 0) * Number(product.purchasePrice || 0);
    current.retailValue += Number(product.quantity || 0) * Number(product.retailPrice || 0);
    current.products.push({
      ...product,
      code: product.code || product.model || "",
      gender: product.gender || "",
    });
    categoryMap.set(key, current);
  }

  const categoryInventory = [...categoryMap.values()]
    .map((item) => ({
      ...item,
      purchaseValue: roundMoney(item.purchaseValue),
      retailValue: roundMoney(item.retailValue),
    }))
    .sort((a, b) => a.name.localeCompare(b.name, "uz"));

  const productMap = new Map(products.map((item) => [String(item._id), item]));
  const sectionInventory = sections
    .map((section) => {
      const items = Array.isArray(section.items) ? section.items : [];
      let quantity = 0;
      let purchaseValue = 0;
      let retailValue = 0;
      let productCount = 0;

      for (const item of items) {
        const product = productMap.get(String(item.productId || ""));
        if (!product) continue;
        const allocatedQty = Number(item.quantity || 0);
        productCount += 1;
        quantity += allocatedQty;
        purchaseValue += allocatedQty * Number(product.purchasePrice || 0);
        retailValue += allocatedQty * Number(product.retailPrice || 0);
      }

      return {
        sectionId: section._id,
        name: section.name,
        productCount,
        quantity: roundMoney(quantity),
        purchaseValue: roundMoney(purchaseValue),
        retailValue: roundMoney(retailValue),
      };
    })
    .sort((a, b) => a.name.localeCompare(b.name, "uz"));

  const lowStockProducts = products
    .filter((item) => Number(item.quantity || 0) <= 5)
    .sort((a, b) => Number(a.quantity || 0) - Number(b.quantity || 0))
    .slice(0, 20)
    .map((item) => ({
      ...item,
      code: item.code || item.model || "",
      gender: item.gender || "",
    }));

  return res.json({
    message: "Admin panelga xush kelibsiz",
    counts: {
      users,
      products: productsCount,
      categories: categoriesCount,
      sections: sections.length,
      suppliers: suppliersCount,
      purchases: purchasesCount,
    },
    inventorySummary: {
      totalPurchaseValue,
      totalRetailValue,
      totalQuantity,
      sectionInventory,
      categoryInventory,
    },
    lowStockProducts,
    stats: {
      users,
      products: productsCount
    },
    admin: req.user
  });
});

router.get("/users", authMiddleware, requireAdmin, async (req, res) => {
  const users = await User.find(tenantFilter(req)).select("_id username role createdAt updatedAt").sort({ createdAt: -1 }).lean();
  res.json({ users });
});

router.post("/users", authMiddleware, requireAdmin, async (req, res) => {
  const username = String(req.body?.username || "").trim();
  const password = String(req.body?.password || "");
  const role = String(req.body?.role || "").toLowerCase();

  if (!username || !password || !role) {
    return res.status(400).json({ message: "Username, parol va rol kerak" });
  }
  if (!ROLES.includes(role)) {
    return res.status(400).json({ message: "Rol noto'g'ri" });
  }
  if (password.length < 4) {
    return res.status(400).json({ message: "Parol kamida 4 ta belgidan iborat bo'lsin" });
  }

  const exists = await User.exists(tenantFilter(req, { username: { $regex: `^${escapeRegex(username)}$`, $options: "i" } }));
  if (exists) return res.status(409).json({ message: "Bu username band" });

  const passwordHash = bcrypt.hashSync(password, 10);
  const user = await User.create(withTenant(req, { username, passwordHash, role }));

  res.status(201).json({
    user: { _id: user._id, username: user.username, role: user.role, createdAt: user.createdAt, updatedAt: user.updatedAt }
  });
});

router.put("/users/:id", authMiddleware, requireAdmin, async (req, res) => {
  const username = String(req.body?.username || "").trim();
  const role = String(req.body?.role || "").toLowerCase();
  const password = req.body?.password == null ? "" : String(req.body.password);

  if (!username || !role) {
    return res.status(400).json({ message: "Username va rol kerak" });
  }
  if (!ROLES.includes(role)) {
    return res.status(400).json({ message: "Rol noto'g'ri" });
  }

  const user = await User.findOne(tenantFilter(req, { _id: req.params.id }));
  if (!user) return res.status(404).json({ message: "Foydalanuvchi topilmadi" });

  const duplicate = await User.exists(tenantFilter(req, {
    _id: { $ne: req.params.id },
    username: { $regex: `^${escapeRegex(username)}$`, $options: "i" }
  }));
  if (duplicate) return res.status(409).json({ message: "Bu username band" });

  user.username = username;
  user.role = role;

  if (password) {
    if (password.length < 4) {
      return res.status(400).json({ message: "Parol kamida 4 ta belgidan iborat bo'lsin" });
    }
    user.passwordHash = bcrypt.hashSync(password, 10);
  }

  // keep at least one admin in system
  if (user.role !== "admin") {
    const adminCount = await User.countDocuments(tenantFilter(req, { role: "admin", _id: { $ne: user._id } }));
    if (adminCount < 1) {
      return res.status(400).json({ message: "Kamida 1 ta admin qolishi kerak" });
    }
  }

  await user.save();
  res.json({
    user: { _id: user._id, username: user.username, role: user.role, createdAt: user.createdAt, updatedAt: user.updatedAt }
  });
});

export default router;
