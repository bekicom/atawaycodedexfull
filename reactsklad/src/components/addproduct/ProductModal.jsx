import { useEffect, useMemo, useRef, useState } from "react";
import { useCreateCategoryMutation, useCreateSupplierMutation } from "../../context/service/master.service";
import { useCreateSectionMutation } from "../../context/service/section.service";
import { buildVariantRows, formatGroupedNumberInput, formatPercentInput, normalizeCsvInput, normalizeSizeInput, parseGroupedNumberInput, parsePercentInput, sumVariantQuantity, toCsvInput } from "../../utils/format";
import { ModalShell } from "../modal/ModalShell";

const COLOR_PRESETS = [
  "qizil",
  "qora",
  "oq",
  "kok",
  "havorang",
  "yashil",
  "sariq",
  "kulrang",
  "jigarrang",
  "bej",
  "pushti",
  "siyohrang",
  "toq kok",
  "toq yashil",
  "bordo",
  "zangori",
  "oltin",
  "kumush",
  "apelsin",
  "krem",
];

function supportsPieceSaleUnit(unit) {
  return unit === "qop" || unit === "pachka";
}

const baseForm = {
  id: "",
  name: "",
  code: "",
  barcode: "",
  barcodeAliases: [""],
  gender: "",
  categoryId: "",
  supplierId: "",
  sectionId: "",
  purchasePrice: "",
  markupPercent: "",
  retailPrice: "",
  paymentType: "naqd",
  paidAmount: "",
  quantity: "",
  unit: "dona",
  sizeInput: "",
  colorInput: "",
  allowPieceSale: false,
  pieceUnit: "dona",
  pieceQtyPerBase: "",
  piecePrice: "",
  variantStocks: [],
};

function getRelationId(value) {
  return typeof value === "object" ? value?._id || "" : value || "";
}

function getRelationName(value) {
  return typeof value === "object" ? value?.name || "" : "";
}

function generateProductCode(products = []) {
  const usedCodes = new Set(
    products
      .map((item) => String(item?.code || "").trim())
      .filter((code) => /^\d{4}$/.test(code)),
  );

  for (let attempt = 0; attempt < 40; attempt += 1) {
    const code = String(Math.floor(1000 + Math.random() * 9000));
    if (!usedCodes.has(code)) return code;
  }

  return String(Math.floor(1000 + Math.random() * 9000));
}

function SearchableDropdown({
  label,
  value,
  items,
  query,
  setQuery,
  open,
  setOpen,
  onSelect,
  onAdd,
  placeholder = "Tanlang",
}) {
  return (
    <div className="select-create-block">
      <div className="select-create-head">
        <span>{label}</span>
        <button type="button" className="tiny-icon-btn" onClick={onAdd}>+</button>
      </div>

      <div className={`dropdown-shell ${open ? "open" : ""}`.trim()}>
        <button
          type="button"
          className="dropdown-trigger"
          onClick={() => setOpen((prev) => !prev)}
        >
          <span>{value || placeholder}</span>
          <span className="dropdown-caret">v</span>
        </button>

        {open ? (
          <div className="dropdown-panel">
            <input
              autoFocus
              className="mini-search-input"
              placeholder="Qidirish..."
              value={query}
              onChange={(event) => setQuery(event.target.value)}
            />
            <div className="dropdown-options">
              {items.map((item) => (
                <button
                  key={item._id}
                  type="button"
                  className="dropdown-option"
                  onClick={() => {
                    onSelect(item);
                    setOpen(false);
                  }}
                >
                  {item.name}
                </button>
              ))}
              {!items.length ? <div className="dropdown-empty">Topilmadi</div> : null}
            </div>
          </div>
        ) : null}
      </div>
    </div>
  );
}

