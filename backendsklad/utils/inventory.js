export const PRODUCT_UNITS = ["dona", "kg", "blok", "pachka", "qop", "razmer"];
export const PAYMENT_TYPES = ["naqd", "qarz", "qisman"];
export const PRICING_MODES = ["keep_old", "replace_all", "average"];
export const PRODUCT_GENDERS = ["", "qiz_bola", "ogil_bola"];

export function normalizeProductUnit(value) {
  const unit = String(value || "").trim().toLowerCase();
  if (unit === "razmer") return "dona";
  return unit;
}

export function isVariantProductUnit(value) {
  return normalizeProductUnit(value) === "dona";
}

export function roundMoney(value) {
  return Math.round(Number(value || 0) * 100) / 100;
}

export function escapeRegex(value) {
  return String(value || "").replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export function normalizeBarcode(value) {
  return String(value || "").replace(/\s+/g, "").trim();
}

export function normalizeBarcodeList(value, primaryBarcode = "") {
  const primary = normalizeBarcode(primaryBarcode);
  if (!Array.isArray(value)) return [];
  return [
    ...new Set(
      value
        .map((item) => normalizeBarcode(item))
        .filter((item) => item && item !== primary),
    ),
  ];
}

export function normalizeProductCode(value) {
  return String(value || "").replace(/\D/g, "").slice(0, 4);
}

export function normalizeStringArray(value) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.map((item) => String(item || "").trim()).filter(Boolean))];
}

export function normalizeVariantStocks(value) {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => ({
      size: String(item?.size || "").trim(),
      color: String(item?.color || "").trim(),
      quantity: Number(item?.quantity || 0),
    }))
    .filter(
      (item) =>
        item.size &&
        item.color &&
        Number.isFinite(item.quantity) &&
        item.quantity >= 0,
    );
}

export function convertToUzs(value, priceCurrency, usdRate) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric) || numeric < 0) return NaN;
  if (String(priceCurrency).toLowerCase() === "usd") {
    return roundMoney(numeric * Number(usdRate || 0));
  }
  return roundMoney(numeric);
}

export function generateCode(prefix) {
  const stamp = Date.now();
  const suffix = Math.floor(100 + Math.random() * 900);
  return `${prefix}-${stamp}-${suffix}`;
}

export function supportsPieceSale(unit) {
  const normalizedUnit = normalizeProductUnit(unit);
  return normalizedUnit === "qop" || normalizedUnit === "pachka";
}

export function mergeVariantStocks(currentStocks, incomingStocks) {
  const bucket = new Map();

  for (const item of currentStocks || []) {
    const key = `${item.size}::${item.color}`;
    bucket.set(key, {
      size: item.size,
      color: item.color,
      quantity: Number(item.quantity || 0),
    });
  }

  for (const item of incomingStocks || []) {
    const key = `${item.size}::${item.color}`;
    const current = bucket.get(key) || {
      size: item.size,
      color: item.color,
      quantity: 0,
    };
    current.quantity += Number(item.quantity || 0);
    bucket.set(key, current);
  }

  return [...bucket.values()].sort(
    (a, b) => a.size.localeCompare(b.size) || a.color.localeCompare(b.color),
  );
}

