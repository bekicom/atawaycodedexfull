import { useEffect, useState } from "react";
import { ModalShell } from "../modal/ModalShell";

const initialState = {
  id: "",
  name: "",
  address: "",
};

export function StoreModal({ open, current, onClose, onSubmit, loading }) {
  const [form, setForm] = useState(initialState);

  useEffect(() => {
    if (!open) return;
    setForm(current ? {
      id: current._id,
      name: current.name || "",
      address: current.address || "",
    } : initialState);
  }, [open, current]);

  return (
    <ModalShell open={open} title={current ? "Do'konni tahrirlash" : "Yangi do'kon"} onClose={onClose} width="680px">
      <form
        className="form-grid"
        onSubmit={(event) => {
          event.preventDefault();
          onSubmit(form);
        }}
      >
        <label>
          <span>Do'kon nomi</span>
          <input value={form.name} onChange={(event) => setForm((prev) => ({ ...prev, name: event.target.value }))} required />
        </label>

        <label className="full-width">
          <span>Manzil</span>
          <input value={form.address} onChange={(event) => setForm((prev) => ({ ...prev, address: event.target.value }))} />
        </label>

        <div className="modal-footer full-width">
          <button type="button" className="ghost-btn" onClick={onClose}>Bekor qilish</button>
          <button type="submit" className="primary-btn" disabled={loading}>
            {loading ? "Saqlanmoqda..." : "Saqlash"}
          </button>
        </div>
      </form>
    </ModalShell>
  );
}
