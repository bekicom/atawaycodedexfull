import { Category } from "../models/Category.js";
import { Product } from "../models/Product.js";
import { Purchase } from "../models/Purchase.js";
import { Section } from "../models/Section.js";
import { SectionAllocation } from "../models/SectionAllocation.js";
import { Supplier } from "../models/Supplier.js";
import { asyncHandler } from "../utils/asyncHandler.js";
import { roundMoney } from "../utils/inventory.js";

export const getOverview = asyncHandler(async (_req, res) => {
  const [productsCount, categoriesCount, suppliersCount, purchasesCount, sectionsCount] =
    await Promise.all([
      Product.countDocuments(),
      Category.countDocuments(),
      Supplier.countDocuments(),
      Purchase.countDocuments({ entryType: { $in: ["initial", "restock"] } }),
      Section.countDocuments({ isActive: true }),
    ]);

  const lowStockProducts = await Product.find({ quantity: { $lte: 5 } })
    .select("name code barcode quantity unit")
    .sort({ quantity: 1, updatedAt: -1 })
    .limit(10)
    .lean();

  const latestPurchases = await Purchase.find()
    .select("invoiceNumber productName productModel quantity totalCost purchasedAt")
    .sort({ purchasedAt: -1 })
    .limit(10)
    .lean();

  const stockProducts = await Product.find()
    .populate("categoryId", "name")
    .select("name quantity purchasePrice retailPrice categoryId")
    .lean();

  const stockSummary = stockProducts.reduce(
    (acc, item) => {
      const quantity = Number(item.quantity || 0);
      const purchaseValue = quantity * Number(item.purchasePrice || 0);
      const retailValue = quantity * Number(item.retailPrice || 0);

      acc.totalPurchaseValue += purchaseValue;
      acc.totalRetailValue += retailValue;
      acc.totalQuantity += quantity;

      const categoryName =
        typeof item.categoryId === "object" ? item.categoryId?.name || "Kategoriyasiz" : "Kategoriyasiz";

      if (!acc.byCategory[categoryName]) {
        acc.byCategory[categoryName] = {
          categoryId: typeof item.categoryId === "object" ? String(item.categoryId?._id || "") : "",
          name: categoryName,
          productCount: 0,
          quantity: 0,
          purchaseValue: 0,
          retailValue: 0,
          products: [],
        };
      }

      acc.byCategory[categoryName].productCount += 1;
      acc.byCategory[categoryName].quantity += quantity;
      acc.byCategory[categoryName].purchaseValue += purchaseValue;
      acc.byCategory[categoryName].retailValue += retailValue;
      acc.byCategory[categoryName].products.push({
        _id: String(item._id),
        name: item.name,
        code: item.code,
        quantity,
        unit: item.unit,
        purchasePrice: item.purchasePrice,
        retailPrice: item.retailPrice,
      });

      return acc;
    },
    {
      totalPurchaseValue: 0,
      totalRetailValue: 0,
      totalQuantity: 0,
      byCategory: {},
    },
  );

  const categoryInventory = Object.values(stockSummary.byCategory)
    .sort((a, b) => b.purchaseValue - a.purchaseValue)
    .slice(0, 12);

  const [sections, allocations] = await Promise.all([
    Section.find({ isActive: true }).select("name").sort({ name: 1 }).lean(),
    SectionAllocation.find().select("sectionId productId quantity").lean(),
  ]);
  const productValueMap = new Map(
    stockProducts.map((item) => [
      String(item._id),
      {
        purchasePrice: Number(item.purchasePrice || 0),
        retailPrice: Number(item.retailPrice || 0),
      },
    ]),
  );
  const sectionRollup = new Map();
  for (const section of sections) {
    sectionRollup.set(String(section._id), {
      sectionId: String(section._id),
      name: section.name,
      productCount: 0,
      quantity: 0,
      purchaseValue: 0,
      retailValue: 0,
    });
  }
  for (const row of allocations) {
    const bucket = sectionRollup.get(String(row.sectionId));
    if (!bucket) continue;
    const values = productValueMap.get(String(row.productId));
    const qty = Number(row.quantity || 0);
    bucket.productCount += 1;
    bucket.quantity = roundMoney(bucket.quantity + qty);
    bucket.purchaseValue = roundMoney(bucket.purchaseValue + (qty * Number(values?.purchasePrice || 0)));
    bucket.retailValue = roundMoney(bucket.retailValue + (qty * Number(values?.retailPrice || 0)));
  }
  const sectionInventory = [...sectionRollup.values()].sort((a, b) => b.purchaseValue - a.purchaseValue);

  return res.json({
    counts: {
      products: productsCount,
      categories: categoriesCount,
      suppliers: suppliersCount,
      purchases: purchasesCount,
      sections: sectionsCount,
    },
    lowStockProducts,
    latestPurchases,
    inventorySummary: {
      totalPurchaseValue: stockSummary.totalPurchaseValue,
      totalRetailValue: stockSummary.totalRetailValue,
      totalQuantity: stockSummary.totalQuantity,
      categoryInventory,
      sectionInventory,
    },
  });
});
