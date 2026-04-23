import { formatMoneyWithCurrency } from "../../utils/format";

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
    case "view":
      return (
        <svg {...common}>
          <path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6S2 12 2 12Z" />
          <circle cx="12" cy="12" r="3" />
        </svg>
      );
    case "pay":
      return (
        <svg {...common}>
          <path d="M12 3v18" />
          <path d="M17 7.5c0-1.9-2.2-3.5-5-3.5S7 5.6 7 7.5 9.2 11 12 11s5 1.6 5 3.5S14.8 18 12 18s-5-1.6-5-3.5" />
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

export function SuppliersTable({ suppliers, onEdit, onDelete, onView, onPay }) {
  return (
    <div className="table-panel">
      <table>
        <thead>
          <tr>
            <th>Nomi</th>
            <th>Telefon</th>
            <th>Manzil</th>
            <th>Jami kirim</th>
            <th>Qarz</th>
            <th>Amallar</th>
          </tr>
        </thead>
        <tbody>
          {suppliers.map((item) => (
            <tr key={item._id}>
              <td>{item.name}</td>
              <td>{item.phone || "-"}</td>
              <td>{item.address || "-"}</td>
              <td>{formatMoneyWithCurrency(item.stats?.totalPurchase)}</td>
              <td>{formatMoneyWithCurrency(item.stats?.totalDebt)}</td>
              <td className="actions-cell">
                <button type="button" className="ghost-btn small action-pill" onClick={() => onView(item)}>
                  <ActionIcon type="view" />
                  ko'rish
                </button>
                <button type="button" className="success-btn small action-pill" onClick={() => onPay(item)}>
                  <ActionIcon type="pay" />
                  to'lov
                </button>
                <button type="button" className="edit-btn small action-pill" onClick={() => onEdit(item)}>
                  <ActionIcon type="edit" />
                  edit
                </button>
                <button type="button" className="danger-btn small action-pill" onClick={() => onDelete(item._id)}>
                  <ActionIcon type="delete" />
                  o'chir
                </button>
              </td>
            </tr>
          ))}
          {!suppliers.length ? (
            <tr>
              <td colSpan="6">Yetkazib beruvchi topilmadi</td>
            </tr>
          ) : null}
        </tbody>
      </table>
    </div>
  );
}
