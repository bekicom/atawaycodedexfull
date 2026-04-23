import mongoose from "mongoose";
import { PRODUCT_GENDERS, PRODUCT_UNITS } from "../utils/inventory.js";

const productVariantSchema = new mongoose.Schema(
  {
    size: { type: String, required: true, trim: true },
    color: { type: String, required: true, trim: true },
    quantity: { type: Number, required: true, min: 0, default: 0 },
  },
  { _id: false },
);

const productSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true },
    code: { type: String, required: true, trim: true },
    barcode: { type: String, required: true, trim: true, unique: true },
    barcodeAliases: { type: [String], default: [] },
    categoryId: { type: mongoose.Schema.Types.ObjectId, ref: "Category", required: true },
    supplierId: { type: mongoose.Schema.Types.ObjectId, ref: "Supplier", required: true },
    purchasePrice: { type: Number, required: true, min: 0 },
    priceCurrency: { type: String, enum: ["uzs", "usd"], default: "uzs" },
    usdRateUsed: { type: Number, required: true, min: 1, default: 12600 },
    totalPurchaseCost: { type: Number, required: true, min: 0, default: 0 },
    retailPrice: { type: Number, required: true, min: 0 },
    wholesalePrice: { type: Number, required: true, min: 0 },
    paymentType: { type: String, enum: ["naqd", "qarz", "qisman"], default: "naqd" },
    paidAmount: { type: Number, required: true, min: 0, default: 0 },
    debtAmount: { type: Number, required: true, min: 0, default: 0 },
    quantity: { type: Number, required: true, min: 0, default: 0 },
    unit: { type: String, enum: PRODUCT_UNITS, required: true },
    gender: { type: String, enum: PRODUCT_GENDERS, default: "" },
    sizeOptions: { type: [String], default: [] },
    colorOptions: { type: [String], default: [] },
    variantStocks: { type: [productVariantSchema], default: [] },
    allowPieceSale: { type: Boolean, default: false },
    pieceUnit: { type: String, enum: PRODUCT_UNITS, default: "dona" },
    pieceQtyPerBase: { type: Number, min: 0, default: 0 },
    piecePrice: { type: Number, min: 0, default: 0 },
    note: { type: String, default: "", trim: true },
    isActive: { type: Boolean, default: true },
    lastRestockedAt: { type: Date, default: null },
  },
  { timestamps: true },
);

productSchema.index({ code: 1 }, { unique: true, sparse: true });
productSchema.index(
  { barcodeAliases: 1 },
  {
    unique: true,
    sparse: true,
    partialFilterExpression: { barcodeAliases: { $exists: true, $type: "array", $ne: [] } },
  },
);

export const Product = mongoose.model("Product", productSchema);
