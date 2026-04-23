import { formatMoneyWithCurrency, getCategoryName, getSupplierName, normalizeUnit } from "../../utils/format";

function ActionIcon({ type }) {
  const common = {
    width: 14,
    height: 14,
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: "1.8",
    strokeLinecap: "round",
    strokeLinejoin: "round",
  };

  switch (type) {
    case "barcode":
      return (
        <svg {...common}>
          <path d="M4 5v14M7 5v14M10 5v14M15 5v14M18 5v14M20 5v14" />
        </svg>
      );
    case "restock":
      return (
        <svg {...common}>
          <path d="M12 5v14M5 12h14" />
        </svg>
      );
    case "view":
      return (
        <svg {...common}>
          <path d="M1.5 12s3.5-6.5 10.5-6.5S22.5 12 22.5 12 19 18.5 12 18.5 1.5 12 1.5 12Z" />
          <circle cx="12" cy="12" r="3" />
        </svg>
      );
    case "edit":
      return (
        <svg {...common}>
          <path d="M4 20h4l10-10-4-4L4 16v4Z" />
          <path d="m12 6 4 4" />
        </svg>
      );
    case "delete":
      return (
        <svg {...common}>
          <path d="M4 7h16" />
          <path d="M10 11v6M14 11v6" />
          <path d="M6 7l1 13h10l1-13" />
          <path d="M9 7V4h6v3" />
        </svg>
      );
    default:
      return null;
  }
}

export function ProductsTable({ products, onEdit, onDelete, onRestock, onPrint, onView }) {
  const getGenderLabel = (value) => {
    if (value === "qiz_bola") return "Qiz bola";
    if (value === "ogil_bola") return "O'g'il bola";
    return "-";
  };

  return (
    <div className="table-panel">
      <table>
        <thead>
          <tr>
            <th>Mahsulot nomi</th>
            <th>Kodi</th>
            <th>Jinsi</th>
            <th>Shtixkod</th>
            <th>Kategoriya</th>
            <th>Yetkazib beruvchi</th>
            <th>Kelish narxi</th>
            <th>Sotish narxi</th>
            <th>To'lov / Qarz</th>
            <th>Xisobot</th>
            <th>Miqdori</th>
            <th>Birligi</th>
            <th>Amallar</th>
          </tr>
        </thead>
        <tbody>
          {products.map((item) => (
            <tr key={item._id}>
              <td>{item.name}</td>
              <td>{item.code || "-"}</td>
              <td>{getGenderLabel(item.gender)}</td>
              <td>
                <div>{item.barcode}</div>
                {Array.isArray(item.barcodeAliases) && item.barcodeAliases.length ? (
                  <small style={{ color: "#8ea4c9" }}>
                    Yana {item.barcodeAliases.length} ta shtix bor
                  </small>
                ) : null}
              </td>
              <td>{getCategoryName(item)}</td>
              <td>{getSupplierName(item)}</td>
              <td>{formatMoneyWithCurrency(item.purchasePrice)}</td>
              <td>{formatMoneyWithCurrency(item.retailPrice)}</td>
              <td>{item.paymentType || "-"} / {formatMoneyWithCurrency(item.debtAmount)}</td>
              <td>
                {normalizeUnit(item.unit) === "dona"
                  ? `${(item.sizeOptions || []).join(", ")}${item.colorOptions?.length ? ` | ${item.colorOptions.join(", ")}` : ""}`
                  : item.allowPieceSale
                    ? `1 ${normalizeUnit(item.unit)} = ${item.pieceQtyPerBase} ${item.pieceUnit}`
                    : "-"}
              </td>
              <td>{item.quantity}</td>
              <td>{normalizeUnit(item.unit)}</td>
              <td className="actions-cell">
                <button type="button" className="info-btn small action-pill icon-only-compact" onClick={() => onView(item)} title="Ko'rish" aria-label="Ko'rish">
                  <ActionIcon type="view" />
                  <span className="action-pill-text">Ko'r</span>
                </button>
                <button type="button" className="success-btn small action-pill icon-only-compact" onClick={() => onPrint(item)} title="Shtixkod" aria-label="Shtixkod">
                  <ActionIcon type="barcode" />
                  <span className="action-pill-text">Shtix</span>
                </button>
                <button type="button" className="primary-btn small action-pill icon-only-compact" onClick={() => onRestock(item)} title="Kirim" aria-label="Kirim">
                  <ActionIcon type="restock" />
                  <span className="action-pill-text">Kirim</span>
                </button>
                <button type="button" className="edit-btn small action-pill icon-only-compact" onClick={() => onEdit(item)} title="Tahrirlash" aria-label="Tahrirlash">
                  <ActionIcon type="edit" />
                  <span className="action-pill-text">Edit</span>
                </button>
                <button type="button" className="danger-btn small action-pill icon-only-compact" onClick={() => onDelete(item._id)} title="O'chirish" aria-label="O'chirish">
                  <ActionIcon type="delete" />
                  <span className="action-pill-text">O'chir</span>
                </button>
              </td>
            </tr>
          ))}
          {!products.length ? (
            <tr>
              <td colSpan="13">Mahsulot topilmadi</td>
            </tr>
          ) : null}
        </tbody>
      </table>
    </div>
  );
}
