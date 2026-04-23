import { ModalShell } from "../modal/ModalShell";
import { formatMoneyWithCurrency, normalizeUnit } from "../../utils/format";

function money(value) {
  return formatMoneyWithCurrency(Number(value || 0));
}

function getVariantLabel(item) {
  const parts = [];
  if (item?.size) parts.push(item.size);
  if (item?.color) parts.push(item.color);
  return parts.join(" / ") || "-";
}

export function ProductDetailModal({ open, product, onClose }) {
  if (!product) return null;

  const variants = Array.isArray(product.variantStocks) ? product.variantStocks : [];
  const hasVariants = variants.length > 0;
  const totalQuantity = hasVariants
    ? variants.reduce((sum, item) => sum + Number(item.quantity || 0), 0)
    : Number(product.quantity || 0);
  const purchasePrice = Number(product.purchasePrice || 0);
  const retailPrice = Number(product.retailPrice || 0);
  const purchaseTotal = totalQuantity * purchasePrice;
  const retailTotal = totalQuantity * retailPrice;
  const barcodeAliases = Array.isArray(product.barcodeAliases)
    ? product.barcodeAliases.filter(Boolean)
    : [];

  return (
    <ModalShell open={open} title="Mahsulot tafsiloti" onClose={onClose} width="980px">
      <div className="product-detail-modal">
        <div className="detail-summary-grid">
          <div className="detail-summary-card">
            <span>Mahsulot</span>
            <strong>{product.name}</strong>
          </div>
          <div className="detail-summary-card">
            <span>Kod</span>
            <strong>{product.code || "-"}</strong>
          </div>
          <div className="detail-summary-card">
            <span>Jinsi</span>
            <strong>{product.gender === "qiz_bola" ? "Qiz bola" : product.gender === "ogil_bola" ? "O'g'il bola" : "Umumiy"}</strong>
          </div>
          <div className="detail-summary-card">
            <span>Birligi</span>
            <strong>{normalizeUnit(product.unit)}</strong>
          </div>
          <div className="detail-summary-card">
            <span>Jami miqdor</span>
            <strong>{totalQuantity}</strong>
          </div>
          <div className="detail-summary-card">
            <span>Shtixkod</span>
            <strong>{product.barcode || "-"}</strong>
          </div>
          <div className="detail-summary-card">
            <span>Qo'shimcha shtixlar</span>
            <strong>{barcodeAliases.length ? barcodeAliases.join(", ") : "-"}</strong>
          </div>
        </div>

        <div className="detail-totals-grid">
          <div className="detail-total-card">
            <span>Kelish jami</span>
            <strong>{money(purchaseTotal)}</strong>
          </div>
          <div className="detail-total-card">
            <span>Sotish jami</span>
            <strong>{money(retailTotal)}</strong>
          </div>
        </div>

        {hasVariants ? (
          <div className="detail-table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Variant</th>
                  <th>Miqdor</th>
                  <th>Kelish</th>
                  <th>Sotish</th>
                  <th>Kelish jami</th>
                  <th>Sotish jami</th>
                </tr>
              </thead>
              <tbody>
                {variants.map((item, index) => {
                  const qty = Number(item.quantity || 0);
                  const rowPurchase = qty * purchasePrice;
                  const rowRetail = qty * retailPrice;

                  return (
                    <tr key={`${item.size}-${item.color}-${index}`}>
                      <td>{getVariantLabel(item)}</td>
                      <td>{qty}</td>
                      <td>{money(purchasePrice)}</td>
                      <td>{money(retailPrice)}</td>
                      <td>{money(rowPurchase)}</td>
                      <td>{money(rowRetail)}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="detail-table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Nomi</th>
                  <th>Miqdor</th>
                  <th>Kelish</th>
                  <th>Sotish</th>
                  <th>Kelish jami</th>
                  <th>Sotish jami</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td>{product.name}</td>
                  <td>{totalQuantity}</td>
                  <td>{money(purchasePrice)}</td>
                  <td>{money(retailPrice)}</td>
                  <td>{money(purchaseTotal)}</td>
                  <td>{money(retailTotal)}</td>
                </tr>
              </tbody>
            </table>
          </div>
        )}
      </div>
    </ModalShell>
  );
}
