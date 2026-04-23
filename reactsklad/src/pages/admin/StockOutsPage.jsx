import { useMemo, useState } from "react";
import { PageHeader } from "../../components/page_header/PageHeader";
import { PageLoader } from "../../components/loading/PageLoader";
import { useGetCategoriesQuery } from "../../context/service/master.service";
import { useGetProductsQuery } from "../../context/service/addproduct.service";
import { useCreateStockOutBulkMutation, useGetStockOutsQuery } from "../../context/service/purchase.service";
import { formatDateTime, formatMoneyWithCurrency, getCategoryName, normalizeUnit } from "../../utils/format";
import { getApiErrorMessage } from "../../context/loading";

function isVariantProduct(product) {
  return Array.isArray(product?.variantStocks) && product.variantStocks.length > 0;
}

function createVariantDrafts(product) {
  return (product?.variantStocks || []).map((item) => ({
    size: item.size,
    color: item.color || "",
    available: Number(item.quantity || 0),
    quantity: "",
  }));
}

function buildCartItem(product, variantStocks = []) {
  return {
    productId: product._id,
    name: product.name,
    code: product.code || product.model,
    barcode: product.barcode,
    categoryName: getCategoryName(product),
    purchasePrice: Number(product.purchasePrice || 0),
    stock: Number(product.quantity || 0),
    unit: product.unit,
    quantity: variantStocks.length ? "" : 1,
    variantStocks,
  };
}

function getItemQuantity(item) {
  if (item.variantStocks?.length) {
    return item.variantStocks.reduce((sum, variant) => sum + Number(variant.quantity || 0), 0);
  }
  return Number(item.quantity || 0);
}

