import { useEffect, useMemo, useState } from "react";
import { PageHeader } from "../../components/page_header/PageHeader";
import { PageLoader } from "../../components/loading/PageLoader";
import { ModalShell } from "../../components/modal/ModalShell";
import { useGetCategoriesQuery } from "../../context/service/master.service";
import { useGetProductsQuery } from "../../context/service/addproduct.service";
import {
  useCreateSectionMutation,
  useDeleteSectionMutation,
  useGetSectionsQuery,
  useSetSectionAllocationsMutation,
} from "../../context/service/section.service";
import { formatMoneyWithCurrency, normalizeUnit } from "../../utils/format";
import { getApiErrorMessage } from "../../context/loading";

function buildCartItem(product) {
  return {
    productId: product._id,
    name: product.name,
    code: product.code || product.model || "",
    barcode: product.barcode || "",
    stock: Number(product.quantity || 0),
    unit: product.unit,
    purchasePrice: Number(product.purchasePrice || 0),
    quantity: 1,
  };
}

export function SectionsPage() {
  const [categoryId, setCategoryId] = useState("");
  const [productQuery, setProductQuery] = useState("");
  const [sectionId, setSectionId] = useState("");
  const [newSectionName, setNewSectionName] = useState("");
  const [newSectionDescription, setNewSectionDescription] = useState("");
  const [sectionModalOpen, setSectionModalOpen] = useState(false);
  const [cart, setCart] = useState([]);
  const [pageError, setPageError] = useState("");

  const { data: categoriesRes } = useGetCategoriesQuery();
  const { data: productsRes, isLoading: productsLoading } = useGetProductsQuery({ categoryId });
  const { data: sectionsRes, isLoading: sectionsLoading } = useGetSectionsQuery();
  const [createSection, { isLoading: creatingSection }] = useCreateSectionMutation();
  const [deleteSection] = useDeleteSectionMutation();
  const [setSectionAllocations, { isLoading: saving }] = useSetSectionAllocationsMutation();

  const categories = categoriesRes?.categories || [];
  const allProducts = productsRes?.products || [];
  const sections = sectionsRes?.sections || [];
  const selectedSection = useMemo(
    () => sections.find((item) => item._id === sectionId) || null,
    [sections, sectionId],
  );

  const visibleProducts = useMemo(
    () =>
      allProducts.filter((item) =>
        `${item.name || ""} ${item.code || item.model || ""} ${item.barcode || ""}`
          .toLowerCase()
          .includes(productQuery.toLowerCase()),
      ),
    [allProducts, productQuery],
  );

  useEffect(() => {
    setCart([]);
  }, [sectionId, selectedSection]);

  const loadExistingSectionItems = () => {
    if (!selectedSection) return;
    const nextCart = (selectedSection.items || []).map((item) => ({
      productId: item.productId,
      name: item.name,
      code: item.code || "",
      barcode: item.barcode || "",
      stock: Number(item.warehouseQuantity || 0),
      unit: item.unit,
      purchasePrice: Number(item.purchasePrice || 0),
      quantity: Number(item.quantity || 0),
    }));
    setCart(nextCart);
  };

  const cartTotal = useMemo(
    () => cart.reduce((sum, item) => sum + Number(item.quantity || 0), 0),
    [cart],
  );
  const cartValue = useMemo(
    () => cart.reduce((sum, item) => sum + (Number(item.quantity || 0) * Number(item.purchasePrice || 0)), 0),
    [cart],
  );

  const addToCart = (product) => {
    setCart((prev) => {
      if (prev.some((item) => item.productId === product._id)) return prev;
      return [...prev, buildCartItem(product)];
    });
  };

  const addManyToCart = (items) => {
    setCart((prev) => {
      const next = [...prev];
      for (const product of items) {
        if (next.some((item) => item.productId === product._id)) continue;
        next.push(buildCartItem(product));
      }
      return next;
    });
  };

  const saveSectionProducts = async () => {
    if (!sectionId) return;
    setPageError("");
    try {
      await setSectionAllocations({
        id: sectionId,
        items: cart
          .filter((item) => Number(item.quantity || 0) > 0)
          .map((item) => ({
            productId: item.productId,
            quantity: Number(item.quantity || 0),
          })),
      }).unwrap();
    } catch (error) {
      setPageError(getApiErrorMessage(error));
    }
  };

  const createNewSection = async () => {
    const name = newSectionName.trim();
    if (!name) return;
    setPageError("");
    try {
      const result = await createSection({
        name,
        description: newSectionDescription.trim(),
      }).unwrap();
      setNewSectionName("");
      setNewSectionDescription("");
      setSectionModalOpen(false);
      const createdId = result?.section?._id || "";
      if (createdId) setSectionId(createdId);
    } catch (error) {
      setPageError(getApiErrorMessage(error));
    }
  };

  const removeSection = async () => {
    if (!sectionId || !selectedSection) return;
    if (!window.confirm(`"${selectedSection.name}" bo'limini o'chirmoqchimisiz?`)) return;
    setPageError("");
    try {
      await deleteSection(sectionId).unwrap();
      setSectionId("");
      setCart([]);
    } catch (error) {
      setPageError(getApiErrorMessage(error));
    }
  };

  if (productsLoading || sectionsLoading) return <PageLoader />;

  return (
    <div className="page-stack">
      <PageHeader
        title="Bo'limlar"
        subtitle="Bo'lim yaratib mahsulot biriktiring va bo'lim bo'yicha qoldiq hisobotini yuriting"
      />

      {pageError ? <div className="error-box">{pageError}</div> : null}

      <section className="panel-box">
        <div className="filters-row wrap">
          <select className="search-input narrow" value={sectionId} onChange={(event) => setSectionId(event.target.value)}>
            <option value="">Bo'lim tanlang</option>
            {sections.map((item) => (
              <option key={item._id} value={item._id}>
                {item.name}
              </option>
            ))}
          </select>
          <button type="button" className="ghost-btn" onClick={() => setSectionModalOpen(true)}>
            Bo'lim yaratish
          </button>
          <button
            type="button"
            className="ghost-btn"
            onClick={loadExistingSectionItems}
            disabled={!sectionId}
          >
            Mavjudni yuklash
          </button>
          <button type="button" className="danger-outline-btn" onClick={removeSection} disabled={!sectionId}>
            Bo'limni o'chirish
          </button>
        </div>
        {selectedSection ? (
          <div className="transfer-summary">
            <strong>Tanlangan bo'lim: {selectedSection.name}</strong>
            <strong>Mavjud biriktirilgan: {selectedSection.productCount || 0} ta mahsulot</strong>
          </div>
        ) : null}
      </section>

      <section className="panel-box">
        <div className="filters-row wrap">
          <select className="search-input narrow" value={categoryId} onChange={(event) => setCategoryId(event.target.value)}>
            <option value="">Barcha kategoriyalar</option>
            {categories.map((item) => <option key={item._id} value={item._id}>{item.name}</option>)}
          </select>
          <button type="button" className="ghost-btn" onClick={() => addManyToCart(visibleProducts)}>
            Ko'rinayotganlarni qo'shish
          </button>
          <button type="button" className="ghost-btn" onClick={() => addManyToCart(allProducts)}>
            Kategoriyani qo'shish
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
                    <th>Narx</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  {visibleProducts.map((item) => (
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
                  {!visibleProducts.length ? <tr><td colSpan="5">Bu kategoriyada mahsulot yo'q</td></tr> : null}
                </tbody>
              </table>
            </div>
          </div>

          <div className="panel-box">
            <h3>Bo'limdagi mahsulotlar</h3>
            <div className="mini-table-wrap transfer-table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Mahsulot</th>
                    <th>Omborda</th>
                    <th>Bo'limda</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  {cart.map((item) => (
                    <tr key={item.productId}>
                      <td>{item.name} {item.code ? `(${item.code})` : ""}</td>
                      <td>{item.stock} {normalizeUnit(item.unit)}</td>
                      <td>
                        <input
                          className="search-input narrow"
                          type="number"
                          min="0"
                          max={item.stock}
                          value={item.quantity}
                          onChange={(event) =>
                            setCart((prev) =>
                              prev.map((row) => {
                                if (row.productId !== item.productId) return row;
                                const raw = event.target.value;
                                const next = raw === "" ? "" : Math.min(Number(raw), Number(row.stock || 0));
                                return { ...row, quantity: next };
                              }),
                            )
                          }
                        />
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
              <button type="button" className="ghost-btn" onClick={() => setCart([])}>
                Tozalash
              </button>
              <button
                type="button"
                className="primary-btn"
                onClick={saveSectionProducts}
                disabled={saving || !sectionId}
              >
                {saving ? "Saqlanmoqda..." : "Bo'limga saqlash"}
              </button>
            </div>
          </div>
        </div>
      </section>

      <section className="panel-box">
        <h3>Bo'limlar hisoboti</h3>
        <div className="mini-table-wrap">
          <table>
            <thead>
              <tr>
                <th>Bo'lim</th>
                <th>Mahsulotlar soni</th>
                <th>Jami miqdor</th>
                <th>Kelish qiymati</th>
                <th>Sotish qiymati</th>
              </tr>
            </thead>
            <tbody>
              {sections.map((item) => (
                <tr key={item._id}>
                  <td>{item.name}</td>
                  <td>{item.productCount || 0}</td>
                  <td>{item.totalQuantity || 0}</td>
                  <td>{formatMoneyWithCurrency(item.totalPurchaseValue || 0)}</td>
                  <td>{formatMoneyWithCurrency(item.totalRetailValue || 0)}</td>
                </tr>
              ))}
              {!sections.length ? <tr><td colSpan="5">Bo'limlar hali yo'q</td></tr> : null}
            </tbody>
          </table>
        </div>
      </section>

      <ModalShell
        open={sectionModalOpen}
        title="Yangi bo'lim yaratish"
        onClose={() => {
          if (creatingSection) return;
          setSectionModalOpen(false);
        }}
        width="620px"
      >
        <div className="page-stack">
          <input
            className="search-input"
            placeholder="Bo'lim nomi"
            value={newSectionName}
            onChange={(event) => setNewSectionName(event.target.value)}
          />
          <input
            className="search-input"
            placeholder="Izoh (ixtiyoriy)"
            value={newSectionDescription}
            onChange={(event) => setNewSectionDescription(event.target.value)}
          />
          <div className="modal-footer">
            <button
              type="button"
              className="ghost-btn"
              onClick={() => {
                if (creatingSection) return;
                setSectionModalOpen(false);
              }}
            >
              Bekor qilish
            </button>
            <button
              type="button"
              className="primary-btn"
              onClick={createNewSection}
              disabled={creatingSection || !newSectionName.trim()}
            >
              {creatingSection ? "Yaratilmoqda..." : "Yaratish"}
            </button>
          </div>
        </div>
      </ModalShell>
    </div>
  );
}
