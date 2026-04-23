import { useMemo, useState } from "react";
import { PageHeader } from "../../components/page_header/PageHeader";
import { PageLoader } from "../../components/loading/PageLoader";
import { StoreDetailModal } from "../../components/masters/StoreDetailModal";
import { StoreModal } from "../../components/masters/StoreModal";
import { StoresTable } from "../../components/table/StoresTable";
import {
  useCreateStoreMutation,
  useDeleteStoreMutation,
  useGetStoreByIdQuery,
  useGetStoresQuery,
  useUpdateStoreMutation,
} from "../../context/service/store.service";
import { getApiErrorMessage } from "../../context/loading";

export function StoresPage() {
  const [query, setQuery] = useState("");
  const [modalOpen, setModalOpen] = useState(false);
  const [current, setCurrent] = useState(null);
  const [viewId, setViewId] = useState("");
  const [pageError, setPageError] = useState("");

  const { data, isLoading } = useGetStoresQuery();
  const { data: storeDetail } = useGetStoreByIdQuery(viewId, { skip: !viewId });
  const [createStore, { isLoading: creating }] = useCreateStoreMutation();
  const [updateStore, { isLoading: updating }] = useUpdateStoreMutation();
  const [deleteStore] = useDeleteStoreMutation();

  const stores = useMemo(
    () => (data?.stores || []).filter((item) => [item.name, item.storeCode, item.phone, item.address].join(" ").toLowerCase().includes(query.toLowerCase())),
    [data, query],
  );

  const saveStore = async (payload) => {
    setPageError("");
    try {
      if (payload.id) await updateStore(payload).unwrap();
      else await createStore(payload).unwrap();
      setModalOpen(false);
      setCurrent(null);
    } catch (error) {
      setPageError(getApiErrorMessage(error));
    }
  };

  const removeStore = async (id) => {
    if (!window.confirm("Do'konni o'chirmoqchimisiz?")) return;
    setPageError("");
    try {
      await deleteStore(id).unwrap();
    } catch (error) {
      setPageError(getApiErrorMessage(error));
    }
  };

  if (isLoading) return <PageLoader />;

  return (
    <div className="page-stack">
      <PageHeader
        title="Do'konlar"
        subtitle="Do'kon yarating va unga maxsus ID kod bering"
        actions={<button type="button" className="primary-btn" onClick={() => { setCurrent(null); setModalOpen(true); }}>+ Do'kon</button>}
      />
      <section className="filters-row">
        <input className="search-input" placeholder="Do'kon qidirish..." value={query} onChange={(event) => setQuery(event.target.value)} />
      </section>
      {pageError ? <div className="error-box">{pageError}</div> : null}
      <StoresTable stores={stores} onView={(item) => setViewId(item._id)} onEdit={(item) => { setCurrent(item); setModalOpen(true); }} onDelete={removeStore} />
      <StoreModal open={modalOpen} current={current} onClose={() => { setModalOpen(false); setCurrent(null); }} onSubmit={saveStore} loading={creating || updating} />
      <StoreDetailModal open={Boolean(viewId)} detail={storeDetail} onClose={() => setViewId("")} />
    </div>
  );
}
