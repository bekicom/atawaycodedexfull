export function CategoriesTable({ categories, onEdit, onDelete }) {
  return (
    <div className="table-panel">
      <table>
        <thead>
          <tr>
            <th>Nomi</th>
            <th>Kodi</th>
            <th>Izoh</th>
            <th>Status</th>
            <th>Amallar</th>
          </tr>
        </thead>
        <tbody>
          {categories.map((item) => (
            <tr key={item._id}>
              <td>{item.name}</td>
              <td>{item.code}</td>
              <td>{item.description || "-"}</td>
              <td>{item.isActive ? "Faol" : "O'chirilgan"}</td>
              <td className="actions-cell">
                <button type="button" className="edit-btn small" onClick={() => onEdit(item)}>edit</button>
                <button type="button" className="danger-btn small" onClick={() => onDelete(item._id)}>o'chir</button>
              </td>
            </tr>
          ))}
          {!categories.length ? (
            <tr>
              <td colSpan="5">Kategoriya topilmadi</td>
            </tr>
          ) : null}
        </tbody>
      </table>
    </div>
  );
}