export function parseProductPayload(body, usdRate) {
  const unit = normalizeProductUnit(body?.unit);
  const paymentType = String(body?.paymentType || "naqd").trim().toLowerCase();
  const priceCurrency = String(body?.priceCurrency || "uzs").trim().toLowerCase();
  const gender = String(body?.gender || "").trim().toLowerCase();
  const sizeOptions = normalizeStringArray(body?.sizeOptions);
  const colorOptions = normalizeStringArray(body?.colorOptions);
  const variantStocks = normalizeVariantStocks(body?.variantStocks);

  const quantity =
    isVariantProductUnit(unit)
      ? variantStocks.reduce((sum, item) => sum + Number(item.quantity || 0), 0)
      : Number(body?.quantity || 0);

  const purchasePrice = convertToUzs(body?.purchasePrice, priceCurrency, usdRate);
  const retailPrice = convertToUzs(body?.retailPrice, priceCurrency, usdRate);
  const wholesalePrice = convertToUzs(body?.wholesalePrice, priceCurrency, usdRate);
  const totalPurchaseCost = roundMoney(quantity * purchasePrice);
  const rawPaidAmount = convertToUzs(body?.paidAmount || 0, priceCurrency, usdRate);
  const paidAmount =
    paymentType === "naqd"
      ? totalPurchaseCost
      : paymentType === "qarz"
        ? 0
        : rawPaidAmount;

  return {
    name: String(body?.name || "").trim(),
    code: normalizeProductCode(body?.code),
    barcode: normalizeBarcode(body?.barcode),
    barcodeAliases: normalizeBarcodeList(body?.barcodeAliases, body?.barcode),
    categoryId: String(body?.categoryId || "").trim(),
    supplierId: String(body?.supplierId || "").trim(),
    purchasePrice,
    retailPrice,
    wholesalePrice,
    quantity,
    unit,
    priceCurrency,
    usdRateUsed: Number(usdRate || 0),
    paymentType,
    gender,
    paidAmount: Number.isFinite(paidAmount) ? paidAmount : 0,
    debtAmount: Math.max(0, totalPurchaseCost - (Number.isFinite(paidAmount) ? paidAmount : 0)),
    totalPurchaseCost,
    sizeOptions,
    colorOptions,
    variantStocks,
    allowPieceSale: supportsPieceSale(unit) ? Boolean(body?.allowPieceSale) : false,
    pieceUnit: String(body?.pieceUnit || "dona").trim().toLowerCase(),
    pieceQtyPerBase: Number(body?.pieceQtyPerBase || 0),
    piecePrice: convertToUzs(body?.piecePrice || 0, priceCurrency, usdRate),
    note: String(body?.note || "").trim(),
  };
}

export function validateProductPayload(payload) {
  if (!payload.name) return "Mahsulot nomi kerak";
  if (!payload.categoryId) return "Kategoriya tanlang";
  if (!payload.supplierId) return "Yetkazib beruvchi tanlang";
  if (!PRODUCT_UNITS.includes(payload.unit)) return "Birlik noto'g'ri";
  if (!["uzs", "usd"].includes(payload.priceCurrency)) return "Valyuta noto'g'ri";
  if (!PAYMENT_TYPES.includes(payload.paymentType)) return "To'lov turi noto'g'ri";
  if (!PRODUCT_GENDERS.includes(payload.gender)) return "Jinsi noto'g'ri";
  if (
    [payload.purchasePrice, payload.retailPrice, payload.wholesalePrice, payload.quantity].some(
      (value) => Number.isNaN(value) || value < 0,
    )
  ) {
    return "Narx va miqdor noto'g'ri";
  }
  if (payload.paidAmount > payload.totalPurchaseCost) {
    return "To'langan summa umumiy summadan katta bo'lmasin";
  }
  if (isVariantProductUnit(payload.unit)) {
    if (!payload.sizeOptions.length) return "Kamida bitta razmer kiriting";
    if (!payload.colorOptions.length) return "Kamida bitta rang kiriting";
    if (!payload.variantStocks.length) return "Razmer-rang qoldig'ini kiriting";
  }
  if (payload.allowPieceSale) {
    if (!PRODUCT_UNITS.includes(payload.pieceUnit)) {
      return "Parcha birlik noto'g'ri";
    }
    if (
      Number.isNaN(payload.pieceQtyPerBase) ||
      payload.pieceQtyPerBase <= 0 ||
      Number.isNaN(payload.piecePrice) ||
      payload.piecePrice <= 0
    ) {
      return "Parcha sotuv uchun miqdor va narx noto'g'ri";
    }
  }
  return null;
}
