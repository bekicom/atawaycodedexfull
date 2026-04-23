import mongoose from "mongoose";
import { PRODUCT_UNITS, PRICING_MODES } from "../utils/inventory.js";

const purchaseVariantSchema = new mongoose.Schema(
  {
    size: { type: String, required: true, trim: true },
    color: { type: String, required: true, trim: true },
    quantity: { type: Number, required: true, min: 0 },
  },
  { _id: false },
);

const purchaseSchema = new mongoose.Schema(
  {
    entryType: { type: String, enum: ["initial", "restock", "opening_balance", "stock_out"], required: true },
    invoiceNumber: { type: String, required: true, trim: true, unique: true },
    supplierId: { type: mongoose.Schema.Types.ObjectId, ref: "Supplier", required: true },
    productId: { type: mongoose.Schema.Types.ObjectId, ref: "Product", default: null },
    productName: { type: String, required: true, trim: true },
    productModel: { type: String, default: "", trim: true },
    quantity: { type: Number, required: true, min: 0 },
    unit: { type: String, enum: PRODUCT_UNITS, required: true },
    variants: { type: [purchaseVariantSchema], default: [] },
    purchasePrice: { type: Number, required: true, min: 0 },
    priceCurrency: { type: String, enum: ["uzs", "usd"], default: "uzs" },
    usdRateUsed: { type: Number, required: true, min: 1, default: 12600 },
    totalCost: { type: Number, required: true, min: 0 },
    paidAmount: { type: Number, required: true, min: 0, default: 0 },
    debtAmount: { type: Number, required: true, min: 0, default: 0 },
    paymentType: { type: String, enum: ["naqd", "qarz", "qisman"], default: "naqd" },
    pricingMode: { type: String, enum: PRICING_MODES, default: "replace_all" },
    retailPrice: { type: Number, required: true, min: 0, default: 0 },
    wholesalePrice: { type: Number, required: true, min: 0, default: 0 },
    piecePrice: { type: Number, min: 0, default: 0 },
    note: { type: String, default: "", trim: true },
    purchasedAt: { type: Date, default: Date.now },
    createdBy: { type: String, required: true, trim: true },
  },
  { timestamps: true },
);

purchaseSchema.index({ supplierId: 1, purchasedAt: -1 });
purchaseSchema.index({ productId: 1, purchasedAt: -1 });

export const Purchase = mongoose.model("Purchase", purchaseSchema);
