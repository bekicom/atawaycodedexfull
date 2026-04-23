import { useMemo, useState } from "react";
import { formatDate, formatDateTime, formatMoneyWithCurrency } from "../../utils/format";

export function PurchasesTable({ purchases }) {
  const groupedPurchases = useMemo(() => {
    const grouped = purchases.reduce((acc, item) => {
      const key = item.purchasedAt ? new Date(item.purchasedAt).toISOString().slice(0, 10) : "unknown";
      if (!acc[key]) acc[key] = [];
      acc[key].push(item);
      return acc;
    }, {});

    return Object.entries(grouped).map(([dateKey, items]) => ({
      dateKey,
      label: dateKey === "unknown" ? "Sana yo'q" : formatDate(dateKey),
      items,
      totalQuantity: items.reduce((sum, item) => sum + Number(item.quantity || 0), 0),
      totalAmount: items.reduce((sum, item) => sum + Number(item.totalCost || 0), 0),
      totalDebt: items.reduce((sum, item) => sum + Number(item.debtAmount || 0), 0),
    }));
  }, [purchases]);

  const [openDate, setOpenDate] = useState(() => groupedPurchases[0]?.dateKey || "");

  if (!purchases.length) {
    return (
      <div className="table-panel">
        <table>
          <tbody>
            <tr>
              <td>Kirimlar topilmadi</td>
            </tr>
          </tbody>
        </table>
      </div>
    );
  }

  return (
    <div className="purchase-card-stack">
      {groupedPurchases.map((group) => {
        const isOpen = openDate === group.dateKey;
        return (
          <section key={group.dateKey} className="purchase-date-card">
            <button
              type="button"
              className={`purchase-date-head ${isOpen ? "open" : ""}`.trim()}
              onClick={() => setOpenDate((prev) => (prev === group.dateKey ? "" : group.dateKey))}
            >
              <div>
                <strong>{group.label}</strong>
                <p>{group.items.length} ta kirim hujjati</p>
              </div>
              <div className="purchase-date-meta">
                <span>Miqdor: {group.totalQuantity}</span>
                <span>Jami: {formatMoneyWithCurrency(group.totalAmount)}</span>
                <span>Qarz: {formatMoneyWithCurrency(group.totalDebt)}</span>
                <span className="purchase-date-caret">{isOpen ? "-" : "+"}</span>
              </div>
            </button>

            {isOpen ? (
              <div className="table-panel">
                <table>
                  <thead>
                    <tr>
                      <th>Hujjat</th>
                      <th>Mahsulot</th>
                      <th>Supplier</th>
                      <th>Turi</th>
                      <th>Miqdori</th>
                      <th>Jami</th>
                      <th>To'langan</th>
                      <th>Qarz</th>
                      <th>Sana</th>
                    </tr>
                  </thead>
                  <tbody>
                    {group.items.map((item) => (
                      <tr key={item._id}>
                        <td>{item.invoiceNumber}</td>
                        <td>{item.productName} {item.productModel ? `(${item.productModel})` : ""}</td>
                        <td>{typeof item.supplierId === "object" ? item.supplierId?.name || "-" : "-"}</td>
                        <td>{item.entryType}</td>
                        <td>{item.quantity}</td>
                        <td>{formatMoneyWithCurrency(item.totalCost)}</td>
                        <td>{formatMoneyWithCurrency(item.paidAmount)}</td>
                        <td>{formatMoneyWithCurrency(item.debtAmount)}</td>
                        <td>{formatDateTime(item.purchasedAt)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            ) : null}
          </section>
        );
      })}
    </div>
  );
}
