export function formatMoney(value) {
  const amount = Number(value || 0);
  return amount.toLocaleString("uz-UZ", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  });
}

export function formatMoneyWithCurrency(value, currency = "so'm") {
  return `${formatMoney(value)} ${currency}`;
}

export function formatDateTime(value) {
  if (!value) return "-";
  return new Date(value).toLocaleString("uz-UZ");
}

export function formatDate(value) {
  if (!value) return "-";
  return new Date(value).toLocaleDateString("uz-UZ");
}

export function getCategoryName(item) {
  return typeof item?.categoryId === "object" ? item.categoryId?.name || "-" : "-";
}

export function getCategoryId(item) {
  return typeof item?.categoryId === "object" ? item.categoryId?._id || "" : item?.categoryId || "";
}

export function getSupplierName(item) {
  return typeof item?.supplierId === "object" ? item.supplierId?.name || "-" : "-";
}

export function getSupplierId(item) {
  return typeof item?.supplierId === "object" ? item.supplierId?._id || "" : item?.supplierId || "";
}

export function normalizeUnit(value) {
  const unit = String(value || "").trim();
  if (unit === "razmer") return "dona";
  return unit || "-";
}

export function sumVariantQuantity(variants = []) {
  return variants.reduce((sum, item) => sum + Number(item.quantity || 0), 0);
}

export function buildVariantRows(sizes = [], colors = []) {
  if (!sizes.length) return [];

  if (!colors.length) {
    return sizes.map((size) => ({
      size,
      color: "",
      quantity: 0,
    }));
  }

  return sizes.flatMap((size) =>
    colors.map((color) => ({
      size,
      color,
      quantity: 0,
    })),
  );
}

export function normalizeCsvInput(value) {
  return String(value || "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

export function normalizeSizeInput(value) {
  return [
    ...new Set(
      String(value || "")
        .split(/[\s,;]+/)
        .map((item) => item.trim())
        .filter(Boolean),
    ),
  ];
}

export function toCsvInput(values = []) {
  return values.join(", ");
}

export function toCurrencyNumber(value) {
  const numeric = Number(String(value || "").replace(/,/g, "."));
  return Number.isFinite(numeric) ? numeric : 0;
}

export function formatGroupedNumberInput(value) {
  const digits = String(value ?? "").replace(/\D/g, "");
  if (!digits) return "";
  return digits.replace(/\B(?=(\d{3})+(?!\d))/g, " ");
}

export function parseGroupedNumberInput(value) {
  const digits = String(value ?? "").replace(/\D/g, "");
  return digits ? Number(digits) : 0;
}

export function formatPercentInput(value) {
  const normalized = String(value ?? "").replace(/,/g, ".").replace(/[^0-9.]/g, "");
  const [whole = "", ...rest] = normalized.split(".");
  const fraction = rest.join("").slice(0, 2);
  if (!whole && !fraction) return "";
  return fraction ? `${whole || "0"}.${fraction}` : whole;
}

export function parsePercentInput(value) {
  const numeric = Number(String(value ?? "").replace(/,/g, "."));
  return Number.isFinite(numeric) ? numeric : 0;
}
