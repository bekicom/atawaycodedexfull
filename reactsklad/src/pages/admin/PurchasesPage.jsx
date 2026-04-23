import { useState } from "react";
import { PageHeader } from "../../components/page_header/PageHeader";
import { PageLoader } from "../../components/loading/PageLoader";
import { PurchasesTable } from "../../components/table/PurchasesTable";
import { useGetSuppliersQuery } from "../../context/service/master.service";
import { useGetPurchasesQuery } from "../../context/service/purchase.service";

export function PurchasesPage() {
  const [filter, setFilter] = useState({
    supplierId: "",
    entryType: "",
    q: "",
    dateFrom: "",
    dateTo: "",
  });

  const { data: suppliersRes } = useGetSuppliersQuery();
  const { data, isLoading } = useGetPurchasesQuery(filter);

  if (isLoading) return <PageLoader />;

  return (
    <div className="page-stack">
      <PageHeader title="Kirim tarixi" subtitle="Barcha prihod hujjatlari va supplier kirimlari" />
      <section className="filters-row wrap">
        <input className="search-input" placeholder="Qidirish..." value={filter.q} onChange={(event) => setFilter((prev) => ({ ...prev, q: event.target.value }))} />
        <select className="search-input narrow" value={filter.supplierId} onChange={(event) => setFilter((prev) => ({ ...prev, supplierId: event.target.value }))}>
          <option value="">Barcha supplierlar</option>
          {(suppliersRes?.suppliers || []).map((item) => <option key={item._id} value={item._id}>{item.name}</option>)}
        </select>
        <select className="search-input narrow" value={filter.entryType} onChange={(event) => setFilter((prev) => ({ ...prev, entryType: event.target.value }))}>
          <option value="">Barcha turlar</option>
          <option value="initial">initial</option>
          <option value="restock">restock</option>
          <option value="opening_balance">opening_balance</option>
          <option value="stock_out">stock_out</option>
        </select>
        <input className="search-input narrow" type="date" value={filter.dateFrom} onChange={(event) => setFilter((prev) => ({ ...prev, dateFrom: event.target.value }))} />
        <input className="search-input narrow" type="date" value={filter.dateTo} onChange={(event) => setFilter((prev) => ({ ...prev, dateTo: event.target.value }))} />
      </section>
      <PurchasesTable purchases={data?.purchases || []} />
    </div>
  );
}
