import { useEffect, useState } from "react";
import { ModalShell } from "../modal/ModalShell";
import { formatDateTime, formatMoneyWithCurrency } from "../../utils/format";

export function SupplierPaymentModal({ open, supplier, onClose, onSubmit, loading }) {
  const [form, setForm] = useState({ amount: "", note: "" });

  useEffect(() => {
    if (!open) return;
    setForm({ amount: "", note: "" });
  }, [open]);

  return (
    <ModalShell open={open} title={`${supplier?.name || ""} qarzini yopish`} onClose={onClose} width="900px">
      <div className="supplier-detail-grid">
        <div className="detail-card">
          <h4>Umumiy ko'rsatkichlar</h4>
          <p>Jami kirim: {formatMoneyWithCurrency(supplier?.stats?.totalPurchase)}</p>
          <p>Jami to'langan: {formatMoneyWithCurrency(supplier?.stats?.supplierPaid)}</p>
          <p>Qoldiq qarz: {formatMoneyWithCurrency(supplier?.stats?.totalDebt)}</p>
        </div>

        <div className="detail-card">
          <h4>To'lov kiritish</h4>
          <form
            className="form-grid"
            onSubmit={(event) => {
              event.preventDefault();
              onSubmit(form);
            }}
          >
            <label>
              <span>Summa</span>
              <input type="number" min="0" step="0.01" value={form.amount} onChange={(event) => setForm((prev) => ({ ...prev, amount: event.target.value }))} required />
            </label>
            <label className="full-width">
              <span>Izoh</span>
              <textarea rows="3" value={form.note} onChange={(event) => setForm((prev) => ({ ...prev, note: event.target.value }))} />
            </label>
            <div className="modal-footer full-width">
              <button type="button" className="ghost-btn" onClick={onClose}>Yopish</button>
              <button type="submit" className="primary-btn" disabled={loading}>
                {loading ? "Saqlanmoqda..." : "To'lovni saqlash"}
              </button>
            </div>
          </form>
        </div>

        <div className="detail-card full-width">
          <h4>Oxirgi to'lovlar</h4>
          <div className="mini-table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Sana</th>
                  <th>Summa</th>
                  <th>Izoh</th>
                </tr>
              </thead>
              <tbody>
                {(supplier?.payments || []).map((payment) => (
                  <tr key={payment._id}>
                    <td>{formatDateTime(payment.paidAt)}</td>
                    <td>{formatMoneyWithCurrency(payment.amount)}</td>
                    <td>{payment.note || "-"}</td>
                  </tr>
                ))}
                {!supplier?.payments?.length ? (
                  <tr>
                    <td colSpan="3">To'lovlar hali yo'q</td>
                  </tr>
                ) : null}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </ModalShell>
  );
}
