import { useEffect, useState } from "react";
import { PageHeader } from "../../components/page_header/PageHeader";
import { PageLoader } from "../../components/loading/PageLoader";
import { ModalShell } from "../../components/modal/ModalShell";
import { useGetOverviewQuery } from "../../context/service/dashboard.service";
import { useGetProductsQuery } from "../../context/service/addproduct.service";
import { formatMoneyWithCurrency, getCategoryName, normalizeUnit } from "../../utils/format";

function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function ActionIcon({ type }) {
  const common = {
    width: 14,
    height: 14,
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: "1.8",
    strokeLinecap: "round",
    strokeLinejoin: "round",
  };

  if (type === "view") {
    return (
      <svg {...common}>
        <path d="M1.5 12s3.5-6.5 10.5-6.5S22.5 12 22.5 12 19 18.5 12 18.5 1.5 12 1.5 12Z" />
        <circle cx="12" cy="12" r="3" />
      </svg>
    );
  }

  return null;
}

function collectVariantSummary(products = []) {
  const colorMap = new Map();
  const sizeMap = new Map();

  products.forEach((product) => {
    (product?.variantStocks || []).forEach((variant) => {
      const quantity = Number(variant?.quantity || 0);
      const color = String(variant?.color || "").trim();
      const size = String(variant?.size || "").trim();

      if (color) {
        const current = colorMap.get(color) || { name: color, quantity: 0, products: new Set() };
        current.quantity += quantity;
        current.products.add(product?.name || "");
        colorMap.set(color, current);
      }

      if (size) {
        const current = sizeMap.get(size) || { name: size, quantity: 0, products: new Set() };
        current.quantity += quantity;
        current.products.add(product?.name || "");
        sizeMap.set(size, current);
      }
    });
  });

  const toRows = (map) =>
    [...map.values()]
      .map((item) => ({
        name: item.name,
        quantity: item.quantity,
        productCount: [...item.products].filter(Boolean).length,
      }))
      .sort((a, b) => a.name.localeCompare(b.name, "uz"));

  return {
    colors: toRows(colorMap),
    sizes: toRows(sizeMap),
  };
}

function formatVariantLabel(variant = {}) {
  const size = String(variant?.size || "").trim();
  const color = String(variant?.color || "").trim();
  if (size && color) return `${size} / ${color}`;
  return size || color || "-";
}

