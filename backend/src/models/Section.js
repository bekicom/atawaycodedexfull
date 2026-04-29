import mongoose from "mongoose";

const sectionItemSchema = new mongoose.Schema(
  {
    productId: { type: mongoose.Schema.Types.ObjectId, ref: "Product", required: true },
    quantity: { type: Number, required: true, min: 0, default: 0 },
  },
  { _id: false },
);

const sectionSchema = new mongoose.Schema(
  {
    tenantId: { type: mongoose.Schema.Types.ObjectId, ref: "Tenant", required: true, index: true },
    name: { type: String, required: true, trim: true },
    description: { type: String, default: "", trim: true },
    items: { type: [sectionItemSchema], default: [] },
  },
  { timestamps: true },
);

sectionSchema.index({ tenantId: 1, name: 1 }, { unique: true });

export const Section = mongoose.model("Section", sectionSchema);
