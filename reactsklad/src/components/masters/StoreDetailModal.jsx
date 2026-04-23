import { ModalShell } from "../modal/ModalShell";
import { formatMoneyWithCurrency } from "../../utils/format";

export function StoreDetailModal({ open, onClose, detail }) {
  const store = detail?.store;
  const inventory = detail?.inventory || [];
  const totals = detail?.totals || {};
  const transfers = detail?.transfers || [];

  return (
    <ModalShell open={open} title={store ? `${store.name} ombori` : "Do'kon ombori"} onClose={onClose} width="1180px">
      <div className="page-stack">
        <div className="detail-grid">
          <div className="detail-card">
            <strong>{store?.name || "-"}</strong>
            <p>ID kodi: {store?.storeCode || "-"}</p>
            <p>Manzil: {store?.address || "-"}</p>
          </div>
          <div className="detail-card">
            <p>Jami mahsulot soni: {totals.totalQuantity || 0}</p>
            <p>Jami qiymat: {formatMoneyWithCurrency(totals.totalValue)}</p>
            <p>Transferlar soni: {transfers.length}</p>
          </div>
        </div>

        <div className="panel-box">
          <h3>Do'kon astatkasi</h3>
          <div className="mini-table-wrap tall-table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Mahsulot</th>
                  <th>Shtixkod</th>
                  <th>Miqdori</th>
                  <th>Birligi</th>
                  <th>Jami qiymat</th>
                </tr>
              </thead>
              <tbody>
                {inventory.map((item) => (
                  <tr key={`${item.productId || item.barcode}-${item.name}`}>
                    <td>{item.name} {item.model ? `(${item.model})` : ""}</td>
                    <td>{item.barcode || "-"}</td>
                    <td>{item.quantity}</td>
                    <td>{item.unit || "-"}</td>
                    <td>{formatMoneyWithCurrency(item.totalValue)}</td>
                  </tr>
                ))}
                {!inventory.length ? <tr><td colSpan="5">Hali bu do'konga transfer bo'lmagan</td></tr> : null}
              </tbody>
            </table>
          </div>
        </div>

        <div className="panel-box">
          <h3>Yuborilgan transferlar</h3>
          <div className="mini-table-wrap tall-table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Hujjat</th>
                  <th>Mahsulotlar</th>
                  <th>Miqdor</th>
                  <th>Jami</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {transfers.map((item) => (
                  <tr key={item._id}>
                    <td>{item.transferNumber}</td>
                    <td className="cell-wrap">{item.items.map((row) => row.name).join(", ")}</td>
                    <td>{item.totalQuantity}</td>
                    <td>{formatMoneyWithCurrency(item.totalValue)}</td>
                    <td>{item.status}</td>
                  </tr>
                ))}
                {!transfers.length ? <tr><td colSpan="5">Transfer topilmadi</td></tr> : null}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </ModalShell>
  );
}
