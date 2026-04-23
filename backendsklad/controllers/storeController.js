import { Store } from "../models/Store.js";
import { Transfer } from "../models/Transfer.js";
import { asyncHandler } from "../utils/asyncHandler.js";
import { escapeRegex } from "../utils/inventory.js";

async function generateStoreCode() {
  for (let attempt = 0; attempt < 50; attempt += 1) {
    const code = String(Math.floor(1000 + Math.random() * 9000));
    const exists = await Store.exists({ storeCode: code });
    if (!exists) return code;
  }

  throw new Error("Do'kon ID yaratib bo'lmadi");
}

export const listStores = asyncHandler(async (_req, res) => {
  const stores = await Store.find().sort({ createdAt: -1 }).lean();
  return res.json({ stores });
});

export const getStoreById = asyncHandler(async (req, res) => {
  const store = await Store.findById(req.params.id).lean();
  if (!store) {
    return res.status(404).json({ message: "Do'kon topilmadi" });
  }

  const transfers = await Transfer.find({
    $or: [
      { storeId: store._id },
      { storeCode: store.storeCode },
      { storeName: store.name },
    ],
  })
    .sort({ sentAt: -1, createdAt: -1 })
    .lean();

  const inventoryMap = new Map();

  for (const transfer of transfers) {
    for (const item of transfer.items || []) {
      const key = String(item.productId || item.barcode || item.name);
      const current = inventoryMap.get(key) || {
        productId: item.productId || null,
        name: item.name,
        code: item.code || item.model || "",
        barcode: item.barcode || "",
        unit: item.unit || "",
        quantity: 0,
        totalValue: 0,
      };

      current.quantity += Number(item.quantity || 0);
      current.totalValue += Number(item.totalValue || 0);
      inventoryMap.set(key, current);
    }
  }

  const inventory = [...inventoryMap.values()].sort((a, b) => b.quantity - a.quantity);
  const totals = inventory.reduce(
    (acc, item) => {
      acc.totalQuantity += Number(item.quantity || 0);
      acc.totalValue += Number(item.totalValue || 0);
      return acc;
    },
    { totalQuantity: 0, totalValue: 0 },
  );

  return res.json({
    store,
    transfers,
    inventory,
    totals,
  });
});

export const createStore = asyncHandler(async (req, res) => {
  const name = String(req.body?.name || "").trim();
  const address = String(req.body?.address || "").trim();

  if (!name) {
    return res.status(400).json({ message: "Do'kon nomi kerak" });
  }

  const nameExists = await Store.exists({
    name: { $regex: `^${escapeRegex(name)}$`, $options: "i" },
  });

  if (nameExists) {
    return res.status(409).json({ message: "Bu do'kon allaqachon mavjud" });
  }

  const store = await Store.create({
    name,
    storeCode: await generateStoreCode(),
    address,
  });

  return res.status(201).json({ store });
});

export const updateStore = asyncHandler(async (req, res) => {
  const name = String(req.body?.name || "").trim();
  const address = String(req.body?.address || "").trim();
  const isActive = typeof req.body?.isActive === "boolean" ? req.body.isActive : true;

  if (!name) {
    return res.status(400).json({ message: "Do'kon nomi kerak" });
  }

  const nameExists = await Store.exists({
    _id: { $ne: req.params.id },
    name: { $regex: `^${escapeRegex(name)}$`, $options: "i" },
  });

  if (nameExists) {
    return res.status(409).json({ message: "Bu do'kon allaqachon mavjud" });
  }

  const store = await Store.findByIdAndUpdate(
    req.params.id,
    { name, address, isActive },
    { new: true, runValidators: true },
  );

  if (!store) {
    return res.status(404).json({ message: "Do'kon topilmadi" });
  }

  return res.json({ store });
});

export const deleteStore = asyncHandler(async (req, res) => {
  const store = await Store.findByIdAndDelete(req.params.id);
  if (!store) {
    return res.status(404).json({ message: "Do'kon topilmadi" });
  }

  return res.json({ ok: true });
});
