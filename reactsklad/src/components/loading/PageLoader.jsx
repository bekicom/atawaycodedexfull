export function PageLoader({ label = "Yuklanmoqda..." }) {
  return (
    <div className="page-loader">
      <div className="spinner" />
      <span>{label}</span>
    </div>
  );
}