export function DashboardPage() {
  const { data, isLoading } = useGetOverviewQuery();
  const { data: productsRes } = useGetProductsQuery();
  const [categoryModalOpen, setCategoryModalOpen] = useState(false);
  const [selectedCategory, setSelectedCategory] = useState(null);
  const [categoryProducts, setCategoryProducts] = useState([]);
  const [categoryMode, setCategoryMode] = useState("products");

  const openCategory = (item, mode = "products") => {
    setSelectedCategory(item);
    setCategoryMode(mode);
    const allProducts = productsRes?.products || [];
    const nextProducts = allProducts.filter((product) => getCategoryName(product) === item.name);
    setCategoryProducts(nextProducts.length ? nextProducts : item?.products || []);
    setCategoryModalOpen(true);
  };

  useEffect(() => {
    if (!categoryModalOpen || !selectedCategory) return;

    const allProducts = productsRes?.products || [];
    const nextProducts = allProducts.filter((product) => getCategoryName(product) === selectedCategory.name);
    if (nextProducts.length) {
      setCategoryProducts(nextProducts);
      return;
    }

    if (Array.isArray(selectedCategory.products)) {
      setCategoryProducts(selectedCategory.products);
    }
  }, [categoryModalOpen, selectedCategory, productsRes?.products]);

  const downloadCategoryExcel = () => {
    const summary = collectVariantSummary(selectedCategoryProducts);
    const rows =
      categoryMode === "colors"
        ? summary.colors
        : categoryMode === "sizes"
          ? summary.sizes
          : selectedCategoryProducts.length
            ? selectedCategoryProducts
            : selectedCategory?.products || [];

    if (!rows.length) return;

    const header =
      categoryMode === "colors"
        ? `<tr><th>Rang</th><th>Miqdor</th><th>Mahsulotlar</th></tr>`
        : categoryMode === "sizes"
          ? `<tr><th>Razmer</th><th>Miqdor</th><th>Mahsulotlar</th></tr>`
          : `
      <tr>
        <th>Mahsulot</th>
        <th>Kod</th>
        <th>Miqdor</th>
        <th>Birligi</th>
        <th>Kelish</th>
        <th>Sotish</th>
      </tr>
    `;

    const body = rows
      .map((item) => {
        if (categoryMode === "colors" || categoryMode === "sizes") {
          return `
            <tr>
              <td>${escapeHtml(item.name)}</td>
              <td>${escapeHtml(item.quantity)}</td>
              <td>${escapeHtml(item.productCount)}</td>
            </tr>
          `;
        }

        return `
          <tr>
            <td>${escapeHtml(item.name)}</td>
            <td>${escapeHtml(item.code || "-")}</td>
            <td>${escapeHtml(item.quantity)}</td>
            <td>${escapeHtml(normalizeUnit(item.unit))}</td>
            <td>${escapeHtml(formatMoneyWithCurrency(item.purchasePrice))}</td>
            <td>${escapeHtml(formatMoneyWithCurrency(item.retailPrice))}</td>
          </tr>
        `;
      })
      .join("");

    const html = `
      <html>
        <head>
          <meta charset="utf-8" />
          <style>
            body { font-family: Arial, sans-serif; }
            table { border-collapse: collapse; width: 100%; }
            th, td { border: 1px solid #999; padding: 8px 10px; text-align: left; }
            th { background: #3f5f99; color: #fff; }
          </style>
        </head>
        <body>
          <h2>${escapeHtml(selectedCategory?.name || "Kategoriya")} ${escapeHtml(
            categoryMode === "colors"
              ? "ranglari"
              : categoryMode === "sizes"
                ? "razmerlari"
                : "mahsulotlari",
          )}</h2>
          <p>Mahsulotlar: ${escapeHtml(selectedCategory?.productCount || rows.length)}</p>
          <p>Miqdor: ${escapeHtml(selectedCategory?.quantity || 0)}</p>
          <p>Kelish: ${escapeHtml(formatMoneyWithCurrency(selectedCategory?.purchaseValue || 0))}</p>
          <p>Sotish: ${escapeHtml(formatMoneyWithCurrency(selectedCategory?.retailValue || 0))}</p>
          <table>
            <thead>${header}</thead>
            <tbody>${body}</tbody>
          </table>
        </body>
      </html>
    `;

    const blob = new Blob([html], { type: "application/vnd.ms-excel;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = `${(selectedCategory?.name || "kategoriya").replace(/\s+/g, "_")}.xls`;
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
  };

  const renderProductRows = () => {
    if (!selectedCategoryProducts.length) {
      return (
        <tr>
          <td colSpan="6">Bu kategoriyada mahsulot yo'q</td>
        </tr>
      );
    }

    return selectedCategoryProducts.flatMap((item) => {
      const variants = Array.isArray(item.variantStocks) ? item.variantStocks : [];
      const hasVariants = variants.length > 0;
      const baseRow = (
        <tr key={item._id}>
          <td className="category-product-name">
            <div>{item.name}</div>
            <small>{item.code || "-"}</small>
          </td>
          <td>{item.code || "-"}</td>
          <td>{item.quantity}</td>
          <td>{normalizeUnit(item.unit)}</td>
          <td>{formatMoneyWithCurrency(item.purchasePrice)}</td>
          <td>{formatMoneyWithCurrency(item.retailPrice)}</td>
        </tr>
      );

      if (!hasVariants) return [baseRow];

      const variantRows = variants.map((variant, index) => (
        <tr key={`${item._id}-variant-${index}`} className="category-variant-row">
          <td colSpan="6">
            <div className="category-variant-inline">
              <span className="category-variant-name">{formatVariantLabel(variant)}</span>
              <span>{variant.quantity}</span>
              <span>{normalizeUnit(item.unit)}</span>
              <span>-</span>
              <span>-</span>
            </div>
          </td>
        </tr>
      ));

      return [baseRow, ...variantRows];
    });
  };

  if (isLoading) return <PageLoader />;

  const counts = data?.counts || {};
  const inventorySummary = data?.inventorySummary || {};
  const selectedCategoryProducts = categoryProducts;
  const selectedCategoryVariants = collectVariantSummary(selectedCategoryProducts);

  return (
    <div className="page-stack">
      <PageHeader title="Dashboard" subtitle="Sklad bo'yicha umumiy ko'rsatkichlar" />

      <section className="stats-grid">
        <article className="stat-card"><span>Mahsulotlar</span><strong>{counts.products || 0}</strong></article>
        <article className="stat-card"><span>Kategoriyalar</span><strong>{counts.categories || 0}</strong></article>
        <article className="stat-card"><span>Bo'limlar</span><strong>{counts.sections || 0}</strong></article>
        <article className="stat-card"><span>Yetkazib beruvchilar</span><strong>{counts.suppliers || 0}</strong></article>
        <article className="stat-card"><span>Kirim hujjatlari</span><strong>{counts.purchases || 0}</strong></article>
      </section>

      <section className="stats-grid">
        <article className="stat-card">
          <span>Ombordagi kelish qiymati</span>
          <strong>{formatMoneyWithCurrency(inventorySummary.totalPurchaseValue)}</strong>
        </article>
        <article className="stat-card">
          <span>Ombordagi sotish qiymati</span>
          <strong>{formatMoneyWithCurrency(inventorySummary.totalRetailValue)}</strong>
        </article>
        <article className="stat-card">
          <span>Jami astatka soni</span>
          <strong>{inventorySummary.totalQuantity || 0}</strong>
        </article>
      </section>

      <section className="panel-box panel-box--wide">
        <h3>Bo'lim bo'yicha astatka</h3>
        <div className="mini-table-wrap">
          <table>
            <thead>
              <tr>
                <th>Bo'lim</th>
                <th>Mahsulotlar</th>
                <th>Miqdor</th>
                <th>Kelish qiymati</th>
                <th>Sotish qiymati</th>
              </tr>
            </thead>
            <tbody>
              {(inventorySummary.sectionInventory || []).map((item) => (
                <tr key={item.sectionId || item.name}>
                  <td>{item.name}</td>
                  <td>{item.productCount || 0}</td>
                  <td>{item.quantity || 0}</td>
                  <td>{formatMoneyWithCurrency(item.purchaseValue || 0)}</td>
                  <td>{formatMoneyWithCurrency(item.retailValue || 0)}</td>
                </tr>
              ))}
              {!inventorySummary.sectionInventory?.length ? (
                <tr><td colSpan="5">Bo'lim bo'yicha astatka yo'q</td></tr>
              ) : null}
            </tbody>
          </table>
        </div>
      </section>

      <section className="split-grid">
        <div className="panel-box">
          <h3>Kam qolgan mahsulotlar</h3>
          <div className="mini-table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Mahsulot</th>
                  <th>Shtixkod</th>
                  <th>Miqdori</th>
                  <th>Birligi</th>
                </tr>
              </thead>
              <tbody>
                {(data?.lowStockProducts || []).map((item) => (
                  <tr key={item._id}>
                    <td>{item.name} {item.code ? `(${item.code})` : ""}</td>
                    <td>{item.barcode}</td>
                    <td>{item.quantity}</td>
                    <td>{normalizeUnit(item.unit)}</td>
                  </tr>
                ))}
                {!data?.lowStockProducts?.length ? <tr><td colSpan="4">Kam qolgan mahsulot yo'q</td></tr> : null}
              </tbody>
            </table>
          </div>
        </div>

        <div className="panel-box panel-box--wide">
          <h3>Kategoriya bo'yicha astatka</h3>
          <div className="mini-table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Kategoriya</th>
                  <th>Mahsulot</th>
                  <th>Miqdor</th>
                  <th>Kelish qiymati</th>
                  <th>Sotish qiymati</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {(inventorySummary.categoryInventory || []).map((item) => (
                  <tr key={item.name}>
                    <td>{item.name}</td>
                    <td>{item.productCount}</td>
                    <td>{item.quantity}</td>
                    <td>{formatMoneyWithCurrency(item.purchaseValue)}</td>
                    <td>{formatMoneyWithCurrency(item.retailValue)}</td>
                    <td>
                      <div className="category-action-group">
                        <button
                          type="button"
                          className="success-btn small action-pill icon-only-compact"
                          title="Razmerlarni ko'rish"
                          aria-label="Razmerlarni ko'rish"
                          onClick={() => openCategory(item, "sizes")}
                        >
                          <span className="action-pill-text">Razmer</span>
                        </button>
                        <button
                          type="button"
                          className="info-btn small action-pill icon-only-compact"
                          title="Ranglarni ko'rish"
                          aria-label="Ranglarni ko'rish"
                          onClick={() => openCategory(item, "colors")}
                        >
                          <span className="action-pill-text">Rang</span>
                        </button>
                        <button
                          type="button"
                          className="info-btn small action-pill icon-only-compact"
                          title="Mahsulotlarni ko'rish"
                          aria-label="Mahsulotlarni ko'rish"
                          onClick={() => openCategory(item, "products")}
                        >
                          <ActionIcon type="view" />
                          <span className="action-pill-text">Ko'r</span>
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
                {!inventorySummary.categoryInventory?.length ? <tr><td colSpan="6">Kategoriya bo'yicha astatka yo'q</td></tr> : null}
              </tbody>
            </table>
          </div>
        </div>
      </section>

      <ModalShell
        open={categoryModalOpen}
        title={`${selectedCategory?.name || "Kategoriya"} ${
          categoryMode === "colors"
            ? "ranglari"
            : categoryMode === "sizes"
              ? "razmerlari"
              : "mahsulotlari"
        }`}
        onClose={() => {
          setCategoryModalOpen(false);
          setSelectedCategory(null);
          setCategoryProducts([]);
          setCategoryMode("products");
        }}
        width="1080px"
      >
        <div className="category-products-modal">
          <div className="category-products-summary">
            <div className="category-products-summary-left">
              <span>Mahsulotlar: {selectedCategory?.productCount || 0}</span>
              <span>Miqdor: {selectedCategory?.quantity || 0}</span>
              <span>Kelish: {formatMoneyWithCurrency(selectedCategory?.purchaseValue || 0)}</span>
              <span>Sotish: {formatMoneyWithCurrency(selectedCategory?.retailValue || 0)}</span>
            </div>
            <button type="button" className="success-btn small" onClick={downloadCategoryExcel}>
              Excel
            </button>
          </div>

          {categoryMode !== "products" ? (
            <div className="category-variant-note">
              {categoryMode === "colors"
                ? "Bu yerda shu kategoriyadagi ranglar bo'yicha jami miqdor ko'rsatiladi."
                : "Bu yerda shu kategoriyadagi razmerlar bo'yicha jami miqdor ko'rsatiladi."}
            </div>
          ) : null}

          {categoryMode === "products" ? (
            <div className="mini-table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Mahsulot</th>
                    <th>Kod</th>
                    <th>Miqdor</th>
                    <th>Birligi</th>
                    <th>Kelish</th>
                    <th>Sotish</th>
                  </tr>
                </thead>
                <tbody>
                  {renderProductRows()}
                </tbody>
              </table>
            </div>
          ) : (
            <div className="mini-table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>{categoryMode === "colors" ? "Rang" : "Razmer"}</th>
                    <th>Jami miqdor</th>
                    <th>Mahsulotlar soni</th>
                  </tr>
                </thead>
                <tbody>
                  {(categoryMode === "colors"
                    ? selectedCategoryVariants.colors
                    : selectedCategoryVariants.sizes
                  ).length ? (
                    (categoryMode === "colors"
                      ? selectedCategoryVariants.colors
                      : selectedCategoryVariants.sizes
                    ).map((item) => (
                      <tr key={item.name}>
                        <td>
                          <strong>{categoryMode === "colors" ? "Rang" : "Razmer"}:</strong> {item.name}
                        </td>
                        <td>{item.quantity}</td>
                        <td>{item.productCount}</td>
                      </tr>
                    ))
                  ) : (
                    <tr>
                      <td colSpan="3">Variant ma'lumotlari topilmadi</td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </ModalShell>
    </div>
  );
}
