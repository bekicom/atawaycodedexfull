import { Router } from "express";

import { login, me } from "../controllers/authController.js";
import {
  createCategory,
  deleteCategory,
  listCategories,
  updateCategory,
} from "../controllers/categoryController.js";
import { getOverview } from "../controllers/dashboardController.js";
import {
  createProduct,
  deleteProduct,
  getProductById,
  listProducts,
  restockProduct,
  updateProduct,
} from "../controllers/productController.js";
import {
  createStockOut,
  createStockOutBulk,
  getSupplierPurchaseReport,
  listPurchases,
  listStockOuts,
} from "../controllers/purchaseController.js";
import {
  createSupplier,
  createSupplierPayment,
  deleteSupplier,
  getSupplierById,
  listSuppliers,
  updateSupplier,
} from "../controllers/supplierController.js";
import {
  createStore,
  deleteStore,
  getStoreById,
  listStores,
  updateStore,
} from "../controllers/storeController.js";
import {
  createSection,
  deleteSection,
  getSectionAllocations,
  listSections,
  setSectionAllocations,
  updateSection,
} from "../controllers/sectionController.js";
import {
  createTransfer,
  listTransfers,
} from "../controllers/transferController.js";
import { authMiddleware } from "../middleware/authMiddleware.js";

const router = Router();

router.post("/auth/login", login);
router.get("/auth/me", authMiddleware, me);

router.get("/categories", authMiddleware, listCategories);
router.post("/categories", authMiddleware, createCategory);
router.put("/categories/:id", authMiddleware, updateCategory);
router.delete("/categories/:id", authMiddleware, deleteCategory);

router.get("/suppliers", authMiddleware, listSuppliers);
router.get("/suppliers/:id", authMiddleware, getSupplierById);
router.post("/suppliers", authMiddleware, createSupplier);
router.put("/suppliers/:id", authMiddleware, updateSupplier);
router.post("/suppliers/:id/payments", authMiddleware, createSupplierPayment);
router.delete("/suppliers/:id", authMiddleware, deleteSupplier);

router.get("/stores", authMiddleware, listStores);
router.get("/stores/:id", authMiddleware, getStoreById);
router.post("/stores", authMiddleware, createStore);
router.put("/stores/:id", authMiddleware, updateStore);
router.delete("/stores/:id", authMiddleware, deleteStore);

router.get("/sections", authMiddleware, listSections);
router.post("/sections", authMiddleware, createSection);
router.put("/sections/:id", authMiddleware, updateSection);
router.delete("/sections/:id", authMiddleware, deleteSection);
router.get("/sections/:id/allocations", authMiddleware, getSectionAllocations);
router.put("/sections/:id/allocations", authMiddleware, setSectionAllocations);

router.get("/products", authMiddleware, listProducts);
router.get("/products/:id", authMiddleware, getProductById);
router.post("/products", authMiddleware, createProduct);
router.post("/products/:id/restock", authMiddleware, restockProduct);
router.put("/products/:id", authMiddleware, updateProduct);
router.delete("/products/:id", authMiddleware, deleteProduct);

router.get("/purchases", authMiddleware, listPurchases);
router.get("/purchases/supplier/:id", authMiddleware, getSupplierPurchaseReport);
router.get("/stock-outs", authMiddleware, listStockOuts);
router.post("/stock-outs", authMiddleware, createStockOut);
router.post("/stock-outs/bulk", authMiddleware, createStockOutBulk);

router.get("/dashboard/overview", authMiddleware, getOverview);

router.get("/transfers", authMiddleware, listTransfers);
router.post("/transfers", authMiddleware, createTransfer);

export default router;
