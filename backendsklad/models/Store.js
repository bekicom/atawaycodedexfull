import mongoose from "mongoose";

const storeSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true },
    storeCode: { type: String, required: true, unique: true, trim: true },
    phone: { type: String, default: "", trim: true },
    address: { type: String, default: "", trim: true },
    note: { type: String, default: "", trim: true },
    isActive: { type: Boolean, default: true },
  },
  { timestamps: true },
);

storeSchema.index({ name: 1 }, { unique: true });

export const Store = mongoose.model("Store", storeSchema);
