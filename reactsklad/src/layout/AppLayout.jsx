import { NavLink, Outlet } from "react-router-dom";
import { NAV_ITEMS } from "../index";
import { useAuth } from "../context/AuthContext";

function SidebarIcon({ name }) {
  const common = {
    width: 18,
    height: 18,
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: "1.8",
    strokeLinecap: "round",
    strokeLinejoin: "round",
  };

  switch (name) {
    case "dashboard":
      return (
        <svg {...common}>
          <path d="M4 13h7V4H4zM13 20h7v-9h-7zM13 11h7V4h-7zM4 20h7v-5H4z" />
        </svg>
      );
    case "products":
      return (
        <svg {...common}>
          <path d="M12 3 4 7v10l8 4 8-4V7l-8-4Z" />
          <path d="M4 7l8 4 8-4M12 11v10" />
        </svg>
      );
    case "categories":
      return (
        <svg {...common}>
          <path d="M4 5h7v7H4zM13 5h7v7h-7zM4 14h7v5H4zM13 14h7v5h-7z" />
        </svg>
      );
    case "sections":
      return (
        <svg {...common}>
          <path d="M4 6h16M4 12h16M4 18h16" />
          <path d="M8 4v16M16 4v16" />
        </svg>
      );
    case "stores":
      return (
        <svg {...common}>
          <path d="M3 10h18" />
          <path d="M5 10V6l7-3 7 3v4" />
          <path d="M5 10v10h14V10" />
          <path d="M10 20v-5h4v5" />
        </svg>
      );
    case "suppliers":
      return (
        <svg {...common}>
          <path d="M3 20h18" />
          <path d="M5 20V8l7-4 7 4v12" />
          <path d="M9 12h.01M15 12h.01M9 16h.01M15 16h.01" />
        </svg>
      );
    case "purchases":
      return (
        <svg {...common}>
          <path d="M6 4h12l-1 14H7L6 4Z" />
          <path d="M9 4V3h6v1M9 9h6M9 13h6" />
        </svg>
      );
    case "transfers":
      return (
        <svg {...common}>
          <path d="M4 12h12" />
          <path d="m12 6 6 6-6 6" />
          <path d="M4 6h5" />
          <path d="M4 18h5" />
        </svg>
      );
    case "stockouts":
      return (
        <svg {...common}>
          <path d="M4 12h12" />
          <path d="m10 6-6 6 6 6" />
          <path d="M20 6h-5" />
          <path d="M20 18h-5" />
        </svg>
      );
    case "storeReturns":
      return (
        <svg {...common}>
          <path d="M20 8V4h-4" />
          <path d="M4 16v4h4" />
          <path d="M4 8a8 8 0 0 1 13.66-5.66L20 4" />
          <path d="M20 16a8 8 0 0 1-13.66 5.66L4 20" />
        </svg>
      );
    case "logout":
      return (
        <svg {...common}>
          <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" />
          <path d="m16 17 5-5-5-5" />
          <path d="M21 12H9" />
        </svg>
      );
    case "settings":
      return (
        <svg {...common}>
          <path d="M12 3v3" />
          <path d="M12 18v3" />
          <path d="m4.93 4.93 2.12 2.12" />
          <path d="m16.95 16.95 2.12 2.12" />
          <path d="M3 12h3" />
          <path d="M18 12h3" />
          <path d="m4.93 19.07 2.12-2.12" />
          <path d="m16.95 7.05 2.12-2.12" />
          <circle cx="12" cy="12" r="3.5" />
        </svg>
      );
    default:
      return null;
  }
}

export function AppLayout() {
  const { logout } = useAuth();

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand-block brand-block-simple">
          <h1>ATAWAY</h1>
        </div>

        <nav className="sidebar-nav">
          {NAV_ITEMS.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              end={item.to === "/"}
              className={({ isActive }) => `sidebar-link ${isActive ? "active" : ""}`.trim()}
            >
              <span className="sidebar-link-icon">
                <SidebarIcon name={item.icon} />
              </span>
              {item.label}
            </NavLink>
          ))}
        </nav>

        <div className="sidebar-user">
          <button type="button" className="danger-outline-btn logout-btn" onClick={logout}>
            <span className="sidebar-link-icon">
              <SidebarIcon name="logout" />
            </span>
            Chiqish
          </button>
        </div>
      </aside>

      <section className="workspace">
        <Outlet />
      </section>
    </div>
  );
}
