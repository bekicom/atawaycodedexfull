import mongoose from "mongoose";

const sectionAllocationSchema = new mongoose.Schema(
  {
    sectionId: { type: mongoose.Schema.Types.ObjectId, ref: "Section", required: true },
    productId: { type: mongoose.Schema.Types.ObjectId, ref: "Product", required: true },
    quantity: { type: Number, required: true, min: 0 },
  },
  { timestamps: true },
);

sectionAllocationSchema.index({ sectionId: 1, productId: 1 }, { unique: true });
sectionAllocationSchema.index({ productId: 1 });

export const SectionAllocation = mongoose.model("SectionAllocation", sectionAllocationSchema);
