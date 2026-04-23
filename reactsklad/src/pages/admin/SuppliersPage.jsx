import { useMemo, useState } from "react";
import { PageHeader } from "../../components/page_header/PageHeader";
import { PageLoader } from "../../components/loading/PageLoader";
import { SupplierModal } from "../../components/masters/SupplierModal";
import { SupplierPaymentModal } from "../../components/masters/SupplierPaymentModal";
import { SuppliersTable } from "../../components/table/SuppliersTable";
import {
  useCreateSupplierMutation,
  useCreateSupplierPaymentMutation,
  useDeleteSupplierMutation,
  useGetSupplierByIdQuery,
  useGetSuppliersQuery,
  useUpdateSupplierMutation,
} from "../../context/service/master.service";
import { formatDateTime, formatMoneyWithCurrency } from "../../utils/format";
import { getApiErrorMessage } from "../../context/loading";

export function SuppliersPage() {
  const [query, setQuery] = useState("");
  const [modalOpen, setModalOpen] = useState(false);
  const [current, setCurrent] = useState(null);
  const [selectedSupplierId, setSelectedSupplierId] = useState("");
  const [paymentOpen, setPaymentOpen] = useState(false);
  const [pageError, setPageError] = useState("");

  const { data, isLoading } = useGetSuppliersQuery();
  const { data: supplierDetail } = useGetSupplierByIdQuery(selectedSupplierId, { skip: !selectedSupplierId });
  const [createSupplier, { isLoading: creating }] = useCreateSupplierMutation();
  const [updateSupplier, { isLoading: updating }] = useUpdateSupplierMutation();
  const [deleteSupplier] = useDeleteSupplierMutation();
  const [createSupplierPayment, { isLoading: paying }] = useCreateSupplierPaymentMutation();

  const suppliers = useMemo(
    () => (data?.suppliers || []).filter((item) => [item.name, item.phone, item.address].join(" ").toLowerCase().includes(query.toLowerCase())),
    [data, query],
  );

  const saveSupplier = async (payload) => {
    setPageError("");
    try {
      if (payload.id) await updateSupplier(payload).unwrap();
      else await createSupplier(payload).unwrap();
      setModalOpen(false);
      setCurrent(null);
    } catch (error) {
      setPageError(getApiErrorMessage(error));
    }
  };

  const removeSupplier = async (id) => {
    if (!window.confirm("Yetkazib beruvchini o'chirmoqchimisiz?")) return;
    setPageError("");
    try {
      await deleteSupplier(id).unwrap();
    } catch (error) {
      setPageError(getApiErrorMessage(error));
    }
  };

  const savePayment = async (payload) => {
    if (!selectedSupplierId) return;
    setPageError("");
    try {
      await createSupplierPayment({ id: selectedSupplierId, ...payload }).unwrap();
      setPaymentOpen(false);
    } catch (error) {
      setPageError(getApiErrorMessage(error));
    }
  };

  if (isLoading) return <PageLoader />;

  return (
    <div className="page-stack">
      <PageHeader
        title="Yetkazib beruvchilar"
        subtitle="Yetkazib beruvchi qo'shish, ko'rish va qarzni boshqarish"
        actions={<button type="button" className="primary-btn" onClick={() => { setCurrent(null); setModalOpen(true); }}>+ Yetkazib beruvchi</button>}
      />
      <section className="filters-row">
        <input className="search-input" placeholder="Qidirish..." value={query} onChange={(event) => setQuery(event.target.value)} />
      </section>
      {pageError ? <div className="error-box">{pageError}</div> : null}
      <SuppliersTable
        suppliers={suppliers}
        onEdit={(item) => { setCurrent(item); setModalOpen(true); }}
        onDelete={removeSupplier}
        onView={(item) => setSelectedSupplierId(item._id)}
        onPay={(item) => {
          setSelectedSupplierId(item._id);
          setPaymentOpen(true);
        }}
      />

      {selectedSupplierId ? (
        <section className="panel-box">
          <h3>Yetkazib beruvchi tafsiloti</h3>
          <div className="detail-grid">
            <div>
              <strong>{supplierDetail?.supplier?.name || "-"}</strong>
              <p>{supplierDetail?.supplier?.phone || "-"}</p>
              <p>{supplierDetail?.supplier?.address || "-"}</p>
            </div>
            <div>
              <p>Jami kirim: {formatMoneyWithCurrency(supplierDetail?.supplier?.stats?.totalPurchase)}</p>
              <p>To'langan: {formatMoneyWithCurrency(supplierDetail?.supplier?.stats?.supplierPaid)}</p>
              <p>Qarz: {formatMoneyWithCurrency(supplierDetail?.supplier?.stats?.totalDebt)}</p>
            </div>
          </div>
          <div className="mini-table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Hujjat</th>
                  <th>Mahsulot</th>
                  <th>Jami</th>
                  <th>Qarz</th>
                  <th>Sana</th>
                </tr>
              </thead>
              <tbody>
                {(supplierDetail?.purchases || []).map((item) => (
                  <tr key={item._id}>
                    <td>{item.invoiceNumber}</td>
                    <td>{item.productName}</td>
                    <td>{formatMoneyWithCurrency(item.totalCost)}</td>
                    <td>{formatMoneyWithCurrency(item.debtAmount)}</td>
                    <td>{formatDateTime(item.purchasedAt)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      ) : null}

      <SupplierModal open={modalOpen} current={current} onClose={() => { setModalOpen(false); setCurrent(null); }} onSubmit={saveSupplier} loading={creating || updating} />
      <SupplierPaymentModal
        open={paymentOpen}
        supplier={{ ...(supplierDetail?.supplier || suppliers.find((item) => item._id === selectedSupplierId)), payments: supplierDetail?.payments || [] }}
        onClose={() => setPaymentOpen(false)}
        onSubmit={savePayment}
        loading={paying}
      />
    </div>
  );
}