function toFormData(current) {
  if (!current) return baseForm;

  const nextUnit = current.unit === "razmer" ? "dona" : (current.unit || "dona");
  return {
    id: current._id,
    name: current.name || "",
    code: current.code || "",
    barcode: current.barcode || "",
    barcodeAliases: Array.isArray(current.barcodeAliases) && current.barcodeAliases.length
      ? current.barcodeAliases
      : [""],
    gender: current.gender || "",
    categoryId: getRelationId(current.categoryId),
    supplierId: getRelationId(current.supplierId),
    sectionId: "",
    purchasePrice: current.purchasePrice ?? "",
    markupPercent:
      current.purchasePrice > 0 && current.retailPrice >= current.purchasePrice
        ? String(Math.round((((current.retailPrice - current.purchasePrice) / current.purchasePrice) * 100) * 100) / 100)
        : "",
    retailPrice: current.retailPrice ?? "",
    paymentType: current.paymentType || "naqd",
    paidAmount: current.paidAmount ?? "",
    quantity: current.quantity ?? "",
    unit: nextUnit,
    sizeInput: toCsvInput(current.sizeOptions || []),
    colorInput: toCsvInput(current.colorOptions || []),
    allowPieceSale: Boolean(current.allowPieceSale),
    pieceUnit: current.pieceUnit || "dona",
    pieceQtyPerBase: current.pieceQtyPerBase ?? "",
    piecePrice: current.piecePrice ?? "",
    variantStocks: current.variantStocks || [],
  };
}

function toggleTag(currentValues, nextValue) {
  return currentValues.includes(nextValue)
    ? currentValues.filter((item) => item !== nextValue)
    : [...currentValues, nextValue];
}

function handleGroupedNumberChange(setter, field) {
  return (event) => {
    setter((prev) => ({
      ...prev,
      [field]: formatGroupedNumberInput(event.target.value),
    }));
  };
}

function calculateRetailPriceFromMarkup(purchasePriceInput, markupPercentInput) {
  const purchasePrice = parseGroupedNumberInput(purchasePriceInput);
  const markupPercent = parsePercentInput(markupPercentInput);
  if (!purchasePrice || markupPercent < 0) return "";
  return formatGroupedNumberInput(Math.round(purchasePrice * (1 + markupPercent / 100)));
}

function calculateMarkupPercentFromPrices(purchasePriceInput, retailPriceInput) {
  const purchasePrice = parseGroupedNumberInput(purchasePriceInput);
  const retailPrice = parseGroupedNumberInput(retailPriceInput);
  if (!purchasePrice || retailPrice < purchasePrice) return "";

  const percent = ((retailPrice - purchasePrice) / purchasePrice) * 100;
  return formatPercentInput(String(Math.round(percent * 100) / 100));
}

function fillFormFromProduct(product, categories, suppliers, sections) {
  const next = toFormData(product);
  if (!next.categoryId && categories[0]?._id) next.categoryId = categories[0]._id;
  if (!next.supplierId && suppliers[0]?._id) next.supplierId = suppliers[0]._id;
  if (!next.sectionId && sections[0]?._id) next.sectionId = sections[0]._id;
  return next;
}

function fillFormFromBarcodeMatch(product, categories, suppliers, sections) {
  const next = fillFormFromProduct(product, categories, suppliers, sections);
  return {
    ...next,
    purchasePrice: "",
    retailPrice: "",
    paidAmount: "",
    quantity: "",
    piecePrice: "",
    pieceQtyPerBase: "",
    variantStocks: [],
  };
}

