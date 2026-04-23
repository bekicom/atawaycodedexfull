import { useMemo, useState } from "react";
import { PageHeader } from "../../components/page_header/PageHeader";
import { PageLoader } from "../../components/loading/PageLoader";
import { CategoryModal } from "../../components/masters/CategoryModal";
import { CategoriesTable } from "../../components/table/CategoriesTable";
import {
  useCreateCategoryMutation,
  useDeleteCategoryMutation,
  useGetCategoriesQuery,
  useUpdateCategoryMutation,
} from "../../context/service/master.service";
import { getApiErrorMessage } from "../../context/loading";

export function CategoriesPage() {
  const [query, setQuery] = useState("");
  const [modalOpen, setModalOpen] = useState(false);
  const [current, setCurrent] = useState(null);
  const [pageError, setPageError] = useState("");

  const { data, isLoading } = useGetCategoriesQuery();
  const [createCategory, { isLoading: creating }] = useCreateCategoryMutation();
  const [updateCategory, { isLoading: updating }] = useUpdateCategoryMutation();
  const [deleteCategory] = useDeleteCategoryMutation();

  const categories = useMemo(() => (data?.categories || []).filter((item) => item.name.toLowerCase().includes(query.toLowerCase())), [data, query]);

  const saveCategory = async (payload) => {
    setPageError("");
    try {
      if (payload.id) await updateCategory(payload).unwrap();
      else await createCategory(payload).unwrap();
      setModalOpen(false);
      setCurrent(null);
    } catch (error) {
      setPageError(getApiErrorMessage(error));
    }
  };

  const removeCategory = async (id) => {
    if (!window.confirm("Kategoriyani o'chirmoqchimisiz?")) return;
    setPageError("");
    try {
      await deleteCategory(id).unwrap();
    } catch (error) {
      setPageError(getApiErrorMessage(error));
    }
  };

  if (isLoading) return <PageLoader />;

  return (
    <div className="page-stack">
      <PageHeader
        title="Kategoriyalar"
        subtitle="Kategoriya qo'shish, ko'rish va tahrirlash"
        actions={<button type="button" className="primary-btn" onClick={() => { setCurrent(null); setModalOpen(true); }}>+ Kategoriya</button>}
      />
      <section className="filters-row">
        <input className="search-input" placeholder="Kategoriya qidirish..." value={query} onChange={(event) => setQuery(event.target.value)} />
      </section>
      {pageError ? <div className="error-box">{pageError}</div> : null}
      <CategoriesTable categories={categories} onEdit={(item) => { setCurrent(item); setModalOpen(true); }} onDelete={removeCategory} />
      <CategoryModal open={modalOpen} current={current} onClose={() => { setModalOpen(false); setCurrent(null); }} onSubmit={saveCategory} loading={creating || updating} />
    </div>
  );
}
