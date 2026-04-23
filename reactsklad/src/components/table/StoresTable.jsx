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

export function StoresTable({ stores, onView, onEdit, onDelete }) {
  return (
    <div className="table-panel">
      <table>
        <thead>
          <tr>
            <th>Do'kon nomi</th>
            <th>ID kodi</th>
            <th>Manzil</th>
            <th>Status</th>
            <th>Amallar</th>
          </tr>
        </thead>
        <tbody>
          {stores.map((item) => (
            <tr key={item._id}>
              <td>{item.name}</td>
              <td>{item.storeCode}</td>
              <td>{item.address || "-"}</td>
              <td>{item.isActive ? "Faol" : "O'chirilgan"}</td>
              <td className="actions-cell">
                <button type="button" className="ghost-btn small action-pill" onClick={() => onView(item)}>
                  <ActionIcon type="view" />
                  ko'rish
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
          {!stores.length ? (
            <tr>
              <td colSpan="5">Do'kon topilmadi</td>
            </tr>
          ) : null}
        </tbody>
      </table>
    </div>
  );
}
