import { useEffect, useState } from "react";
import { ModalShell } from "../modal/ModalShell";

const initialState = {
  id: "",
  name: "",
  description: "",
};

export function CategoryModal({ open, current, onClose, onSubmit, loading }) {
  const [form, setForm] = useState(initialState);

  useEffect(() => {
    if (!open) return;
    setForm(current ? {
      id: current._id,
      name: current.name || "",
      description: current.description || "",
    } : initialState);
  }, [open, current]);

  return (
    <ModalShell open={open} title={current ? "Kategoriyani tahrirlash" : "Yangi kategoriya"} onClose={onClose} width="560px">
      <form
        className="form-grid"
        onSubmit={(event) => {
          event.preventDefault();
          onSubmit(form);
        }}
      >
        <label>
          <span>Nomi</span>
          <input value={form.name} onChange={(event) => setForm((prev) => ({ ...prev, name: event.target.value }))} required />
        </label>

        <label className="full-width">
          <span>Izoh</span>
          <textarea rows="4" value={form.description} onChange={(event) => setForm((prev) => ({ ...prev, description: event.target.value }))} />
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
