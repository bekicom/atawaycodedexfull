import { useEffect, useRef, useState } from "react";
import { formatGroupedNumberInput, formatPercentInput, parseGroupedNumberInput, parsePercentInput } from "../../utils/format";
import { ModalShell } from "../modal/ModalShell";
import { normalizeUnit } from "../../utils/format";

const baseState = {
  supplierId: "",
  quantity: "",
  purchasePrice: "",
  markupPercent: "",
  retailPrice: "",
  piecePrice: "",
  paymentType: "naqd",
  paidAmount: "",
  pricingMode: "keep_old",
  note: "",
  variantStocks: [],
};

function handleGroupedNumberChange(setter, field) {
  return (event) => {
    setter((prev) => ({
      ...prev,
      [field]: formatGroupedNumberInput(event.target.value),
    }));
  };
}

function calculateRetailPriceFromMarkup(purchasePriceInput, markupPercentInput) {
  const purchasePrice = parseGroupedNumberInput(purchasePriceInput);
  const markupPercent = parsePercentInput(markupPercentInput);
  if (!purchasePrice || markupPercent < 0) return "";
  return formatGroupedNumberInput(Math.round(purchasePrice * (1 + markupPercent / 100)));
}

function calculateMarkupPercentFromPrices(purchasePriceInput, retailPriceInput) {
  const purchasePrice = parseGroupedNumberInput(purchasePriceInput);
  const retailPrice = parseGroupedNumberInput(retailPriceInput);
  if (!purchasePrice || retailPrice < purchasePrice) return "";

  const percent = ((retailPrice - purchasePrice) / purchasePrice) * 100;
  return formatPercentInput(String(Math.round(percent * 100) / 100));
}

