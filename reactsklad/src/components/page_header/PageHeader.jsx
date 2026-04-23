export function PageHeader({ title, subtitle, actions }) {
  return (
    <header className="page-header">
      <div>
        <h2>{title}</h2>
        {subtitle ? <p>{subtitle}</p> : null}
      </div>
      <div className="page-actions">{actions}</div>
    </header>
  );
}