export function StockOutsPage() {
  const [productQuery, setProductQuery] = useState("");
  const [categoryId, setCategoryId] = useState("");
  const [historyFilter, setHistoryFilter] = useState({
    q: "",
    dateFrom: "",
    dateTo: "",
  });
  const [note, setNote] = useState("");
  const [cart, setCart] = useState([]);
  const [pageError, setPageError] = useState("");

  const { data: categoriesRes } = useGetCategoriesQuery();
  const { data: productsRes, isLoading: productsLoading } = useGetProductsQuery({ categoryId });
  const { data: stockOutRes, isLoading: stockOutsLoading } = useGetStockOutsQuery(historyFilter);
  const [createStockOutBulk, { isLoading: creating }] = useCreateStockOutBulkMutation();

  const categories = categoriesRes?.categories || [];
  const products = useMemo(
    () =>
      (productsRes?.products || []).filter((item) =>
        `${item.name || ""} ${item.code || item.model || ""} ${item.barcode || ""}`
          .toLowerCase()
          .includes(productQuery.toLowerCase()),
      ),
    [productsRes, productQuery],
  );
  const stockOuts = stockOutRes?.stockOuts || [];
  const cartTotal = useMemo(() => cart.reduce((sum, item) => sum + getItemQuantity(item), 0), [cart]);
  const cartValue = useMemo(
    () => cart.reduce((sum, item) => sum + (getItemQuantity(item) * Number(item.purchasePrice || 0)), 0),
    [cart],
  );

  const addToCart = (product) => {
    setCart((prev) => {
      if (prev.some((item) => item.productId === product._id)) return prev;
      return [
        ...prev,
        buildCartItem(product, isVariantProduct(product) ? createVariantDrafts(product) : []),
      ];
    });
  };

  const addManyToCart = (items) => {
    setCart((prev) => {
      const next = [...prev];
      for (const product of items) {
        if (next.some((item) => item.productId === product._id)) continue;
        next.push(buildCartItem(product, isVariantProduct(product) ? createVariantDrafts(product) : []));
      }
      return next;
    });
  };

  const updateCartQuantity = (productId, value) => {
    setCart((prev) =>
      prev.map((item) => {
        if (item.productId !== productId) return item;
        const nextValue = value === "" ? "" : Math.max(0, Number(value));
        return { ...item, quantity: nextValue };
      }),
    );
  };

  const updateCartVariantQuantity = (productId, index, value) => {
    setCart((prev) =>
      prev.map((item) => {
        if (item.productId !== productId) return item;
        return {
          ...item,
          variantStocks: (item.variantStocks || []).map((variant, variantIndex) =>
            variantIndex === index
              ? { ...variant, quantity: value === "" ? "" : Math.max(0, Number(value)) }
              : variant,
          ),
        };
      }),
    );
  };

  const submitStockOut = async () => {
    setPageError("");
    try {
      await createStockOutBulk({
        note,
        items: cart
          .filter((item) => getItemQuantity(item) > 0)
          .map((item) => ({
            productId: item.productId,
            quantity: getItemQuantity(item),
            variantStocks: (item.variantStocks || [])
              .filter((variant) => Number(variant.quantity || 0) > 0)
              .map((variant) => ({
                size: variant.size,
                color: variant.color,
                quantity: Number(variant.quantity || 0),
              })),
          })),
      }).unwrap();
      setCart([]);
      setNote("");
    } catch (error) {
      setPageError(getApiErrorMessage(error));
    }
  };

  if (productsLoading || stockOutsLoading) return <PageLoader />;

  return (
    <div className="page-stack">
      <PageHeader
        title="Chiqim"
        subtitle="Dokonga yuborish oynasi kabi: mahsulot tanlang, rangini tanlang, chiqim qiling"
      />

      {pageError ? <div className="error-box">{pageError}</div> : null}

      <section className="panel-box">
        <div className="filters-row wrap">
          <select className="search-input narrow" value={categoryId} onChange={(event) => setCategoryId(event.target.value)}>
            <option value="">Barcha kategoriyalar</option>
            {categories.map((item) => <option key={item._id} value={item._id}>{item.name}</option>)}
          </select>
          <button type="button" className="ghost-btn" onClick={() => addManyToCart(products)}>
            Ko'rinayotganlarni qo'shish
          </button>
          <button type="button" className="ghost-btn" onClick={() => addManyToCart(productsRes?.products || [])}>
            Kategoriyani qo'shish
          </button>
          <input
            className="search-input narrow"
            placeholder="Mahsulot qidirish..."
            value={productQuery}
            onChange={(event) => setProductQuery(event.target.value)}
          />
          <input
            className="search-input"
            placeholder="Izoh: masalan supplierga qaytarildi"
            value={note}
            onChange={(event) => setNote(event.target.value)}
          />
        </div>

        <div className="split-grid">
          <div className="panel-box">
            <h3>Kategoriyadagi mahsulotlar</h3>
            <div className="mini-table-wrap transfer-table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Mahsulot</th>
                    <th>Shtixkod</th>
                    <th>Astatka</th>
                    <th>Narx</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  {products.map((item) => (
                    <tr key={item._id}>
                      <td>{item.name} {item.code ? `(${item.code})` : ""}</td>
                      <td>{item.barcode}</td>
                      <td>{item.quantity} {normalizeUnit(item.unit)}</td>
                      <td>{formatMoneyWithCurrency(item.purchasePrice)}</td>
                      <td>
                        <button type="button" className="primary-btn small" onClick={() => addToCart(item)}>
                          + Qo'shish
                        </button>
                      </td>
                    </tr>
                  ))}
                  {!products.length ? <tr><td colSpan="5">Bu kategoriyada mahsulot yo'q</td></tr> : null}
                </tbody>
              </table>
            </div>
          </div>

          <div className="panel-box">
            <h3>Karzinka</h3>
            <div className="mini-table-wrap transfer-table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Mahsulot</th>
                    <th>Astatka</th>
                    <th>Miqdor</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  {cart.map((item) => (
                    <tr key={item.productId}>
                      <td>{item.name} {item.code ? `(${item.code})` : ""}</td>
                      <td>{item.stock} {normalizeUnit(item.unit)}</td>
                      <td>
                        {item.variantStocks?.length ? (
                          <div className="variant-cart-grid">
                            {item.variantStocks.map((variant, index) => (
                              <label key={`${variant.size}-${variant.color || "none"}`} className="variant-cart-row">
                                <span>{variant.size}{variant.color ? ` / ${variant.color}` : ""} <small>({variant.available})</small></span>
                                <input
                                  className="search-input narrow"
                                  type="number"
                                  min="0"
                                  max={variant.available}
                                  value={variant.quantity}
                                  onChange={(event) => {
                                    const raw = event.target.value;
                                    const next = raw === "" ? "" : Math.min(Number(raw), variant.available);
                                    updateCartVariantQuantity(item.productId, index, next);
                                  }}
                                />
                              </label>
                            ))}
                          </div>
                        ) : (
                          <input
                            className="search-input narrow"
                            type="number"
                            min="1"
                            max={item.stock}
                            value={item.quantity}
                            onChange={(event) =>
                              updateCartQuantity(
                                item.productId,
                                event.target.value === "" ? "" : Math.min(Number(event.target.value), item.stock),
                              )
                            }
                          />
                        )}
                      </td>
                      <td>
                        <button
                          type="button"
                          className="danger-btn small"
                          onClick={() => setCart((prev) => prev.filter((row) => row.productId !== item.productId))}
                        >
                          o'chir
                        </button>
                      </td>
                    </tr>
                  ))}
                  {!cart.length ? <tr><td colSpan="4">Hali mahsulot qo'shilmagan</td></tr> : null}
                </tbody>
              </table>
            </div>

            <div className="transfer-summary">
              <strong>Jami miqdor: {cartTotal}</strong>
              <strong>Jami qiymat: {formatMoneyWithCurrency(cartValue)}</strong>
            </div>

            <div className="modal-footer">
              <button type="button" className="ghost-btn" onClick={() => { setCart([]); }}>
                Tozalash
              </button>
              <button
                type="button"
                className="primary-btn"
                onClick={submitStockOut}
                disabled={creating || !cart.some((item) => getItemQuantity(item) > 0)}
              >
                {creating ? "Saqlanmoqda..." : "Chiqim qilish"}
              </button>
            </div>
          </div>
        </div>
      </section>

      <section className="panel-box">
        <h3>Chiqim tarixi</h3>
        <div className="filters-row wrap">
          <input
            className="search-input"
            placeholder="Qidirish..."
            value={historyFilter.q}
            onChange={(event) => setHistoryFilter((prev) => ({ ...prev, q: event.target.value }))}
          />
          <input
            className="search-input narrow"
            type="date"
            value={historyFilter.dateFrom}
            onChange={(event) => setHistoryFilter((prev) => ({ ...prev, dateFrom: event.target.value }))}
          />
          <input
            className="search-input narrow"
            type="date"
            value={historyFilter.dateTo}
            onChange={(event) => setHistoryFilter((prev) => ({ ...prev, dateTo: event.target.value }))}
          />
        </div>
        <div className="table-panel">
          <table>
            <thead>
              <tr>
                <th>Hujjat</th>
                <th>Mahsulot</th>
                <th>Miqdor</th>
                <th>Summa</th>
                <th>Izoh</th>
                <th>Sana</th>
                <th>Xodim</th>
              </tr>
            </thead>
            <tbody>
              {stockOuts.map((item) => (
                <tr key={item._id}>
                  <td>{item.invoiceNumber}</td>
                  <td>{item.productName} {item.productModel ? `(${item.productModel})` : ""}</td>
                  <td>{item.quantity} {normalizeUnit(item.unit)}</td>
                  <td>{formatMoneyWithCurrency(item.totalCost)}</td>
                  <td className="cell-wrap">{item.note || "-"}</td>
                  <td>{formatDateTime(item.purchasedAt)}</td>
                  <td>{item.createdBy || "-"}</td>
                </tr>
              ))}
              {!stockOuts.length ? <tr><td colSpan="7">Chiqim tarixi hali yo'q</td></tr> : null}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}
