import mongoose from "mongoose";

const transferVariantSchema = new mongoose.Schema(
  {
    size: { type: String, required: true, trim: true },
    color: { type: String, required: true, trim: true },
    quantity: { type: Number, required: true, min: 1 },
  },
  { _id: false },
);

const transferItemSchema = new mongoose.Schema(
  {
    productId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Product",
      required: true,
    },
    name: { type: String, required: true, trim: true },
    model: { type: String, default: "", trim: true },
    barcode: { type: String, required: true, trim: true },
    barcodeAliases: { type: [String], default: [] },
    unit: { type: String, required: true, trim: true },
    quantity: { type: Number, required: true, min: 1 },
    variants: { type: [transferVariantSchema], default: [] },
    purchasePrice: { type: Number, required: true, min: 0, default: 0 },
    retailPrice: { type: Number, required: true, min: 0, default: 0 },
    wholesalePrice: { type: Number, required: true, min: 0, default: 0 },
    totalValue: { type: Number, required: true, min: 0, default: 0 },
  },
  { _id: false },
);

const transferSchema = new mongoose.Schema(
  {
    transferNumber: { type: String, required: true, unique: true, trim: true },
    storeId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Store",
      default: null,
    },
    storeCode: { type: String, default: "", trim: true },
    storeName: { type: String, required: true, trim: true },
    status: {
      type: String,
      enum: ["sent", "accepted", "cancelled"],
      default: "sent",
    },
    totalQuantity: { type: Number, required: true, min: 0, default: 0 },
    totalValue: { type: Number, required: true, min: 0, default: 0 },
    items: { type: [transferItemSchema], default: [] },
    note: { type: String, default: "", trim: true },
    createdBy: { type: String, default: "admin", trim: true },
    sentAt: { type: Date, default: Date.now },
  },
  { timestamps: true },
);

transferSchema.index({ storeName: 1, sentAt: -1 });

export const Transfer = mongoose.model("Transfer", transferSchema);
