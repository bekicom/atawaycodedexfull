import mongoose from "mongoose";

const allocationSchema = new mongoose.Schema(
  {
    purchaseId: { type: mongoose.Schema.Types.ObjectId, ref: "Purchase", required: true },
    invoiceNumber: { type: String, required: true, trim: true },
    appliedAmount: { type: Number, required: true, min: 0 },
  },
  { _id: false },
);

const supplierPaymentSchema = new mongoose.Schema(
  {
    supplierId: { type: mongoose.Schema.Types.ObjectId, ref: "Supplier", required: true },
    amount: { type: Number, required: true, min: 0 },
    note: { type: String, default: "", trim: true },
    allocations: { type: [allocationSchema], default: [] },
    paidAt: { type: Date, default: Date.now },
    createdBy: { type: String, required: true, trim: true },
  },
  { timestamps: true },
);

supplierPaymentSchema.index({ supplierId: 1, paidAt: -1 });

export const SupplierPayment = mongoose.model("SupplierPayment", supplierPaymentSchema);