export function ProductModal({
  open,
  current,
  products = [],
  categories,
  suppliers,
  sections = [],
  onClose,
  onSubmit,
  loading,
}) {
  const [form, setForm] = useState(baseForm);
  const [showExtraBarcodes, setShowExtraBarcodes] = useState(false);
  const priceSyncReadyRef = useRef(false);
  const priceSyncSourceRef = useRef(null);
  const [categoryQuery, setCategoryQuery] = useState("");
  const [supplierQuery, setSupplierQuery] = useState("");
  const [sectionQuery, setSectionQuery] = useState("");
  const [categoryOpen, setCategoryOpen] = useState(false);
  const [supplierOpen, setSupplierOpen] = useState(false);
  const [sectionOpen, setSectionOpen] = useState(false);
  const [showCategoryCreate, setShowCategoryCreate] = useState(false);
  const [showSupplierCreate, setShowSupplierCreate] = useState(false);
  const [showSectionCreate, setShowSectionCreate] = useState(false);
  const [newCategoryName, setNewCategoryName] = useState("");
  const [newSectionName, setNewSectionName] = useState("");
  const [newSupplier, setNewSupplier] = useState({ name: "", phone: "", address: "" });
  const [inlineError, setInlineError] = useState("");
  const [createCategory, { isLoading: creatingCategory }] = useCreateCategoryMutation();
  const [createSupplier, { isLoading: creatingSupplier }] = useCreateSupplierMutation();
  const [createSection, { isLoading: creatingSection }] = useCreateSectionMutation();

  useEffect(() => {
    priceSyncReadyRef.current = false;
    priceSyncSourceRef.current = null;
    if (!open) return;
    const next = fillFormFromProduct(current, categories, suppliers, sections);
    if (!current) {
      next.code = generateProductCode(products);
    } else if (!next.code) {
      next.code = generateProductCode(products);
    }
    setForm(next);
    setShowExtraBarcodes(
      Array.isArray(next.barcodeAliases)
        && next.barcodeAliases.some((alias) => String(alias || "").trim().length > 0),
    );
    setCategoryQuery("");
    setSupplierQuery("");
    setSectionQuery("");
    setCategoryOpen(false);
    setSupplierOpen(false);
    setSectionOpen(false);
    setShowCategoryCreate(false);
    setShowSupplierCreate(false);
    setShowSectionCreate(false);
    setNewCategoryName("");
    setNewSectionName("");
    setNewSupplier({ name: "", phone: "", address: "" });
    setInlineError("");

    const timer = window.setTimeout(() => {
      priceSyncReadyRef.current = true;
    }, 0);

    return () => window.clearTimeout(timer);
  }, [open, current, categories, suppliers, sections]);

  useEffect(() => {
    if (!open || current) return;
    const barcode = String(form.barcode || "").trim();
    if (!barcode) return;

    const matchedProduct = products.find((item) => {
      const primary = String(item.barcode || "").trim();
      const aliases = Array.isArray(item.barcodeAliases) ? item.barcodeAliases.map((alias) => String(alias || "").trim()) : [];
      return primary === barcode || aliases.includes(barcode);
    });
    if (!matchedProduct) return;
    const matchedAliases = Array.isArray(matchedProduct.barcodeAliases)
      ? matchedProduct.barcodeAliases.map((alias) => String(alias || "").trim()).filter(Boolean)
      : [];
    if (matchedAliases.length > 0) setShowExtraBarcodes(true);

    setForm((prev) => {
      if ((prev.id && prev.id === matchedProduct._id) || prev.name || prev.code || prev.purchasePrice || prev.retailPrice || prev.quantity) {
        return prev.id === matchedProduct._id
          ? prev
          : fillFormFromBarcodeMatch(matchedProduct, categories, suppliers, sections);
      }

      return fillFormFromBarcodeMatch(matchedProduct, categories, suppliers, sections);
    });
  }, [form.barcode, open, current, products, categories, suppliers, sections]);

  const sizeOptions = useMemo(() => normalizeSizeInput(form.sizeInput), [form.sizeInput]);
  const colorOptions = useMemo(() => normalizeCsvInput(form.colorInput), [form.colorInput]);
  const productNameOptions = useMemo(
    () => [...new Set(products.map((item) => String(item.name || "").trim()).filter(Boolean))].sort((a, b) => a.localeCompare(b)),
    [products],
  );
  const selectedCategoryName = categories.find((item) => item._id === form.categoryId)?.name || getRelationName(current?.categoryId);
  const selectedSupplierName = suppliers.find((item) => item._id === form.supplierId)?.name || getRelationName(current?.supplierId);
  const selectedSectionName = sections.find((item) => item._id === form.sectionId)?.name || "";

  const filteredCategories = useMemo(
    () => categories.filter((item) => item.name.toLowerCase().includes(categoryQuery.toLowerCase())),
    [categories, categoryQuery],
  );

  const filteredSuppliers = useMemo(
    () => suppliers.filter((item) => [item.name, item.phone, item.address].join(" ").toLowerCase().includes(supplierQuery.toLowerCase())),
    [suppliers, supplierQuery],
  );

  const filteredSections = useMemo(
    () => sections.filter((item) => item.name.toLowerCase().includes(sectionQuery.toLowerCase())),
    [sections, sectionQuery],
  );

  useEffect(() => {
    if (form.unit !== "dona") return;

    const blueprint = buildVariantRows(sizeOptions, colorOptions);
    setForm((prev) => {
      const currentMap = new Map((prev.variantStocks || []).map((item) => [`${item.size}__${item.color || ""}`, item]));
      const merged = blueprint.map((item) => {
        const existing = currentMap.get(`${item.size}__${item.color || ""}`);
        return existing
          ? { ...item, quantity: existing.quantity === "" ? "" : String(existing.quantity) }
          : { ...item, quantity: "" };
      });
      return {
        ...prev,
        variantStocks: merged,
        quantity: sumVariantQuantity(merged),
      };
    });
  }, [form.unit, form.sizeInput, form.colorInput, sizeOptions, colorOptions]);

  useEffect(() => {
    if (!priceSyncReadyRef.current) return;
    if (priceSyncSourceRef.current === "retail") return;
    if (form.markupPercent === "") return;
    const nextRetailPrice = calculateRetailPriceFromMarkup(form.purchasePrice, form.markupPercent);
    setForm((prev) => (prev.retailPrice === nextRetailPrice ? prev : { ...prev, retailPrice: nextRetailPrice }));
  }, [form.purchasePrice, form.markupPercent]);

  const handleCreateCategory = async () => {
    const name = newCategoryName.trim();
    if (!name) return;
    setInlineError("");
    try {
      const response = await createCategory({ name }).unwrap();
      setForm((prev) => ({ ...prev, categoryId: response.category._id }));
      setNewCategoryName("");
      setShowCategoryCreate(false);
    } catch (error) {
      setInlineError(error?.data?.message || "Kategoriya saqlanmadi");
    }
  };

  const handleCreateSupplier = async () => {
    const name = newSupplier.name.trim();
    if (!name) return;
    setInlineError("");
    try {
      const response = await createSupplier({
        name,
        phone: newSupplier.phone,
        address: newSupplier.address,
      }).unwrap();
      setForm((prev) => ({ ...prev, supplierId: response.supplier._id }));
      setNewSupplier({ name: "", phone: "", address: "" });
      setShowSupplierCreate(false);
    } catch (error) {
      setInlineError(error?.data?.message || "Yetkazib beruvchi saqlanmadi");
    }
  };

  const handleCreateSection = async () => {
    const name = newSectionName.trim();
    if (!name) return;
    setInlineError("");
    try {
      const response = await createSection({ name }).unwrap();
      setForm((prev) => ({ ...prev, sectionId: response.section._id }));
      setNewSectionName("");
      setShowSectionCreate(false);
    } catch (error) {
      setInlineError(error?.data?.message || "Bo'lim saqlanmadi");
    }
  };

  return (
    <>
      <ModalShell open={open} title={current ? "Mahsulotni tahrirlash" : "Yangi mahsulot"} onClose={onClose} width="1040px">
        <form
          className="form-grid"
          onSubmit={(event) => {
            event.preventDefault();
            onSubmit({
              ...form,
              code: String(form.code || "").trim(),
              barcodeAliases: showExtraBarcodes
                ? [...new Set((form.barcodeAliases || []).map((item) => String(item || "").trim()).filter(Boolean))]
                : [],
              purchasePrice: parseGroupedNumberInput(form.purchasePrice),
              retailPrice: parseGroupedNumberInput(form.retailPrice),
              paidAmount: parseGroupedNumberInput(form.paidAmount),
              wholesalePrice: parseGroupedNumberInput(form.retailPrice),
              sizeOptions,
              colorOptions,
              quantity: form.unit === "dona" ? sumVariantQuantity(form.variantStocks) : Number(form.quantity),
              pieceQtyPerBase: Number(form.pieceQtyPerBase || 0),
              piecePrice: parseGroupedNumberInput(form.piecePrice),
              sectionId: String(form.sectionId || "").trim(),
              variantStocks: form.unit === "dona" ? form.variantStocks.filter((item) => Number(item.quantity || 0) > 0) : [],
            });
          }}
        >
          <label>
            <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 10 }}>
              <span>Shtixkod</span>
              <label className="checkbox-row" style={{ fontSize: 13 }}>
                <input
                  type="checkbox"
                  checked={showExtraBarcodes}
                  onChange={(event) => {
                    const checked = event.target.checked;
                    setShowExtraBarcodes(checked);
                    if (checked) {
                      setForm((prev) => ({
                        ...prev,
                        barcodeAliases: (prev.barcodeAliases || []).length ? prev.barcodeAliases : [""],
                      }));
                    }
                  }}
                />
                <span>Qo'shimcha</span>
              </label>
            </div>
            <input value={form.barcode} onChange={(event) => setForm((prev) => ({ ...prev, barcode: event.target.value }))} placeholder="Bo'sh qoldirilsa avtomatik" />
          </label>
          <label>
            <span>Nomi</span>
            <input
              list="product-name-options"
              value={form.name}
              onChange={(event) => setForm((prev) => ({ ...prev, name: event.target.value }))}
              placeholder="Mahsulot nomini kiriting"
              required
            />
            <datalist id="product-name-options">
              {productNameOptions.map((item) => (
                <option key={item} value={item} />
              ))}
            </datalist>
          </label>
          <label>
            <span>Kod</span>
            <input
              value={form.code}
              readOnly
              placeholder="Avtomatik 4 xonali kod"
            />
          </label>
          <div className="full-width">
            {showExtraBarcodes ? (
              <>
                <div className="select-create-head" style={{ marginBottom: 10 }}>
                  <span>Qo'shimcha shtixkodlar</span>
                  <button
                    type="button"
                    className="tiny-icon-btn"
                    onClick={() =>
                      setForm((prev) => ({
                        ...prev,
                        barcodeAliases: [...(prev.barcodeAliases || []), ""],
                      }))
                    }
                  >
                    +
                  </button>
                </div>
                <div className="variant-grid">
                  {(form.barcodeAliases || []).map((barcodeAlias, index) => (
                    <label key={`barcode-alias-${index}`}>
                      <span>{index + 2}-shtixkod</span>
                      <div style={{ display: "flex", gap: 8 }}>
                        <input
                          value={barcodeAlias}
                          onChange={(event) =>
                            setForm((prev) => ({
                              ...prev,
                              barcodeAliases: (prev.barcodeAliases || []).map((item, itemIndex) =>
                                itemIndex === index ? event.target.value : item,
                              ),
                            }))
                          }
                          placeholder="Qo'shimcha shtixkod kiriting"
                        />
                        {(form.barcodeAliases || []).length > 1 ? (
                          <button
                            type="button"
                            className="ghost-btn"
                            onClick={() =>
                              setForm((prev) => ({
                                ...prev,
                                barcodeAliases: (prev.barcodeAliases || []).filter((_, itemIndex) => itemIndex !== index),
                              }))
                            }
                          >
                            -
                          </button>
                        ) : null}
                      </div>
                    </label>
                  ))}
                </div>
              </>
            ) : null}
          </div>
          <div className="full-width">
            <span>Jinsi</span>
            <div className="radio-row">
              <label className="radio-item">
                <input
                  type="radio"
                  name="gender"
                  value=""
                  checked={form.gender === ""}
                  onChange={(event) => setForm((prev) => ({ ...prev, gender: event.target.value }))}
                />
                <span>Umumiy</span>
              </label>
              <label className="radio-item">
                <input
                  type="radio"
                  name="gender"
                  value="qiz_bola"
                  checked={form.gender === "qiz_bola"}
                  onChange={(event) => setForm((prev) => ({ ...prev, gender: event.target.value }))}
                />
                <span>Qiz bola</span>
              </label>
              <label className="radio-item">
                <input
                  type="radio"
                  name="gender"
                  value="ogil_bola"
                  checked={form.gender === "ogil_bola"}
                  onChange={(event) => setForm((prev) => ({ ...prev, gender: event.target.value }))}
                />
                <span>O'g'il bola</span>
              </label>
            </div>
          </div>

          <SearchableDropdown
            label="Kategoriya"
            value={selectedCategoryName}
            items={filteredCategories}
            query={categoryQuery}
            setQuery={setCategoryQuery}
            open={categoryOpen}
            setOpen={setCategoryOpen}
            onSelect={(item) => setForm((prev) => ({ ...prev, categoryId: item._id }))}
            onAdd={() => setShowCategoryCreate(true)}
          />

          <SearchableDropdown
            label="Yetkazib beruvchi"
            value={selectedSupplierName}
            items={filteredSuppliers}
            query={supplierQuery}
            setQuery={setSupplierQuery}
            open={supplierOpen}
            setOpen={setSupplierOpen}
            onSelect={(item) => setForm((prev) => ({ ...prev, supplierId: item._id }))}
            onAdd={() => setShowSupplierCreate(true)}
          />

          <SearchableDropdown
            label="Bo'lim"
            value={selectedSectionName}
            items={filteredSections}
            query={sectionQuery}
            setQuery={setSectionQuery}
            open={sectionOpen}
            setOpen={setSectionOpen}
            onSelect={(item) => setForm((prev) => ({ ...prev, sectionId: item._id }))}
            onAdd={() => setShowSectionCreate(true)}
            placeholder={sections.length ? "Bo'lim tanlang" : "Bo'lim yo'q"}
          />

          <label>
            <span>Birligi</span>
            <select value={form.unit} onChange={(event) => setForm((prev) => ({ ...prev, unit: event.target.value }))}>
              <option value="dona">dona</option>
              <option value="komplekt">komplekt</option>
              <option value="qop">qop</option>
              <option value="pachka">pachka</option>
            </select>
          </label>
          <label>
            <span>Kelish narxi</span>
            <input
              type="text"
              inputMode="numeric"
              value={form.purchasePrice}
              onChange={(event) => {
                priceSyncSourceRef.current = "purchase";
                handleGroupedNumberChange(setForm, "purchasePrice")(event);
              }}
              required
            />
          </label>
          <label>
            <span>Ustama %</span>
            <input
              type="text"
              inputMode="decimal"
              value={form.markupPercent}
              onChange={(event) => {
                priceSyncSourceRef.current = "markup";
                setForm((prev) => ({ ...prev, markupPercent: formatPercentInput(event.target.value) }));
              }}
              placeholder="Masalan 10"
            />
          </label>
          <label>
            <span>Sotish narxi</span>
            <input
            type="text"
            inputMode="numeric"
            value={form.retailPrice}
            onChange={(event) => {
              priceSyncSourceRef.current = "retail";
              const nextRetailPrice = formatGroupedNumberInput(event.target.value);
              setForm((prev) => ({
                ...prev,
                  retailPrice: nextRetailPrice,
                  markupPercent: calculateMarkupPercentFromPrices(prev.purchasePrice, nextRetailPrice),
                }));
              }}
              required
            />
          </label>
          <label>
            <span>To'lov turi</span>
            <select value={form.paymentType} onChange={(event) => setForm((prev) => ({ ...prev, paymentType: event.target.value }))}>
              <option value="naqd">naqd</option>
              <option value="qarz">qarz</option>
              <option value="qisman">qisman</option>
            </select>
          </label>
          <label>
            <span>To'langan summa</span>
            <input type="text" inputMode="numeric" value={form.paidAmount} onChange={handleGroupedNumberChange(setForm, "paidAmount")} disabled={form.paymentType === "naqd" || form.paymentType === "qarz"} />
          </label>
          {form.unit !== "dona" ? (
            <label>
              <span>Miqdori</span>
              <input type="number" min="0" step="1" value={form.quantity} onChange={(event) => setForm((prev) => ({ ...prev, quantity: event.target.value }))} required />
            </label>
          ) : null}
          {form.unit === "dona" ? (
            <>
              <label className="full-width">
                <span>O'lchamlar</span>
                <input
                  value={form.sizeInput}
                  onChange={(event) => setForm((prev) => ({ ...prev, sizeInput: event.target.value }))}
                  placeholder="O'lchamlarni qo'lda kiriting: masalan x 4-6 41 43"
                />
              </label>
              <label className="full-width">
                <span>Ranglar</span>
                <input value={form.colorInput} onChange={(event) => setForm((prev) => ({ ...prev, colorInput: event.target.value }))} placeholder="Qo'shimcha rang kiriting: masalan limon, grafit" />
              </label>
              <div className="full-width">
                <div className="preset-head">
                  <span className="preset-label">Asosiy ranglar</span>
                </div>
                <div className="preset-grid">
                  {COLOR_PRESETS.map((color) => {
                    const active = colorOptions.includes(color);
                    return (
                      <button
                        key={color}
                        type="button"
                        className={`preset-chip ${active ? "active" : ""}`.trim()}
                      onClick={() =>
                        setForm((prev) => ({
                          ...prev,
                          colorInput: toCsvInput(toggleTag(normalizeCsvInput(prev.colorInput), color)),
                        }))
                      }
                    >
                        <span className={`color-dot color-${color.replace(/\s+/g, "-")}`} />
                        {color}
                      </button>
                    );
                  })}
                </div>
              </div>
              <div className="full-width variant-wrap">
                <span>Dona variantlari</span>
                <div className="variant-grid">
                  {form.variantStocks.map((item, index) => (
                    <label key={`${item.size}-${item.color || "none"}`}>
                      <span>{item.size}{item.color ? ` / ${item.color}` : ""}</span>
                      <input
                        type="number"
                        min="0"
                        step="1"
                        value={item.quantity}
                        onChange={(event) =>
                          setForm((prev) => ({
                            ...prev,
                            variantStocks: prev.variantStocks.map((variant, variantIndex) =>
                            variantIndex === index ? { ...variant, quantity: event.target.value === "" ? "" : String(Number(event.target.value)) } : variant,
                            ),
                          }))
                        }
                    />
                    </label>
                  ))}
                  {!form.variantStocks.length ? <p className="hint-text">Avval o'lcham yoki ranglarni kiriting</p> : null}
                </div>
              </div>
            </>
          ) : null}
          {supportsPieceSaleUnit(form.unit) ? (
            <>
              <label className="checkbox-row">
                <input type="checkbox" checked={form.allowPieceSale} onChange={(event) => setForm((prev) => ({ ...prev, allowPieceSale: event.target.checked }))} />
                <span>Mayda sotuvga ruxsat</span>
              </label>
              {form.allowPieceSale ? (
                <>
                  <label>
                    <span>Mayda birlik</span>
                    <input value={form.pieceUnit} onChange={(event) => setForm((prev) => ({ ...prev, pieceUnit: event.target.value }))} />
                  </label>
                  <label>
                    <span>1 {form.unit}dagi miqdor</span>
                    <input type="number" min="0" step="0.01" value={form.pieceQtyPerBase} onChange={(event) => setForm((prev) => ({ ...prev, pieceQtyPerBase: event.target.value }))} />
                  </label>
                  <label>
                    <span>Mayda narx</span>
                    <input type="text" inputMode="numeric" value={form.piecePrice} onChange={handleGroupedNumberChange(setForm, "piecePrice")} />
                  </label>
                </>
              ) : null}
            </>
          ) : null}

          {inlineError ? <div className="error-box full-width">{inlineError}</div> : null}

          <div className="modal-footer full-width">
            <button type="button" className="ghost-btn" onClick={onClose}>Bekor qilish</button>
            <button type="submit" className="primary-btn" disabled={loading}>
              {loading ? "Saqlanmoqda..." : "Saqlash"}
            </button>
          </div>
        </form>
      </ModalShell>

      <ModalShell open={showCategoryCreate} title="Yangi kategoriya" onClose={() => setShowCategoryCreate(false)} width="460px">
        <div className="inline-create-box modal-inline-box">
          <input placeholder="Kategoriya nomi" value={newCategoryName} onChange={(event) => setNewCategoryName(event.target.value)} />
          <div className="modal-footer">
            <button type="button" className="ghost-btn" onClick={() => setShowCategoryCreate(false)}>Bekor qilish</button>
            <button type="button" className="tiny-action-btn solid" onClick={handleCreateCategory} disabled={creatingCategory}>Saqlash</button>
          </div>
        </div>
      </ModalShell>

      <ModalShell open={showSupplierCreate} title="Yangi yetkazib beruvchi" onClose={() => setShowSupplierCreate(false)} width="560px">
        <div className="inline-create-grid modal-inline-grid">
          <input placeholder="Ismi" value={newSupplier.name} onChange={(event) => setNewSupplier((prev) => ({ ...prev, name: event.target.value }))} />
          <input placeholder="Telefon" value={newSupplier.phone} onChange={(event) => setNewSupplier((prev) => ({ ...prev, phone: event.target.value }))} />
          <input placeholder="Manzil" value={newSupplier.address} onChange={(event) => setNewSupplier((prev) => ({ ...prev, address: event.target.value }))} />
          <div className="modal-footer full-width">
            <button type="button" className="ghost-btn" onClick={() => setShowSupplierCreate(false)}>Bekor qilish</button>
            <button type="button" className="tiny-action-btn solid" onClick={handleCreateSupplier} disabled={creatingSupplier}>Saqlash</button>
          </div>
        </div>
      </ModalShell>

      <ModalShell open={showSectionCreate} title="Yangi bo'lim" onClose={() => setShowSectionCreate(false)} width="460px">
        <div className="inline-create-box modal-inline-box">
          <input placeholder="Bo'lim nomi" value={newSectionName} onChange={(event) => setNewSectionName(event.target.value)} />
          <div className="modal-footer">
            <button type="button" className="ghost-btn" onClick={() => setShowSectionCreate(false)}>Bekor qilish</button>
            <button type="button" className="tiny-action-btn solid" onClick={handleCreateSection} disabled={creatingSection}>Saqlash</button>
          </div>
        </div>
      </ModalShell>
    </>
  );
}
