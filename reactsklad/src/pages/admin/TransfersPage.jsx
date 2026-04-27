import { useMemo, useState } from "react";
import { PageHeader } from "../../components/page_header/PageHeader";
import { PageLoader } from "../../components/loading/PageLoader";
import { ModalShell } from "../../components/modal/ModalShell";
import { useGetCategoriesQuery } from "../../context/service/master.service";
import { useGetProductsQuery } from "../../context/service/addproduct.service";
import { useGetStoresQuery } from "../../context/service/store.service";
import { useCreateTransferMutation, useGetTransfersQuery } from "../../context/service/transfer.service";
import { formatMoneyWithCurrency, getCategoryName, normalizeUnit } from "../../utils/format";
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
    purchasePrice: product.purchasePrice,
    stock: product.quantity,
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

export function TransfersPage() {
  const [productQuery, setProductQuery] = useState("");
  const [categoryId, setCategoryId] = useState("");
  const [storeId, setStoreId] = useState("");
  const [transferQuery, setTransferQuery] = useState("");
  const [cart, setCart] = useState([]);
  const [pageError, setPageError] = useState("");
  const [historyOpen, setHistoryOpen] = useState(false);

  const { data: categoriesRes } = useGetCategoriesQuery();
  const { data: storesRes } = useGetStoresQuery();
  const { data: productsRes, isLoading: productsLoading } = useGetProductsQuery({ categoryId });
  const { data: transfersRes, isLoading: transfersLoading } = useGetTransfersQuery({ q: transferQuery });
  const [createTransfer, { isLoading: creating }] = useCreateTransferMutation();

  const categories = categoriesRes?.categories || [];
  const stores = storesRes?.stores || [];
  const products = useMemo(
    () =>
      (productsRes?.products || []).filter((item) =>
        `${item.name || ""} ${item.code || item.model || ""} ${item.barcode || ""}`
          .toLowerCase()
          .includes(productQuery.toLowerCase()),
      ),
    [productsRes, productQuery],
  );
  const visibleProducts = products;
  const transfers = transfersRes?.transfers || [];
  const selectedStore = stores.find((item) => item._id === storeId);

  const cartTotal = useMemo(
    () => cart.reduce((sum, item) => sum + getItemQuantity(item), 0),
    [cart],
  );

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

  const addVisibleToCart = () => {
    addManyToCart(visibleProducts);
  };

  const addCategoryToCart = () => {
    addManyToCart(productsRes?.products || []);
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

  const selectAllVariantColorsInCart = () => {
    setCart((prev) =>
      prev.map((item) => {
        if (!item.variantStocks?.length) return item;
        return {
          ...item,
          variantStocks: (item.variantStocks || []).map((variant) => {
            const available = Number(variant.available || 0);
            if (available <= 0) {
              return { ...variant, quantity: "" };
            }
            return { ...variant, quantity: available };
          }),
        };
      }),
    );
  };

  const submitTransfer = async () => {
    setPageError("");
    try {
      await createTransfer({
        storeId: selectedStore?._id || "",
        storeCode: selectedStore?.storeCode || "",
        storeName: selectedStore?.name || "",
        items: cart
          .filter((item) => getItemQuantity(item) > 0)
          .map((item) => ({
            productId: item.productId,
            quantity: getItemQuantity(item),
            variantStocks: item.variantStocks || [],
          })),
      }).unwrap();
      setCart([]);
      setStoreId("");
    } catch (error) {
      setPageError(getApiErrorMessage(error));
    }
  };

  if (productsLoading || transfersLoading) return <PageLoader />;

  return (
    <div className="page-stack">
      <PageHeader
        title="Dokonga yuborish"
        subtitle="Kategoriya ichidan mahsulot tanlab bir nechta mahsulotni bitta transfer bilan yuboring"
      />

      {pageError ? <div className="error-box">{pageError}</div> : null}

      <section className="panel-box">
        <div className="filters-row wrap">
          <select className="search-input narrow" value={storeId} onChange={(event) => setStoreId(event.target.value)}>
            <option value="">Do'kon tanlang</option>
            {stores.map((item) => (
              <option key={item._id} value={item._id}>
                {item.name} ({item.storeCode})
              </option>
            ))}
          </select>
          <select className="search-input narrow" value={categoryId} onChange={(event) => setCategoryId(event.target.value)}>
            <option value="">Barcha kategoriyalar</option>
            {categories.map((item) => <option key={item._id} value={item._id}>{item.name}</option>)}
          </select>
          <button type="button" className="ghost-btn" onClick={() => setHistoryOpen(true)}>
            Transfer tarixi
          </button>
          <button type="button" className="ghost-btn" onClick={addVisibleToCart}>
            Ko'rinayotganlarni qo'shish
          </button>
          <button type="button" className="ghost-btn" onClick={addCategoryToCart}>
            Kategoriyani qo'shish
          </button>
          <button type="button" className="ghost-btn" onClick={selectAllVariantColorsInCart}>
            Hamma rangini tanlash
          </button>
          <input
            className="search-input narrow"
            placeholder="Mahsulot qidirish..."
            value={productQuery}
            onChange={(event) => setProductQuery(event.target.value)}
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
                    <th>Sotish narxi</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  {visibleProducts.map((item) => (
                    <tr key={item._id}>
                      <td>{item.name} {item.code ? `(${item.code})` : ""}</td>
                      <td>{item.barcode}</td>
                      <td>{item.quantity} {normalizeUnit(item.unit)}</td>
                      <td>{formatMoneyWithCurrency(item.retailPrice ?? item.purchasePrice)}</td>
                      <td>
                        <button type="button" className="primary-btn small" onClick={() => addToCart(item)}>
                          + Qo'shish
                        </button>
                      </td>
                    </tr>
                  ))}
                  {!visibleProducts.length ? <tr><td colSpan="5">Bu kategoriyada mahsulot yo'q</td></tr> : null}
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
                            onChange={(event) => updateCartQuantity(item.productId, event.target.value === "" ? "" : Math.min(Number(event.target.value), item.stock))}
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
                onClick={submitTransfer}
                disabled={creating || !storeId || !cart.some((item) => getItemQuantity(item) > 0)}
              >
                {creating ? "Yuborilmoqda..." : "Dokonga yuborish"}
              </button>
            </div>
          </div>
        </div>
      </section>

      <ModalShell open={historyOpen} title="Transferlar tarixi" onClose={() => setHistoryOpen(false)} width="1100px">
        <div className="page-stack">
          <input
            className="search-input"
            placeholder="Qidirish..."
            value={transferQuery}
            onChange={(event) => setTransferQuery(event.target.value)}
          />
          <div className="mini-table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Hujjat</th>
                  <th>Do'kon</th>
                  <th>Mahsulotlar</th>
                  <th>Miqdor</th>
                  <th>Jami</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {transfers.map((item) => (
                  <tr key={item._id}>
                    <td>{item.transferNumber}</td>
                    <td>{item.storeName}</td>
                    <td>{item.items.map((row) => row.name).join(", ")}</td>
                    <td>{item.totalQuantity}</td>
                    <td>{formatMoneyWithCurrency(item.totalValue)}</td>
                    <td>{item.status}</td>
                  </tr>
                ))}
                {!transfers.length ? <tr><td colSpan="6">Transferlar hali yo'q</td></tr> : null}
              </tbody>
            </table>
          </div>
        </div>
      </ModalShell>
    </div>
  );
}
