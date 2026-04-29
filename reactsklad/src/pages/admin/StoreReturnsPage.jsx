import { useMemo, useState } from "react";
import { PageHeader } from "../../components/page_header/PageHeader";
import { PageLoader } from "../../components/loading/PageLoader";
import {
  useApproveStoreReturnMutation,
  useGetStoreReturnsQuery,
  useRejectStoreReturnMutation,
} from "../../context/service/storeReturn.service";
import { getApiErrorMessage } from "../../context/loading";
import { formatDateTime, formatMoneyWithCurrency, normalizeUnit } from "../../utils/format";

function statusLabel(status) {
  if (status === "approved") return "Qabul qilingan";
  if (status === "rejected") return "Rad etilgan";
  return "Kutilmoqda";
}

export function StoreReturnsPage() {
  const [status, setStatus] = useState("");
  const [query, setQuery] = useState("");
  const [pageError, setPageError] = useState("");

  const { data, isLoading } = useGetStoreReturnsQuery({ status, limit: 300 });
  const [approveStoreReturn, { isLoading: approving }] = useApproveStoreReturnMutation();
  const [rejectStoreReturn, { isLoading: rejecting }] = useRejectStoreReturnMutation();

  const requests = data?.requests || [];
  const filteredRequests = useMemo(() => {
    const normalized = query.trim().toLowerCase();
    if (!normalized) return requests;
    return requests.filter((item) => {
      const text = [
        item?.productName,
        item?.productBarcode,
        item?.requestedByUsername,
        item?.approvedByUsername,
        item?.status,
      ]
        .filter(Boolean)
        .join(" ")
        .toLowerCase();
      return text.includes(normalized);
    });
  }, [requests, query]);

  const summary = data?.summary || {
    pendingCount: 0,
    approvedCount: 0,
    rejectedCount: 0,
    totalRequested: 0,
    totalApproved: 0,
  };

  const approveRequest = async (requestId) => {
    setPageError("");
    const note = window.prompt("Izoh (ixtiyoriy):", "") ?? "";
    try {
      await approveStoreReturn({ id: requestId, note }).unwrap();
    } catch (error) {
      setPageError(getApiErrorMessage(error));
    }
  };

  const rejectRequest = async (requestId) => {
    setPageError("");
    const note = window.prompt("Rad etish sababi (ixtiyoriy):", "") ?? "";
    try {
      await rejectStoreReturn({ id: requestId, note }).unwrap();
    } catch (error) {
      setPageError(getApiErrorMessage(error));
    }
  };

  if (isLoading) return <PageLoader />;

  return (
    <div className="page-stack">
      <PageHeader
        title="Dokondan qaytgan"
        subtitle="Do'konlardan kelgan qaytarish so'rovlarini qabul qiling yoki rad eting"
      />

      <section className="filters-row wrap">
        <select className="search-input narrow" value={status} onChange={(event) => setStatus(event.target.value)}>
          <option value="">Barcha statuslar</option>
          <option value="pending">Kutilmoqda</option>
          <option value="approved">Qabul qilingan</option>
          <option value="rejected">Rad etilgan</option>
        </select>
        <input
          className="search-input"
          placeholder="Mahsulot, shtix yoki kassir bo'yicha qidirish..."
          value={query}
          onChange={(event) => setQuery(event.target.value)}
        />
      </section>

      <section className="stats-grid">
        <article className="stat-card"><span>Kutilmoqda</span><strong>{summary.pendingCount || 0}</strong></article>
        <article className="stat-card"><span>Qabul qilingan</span><strong>{summary.approvedCount || 0}</strong></article>
        <article className="stat-card"><span>Rad etilgan</span><strong>{summary.rejectedCount || 0}</strong></article>
        <article className="stat-card"><span>Jami qaytarish (tasdiqlangan)</span><strong>{formatMoneyWithCurrency(summary.totalApproved || 0, "dona")}</strong></article>
      </section>

      {pageError ? <div className="error-box">{pageError}</div> : null}

      <div className="table-panel">
        <table>
          <thead>
            <tr>
              <th>Sana</th>
              <th>Mahsulot</th>
              <th>Shtixkod</th>
              <th>So'ralgan</th>
              <th>Tasdiqlangan</th>
              <th>Status</th>
              <th>So'ragan</th>
              <th>Tasdiqlagan</th>
              <th>Izoh</th>
              <th>Amal</th>
            </tr>
          </thead>
          <tbody>
            {filteredRequests.map((item) => (
              <tr key={item._id}>
                <td>{formatDateTime(item.requestedAt || item.createdAt)}</td>
                <td>{item.productName || "-"}</td>
                <td>{item.productBarcode || "-"}</td>
                <td>{`${item.requestedQty || 0} ${normalizeUnit(item.unit)}`}</td>
                <td>{`${item.approvedQty || 0} ${normalizeUnit(item.unit)}`}</td>
                <td>{statusLabel(item.status)}</td>
                <td>{item.requestedByUsername || "-"}</td>
                <td>{item.approvedByUsername || "-"}</td>
                <td className="cell-wrap">{item.decisionNote || item.requestNote || "-"}</td>
                <td className="actions-cell">
                  {item.status === "pending" ? (
                    <>
                      <button
                        type="button"
                        className="success-btn small"
                        disabled={approving || rejecting}
                        onClick={() => approveRequest(item._id)}
                      >
                        Qabul qilish
                      </button>
                      <button
                        type="button"
                        className="danger-btn small"
                        disabled={approving || rejecting}
                        onClick={() => rejectRequest(item._id)}
                      >
                        Rad etish
                      </button>
                    </>
                  ) : (
                    <span style={{ color: "var(--muted)" }}>Yakunlangan</span>
                  )}
                </td>
              </tr>
            ))}
            {!filteredRequests.length ? (
              <tr>
                <td colSpan="10">Qaytarish so'rov topilmadi</td>
              </tr>
            ) : null}
          </tbody>
        </table>
      </div>
    </div>
  );
}
