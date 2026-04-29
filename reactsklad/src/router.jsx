import { Navigate, Route, Routes } from "react-router-dom";
import { useAuth } from "./context/AuthContext";
import { AppLayout } from "./layout/AppLayout";
import { DashboardPage } from "./pages/admin/DashboardPage";
import { ProductsPage } from "./pages/admin/ProductsPage";
import { CategoriesPage } from "./pages/admin/CategoriesPage";
import { SectionsPage } from "./pages/admin/SectionsPage";
import { SuppliersPage } from "./pages/admin/SuppliersPage";
import { PurchasesPage } from "./pages/admin/PurchasesPage";
import { StockOutsPage } from "./pages/admin/StockOutsPage";
import { StoresPage } from "./pages/admin/StoresPage";
import { TransfersPage } from "./pages/admin/TransfersPage";
import { StoreReturnsPage } from "./pages/admin/StoreReturnsPage";
import { SettingsPage } from "./pages/admin/SettingsPage";
import { LoginPage } from "./pages/auth/LoginPage";

function ProtectedRoute({ children }) {
  const { token } = useAuth();
  if (!token) return <Navigate to="/login" replace />;
  return children;
}

export function AppRouter() {
  const { token } = useAuth();

  return (
    <Routes>
      <Route path="/login" element={token ? <Navigate to="/" replace /> : <LoginPage />} />
      <Route
        path="/"
        element={(
          <ProtectedRoute>
            <AppLayout />
          </ProtectedRoute>
        )}
      >
        <Route index element={<DashboardPage />} />
        <Route path="products" element={<ProductsPage />} />
        <Route path="categories" element={<CategoriesPage />} />
        <Route path="sections" element={<SectionsPage />} />
        <Route path="stores" element={<StoresPage />} />
        <Route path="suppliers" element={<SuppliersPage />} />
        <Route path="purchases" element={<PurchasesPage />} />
        <Route path="stock-outs" element={<StockOutsPage />} />
        <Route path="transfers" element={<TransfersPage />} />
        <Route path="store-returns" element={<StoreReturnsPage />} />
        <Route path="settings" element={<SettingsPage />} />
      </Route>
      <Route path="*" element={<Navigate to={token ? "/" : "/login"} replace />} />
    </Routes>
  );
}