export function RestockModal({ open, product, suppliers, onClose, onSubmit, loading }) {
  const [form, setForm] = useState(baseState);
  const priceSyncReadyRef = useRef(false);
  const priceSyncSourceRef = useRef(null);
  const isVariantUnit = normalizeUnit(product?.unit) === "dona";
  const isPieceSaleUnit = ["qop", "pachka"].includes(normalizeUnit(product?.unit));

  useEffect(() => {
    priceSyncReadyRef.current = false;
    priceSyncSourceRef.current = null;
    if (!open || !product) return;
    setForm({
      supplierId: typeof product.supplierId === "object" ? product.supplierId?._id || "" : product.supplierId || "",
      quantity: "",
      purchasePrice: formatGroupedNumberInput(product.purchasePrice || ""),
      markupPercent:
        Number(product.purchasePrice || 0) > 0 && Number(product.retailPrice || 0) >= Number(product.purchasePrice || 0)
          ? String(Math.round((((Number(product.retailPrice || 0) - Number(product.purchasePrice || 0)) / Number(product.purchasePrice || 0)) * 100) * 100) / 100)
          : "",
      retailPrice: formatGroupedNumberInput(product.retailPrice || ""),
      piecePrice: formatGroupedNumberInput(product.piecePrice || ""),
      paymentType: "naqd",
      paidAmount: "",
      pricingMode: "keep_old",
      note: "",
      variantStocks: (product.variantStocks || []).map((item) => ({
        size: item.size,
        color: item.color || "",
        quantity: "",
      })),
    });

    const timer = window.setTimeout(() => {
      priceSyncReadyRef.current = true;
    }, 0);

    return () => window.clearTimeout(timer);
  }, [open, product]);

  useEffect(() => {
    if (!priceSyncReadyRef.current) return;
    if (priceSyncSourceRef.current === "retail") return;
    if (form.markupPercent === "") return;
    const nextRetailPrice = calculateRetailPriceFromMarkup(form.purchasePrice, form.markupPercent);
    setForm((prev) => (prev.retailPrice === nextRetailPrice ? prev : { ...prev, retailPrice: nextRetailPrice }));
  }, [form.purchasePrice, form.markupPercent]);

  return (
    <ModalShell open={open} title={`${product?.name || ""} uchun kirim`} onClose={onClose} width="900px">
      <form
        className="form-grid"
        onSubmit={(event) => {
          event.preventDefault();
          onSubmit({
            ...form,
            purchasePrice: parseGroupedNumberInput(form.purchasePrice),
            retailPrice: parseGroupedNumberInput(form.retailPrice),
            piecePrice: parseGroupedNumberInput(form.piecePrice),
            paidAmount: parseGroupedNumberInput(form.paidAmount),
            wholesalePrice: parseGroupedNumberInput(form.retailPrice),
            quantity: Number(form.quantity),
            variantStocks: form.variantStocks.filter((item) => Number(item.quantity || 0) > 0),
          });
        }}
      >
        <label>
          <span>Yetkazib beruvchi</span>
          <select value={form.supplierId} onChange={(event) => setForm((prev) => ({ ...prev, supplierId: event.target.value }))} required>
            <option value="">Tanlang</option>
            {suppliers.map((item) => <option key={item._id} value={item._id}>{item.name}</option>)}
          </select>
        </label>
        {!isVariantUnit ? (
          <label>
            <span>Miqdori</span>
            <input type="number" min="0" step="1" value={form.quantity} onChange={(event) => setForm((prev) => ({ ...prev, quantity: event.target.value }))} required />
          </label>
        ) : null}
        <label>
          <span>Kelish narxi</span>
          <input
            type="text"
            inputMode="numeric"
            value={form.purchasePrice}
            onChange={(event) => {
              priceSyncSourceRef.current = "purchase";
              handleGroupedNumberChange(setForm, "purchasePrice")(event);
            }}
            required
          />
        </label>
        <label>
          <span>Ustama %</span>
          <input
            type="text"
            inputMode="decimal"
            value={form.markupPercent}
            onChange={(event) => {
              priceSyncSourceRef.current = "markup";
              setForm((prev) => ({ ...prev, markupPercent: formatPercentInput(event.target.value) }));
            }}
            placeholder="Masalan 10"
          />
        </label>
        <label>
          <span>Sotish narxi</span>
          <input
            type="text"
            inputMode="numeric"
            value={form.retailPrice}
            onChange={(event) => {
              priceSyncSourceRef.current = "retail";
              const nextRetailPrice = formatGroupedNumberInput(event.target.value);
              setForm((prev) => ({
                ...prev,
                retailPrice: nextRetailPrice,
                markupPercent: calculateMarkupPercentFromPrices(prev.purchasePrice, nextRetailPrice),
              }));
            }}
            required
          />
        </label>
        <label>
          <span>Narx strategiyasi</span>
          <select value={form.pricingMode} onChange={(event) => setForm((prev) => ({ ...prev, pricingMode: event.target.value }))}>
            <option value="keep_old">Eski narx qolsin</option>
            <option value="replace_all">Yangi narx yozilsin</option>
            <option value="average">O'rtachasi olinsin</option>
          </select>
        </label>
        <label>
          <span>To'lov turi</span>
          <select value={form.paymentType} onChange={(event) => setForm((prev) => ({ ...prev, paymentType: event.target.value }))}>
            <option value="naqd">naqd</option>
            <option value="qarz">qarz</option>
            <option value="qisman">qisman</option>
          </select>
        </label>
        <label>
          <span>Qisman to'lov</span>
          <input type="text" inputMode="numeric" value={form.paidAmount} onChange={handleGroupedNumberChange(setForm, "paidAmount")} disabled={form.paymentType !== "qisman"} />
        </label>
        {isPieceSaleUnit && product?.allowPieceSale ? (
          <label>
            <span>Mayda narx ({product?.pieceUnit || "dona"})</span>
            <input type="text" inputMode="numeric" value={form.piecePrice} onChange={handleGroupedNumberChange(setForm, "piecePrice")} />
          </label>
        ) : null}
        {isVariantUnit ? (
          <div className="full-width variant-wrap">
            <span>Variant kirimlari</span>
            <div className="variant-grid">
              {form.variantStocks.map((item, index) => (
                <label key={`${item.size}-${item.color || "none"}`}>
                  <span>{item.size}{item.color ? ` / ${item.color}` : ""}</span>
                  <input
                    type="number"
                    min="0"
                    step="1"
                    value={item.quantity}
                    onChange={(event) =>
                      setForm((prev) => ({
                        ...prev,
                        variantStocks: prev.variantStocks.map((variant, variantIndex) =>
                          variantIndex === index
                            ? { ...variant, quantity: event.target.value === "" ? "" : String(Number(event.target.value)) }
                            : variant,
                        ),
                      }))
                    }
                  />
                </label>
              ))}
            </div>
          </div>
        ) : null}
        <div className="modal-footer full-width">
          <button type="button" className="ghost-btn" onClick={onClose}>Bekor qilish</button>
          <button type="submit" className="primary-btn" disabled={loading}>
            {loading ? "Kiritilmoqda..." : "Kirim qilish"}
          </button>
        </div>
      </form>
    </ModalShell>
  );
}
