import { apiSlice } from "./api.service";

export const purchaseService = apiSlice.injectEndpoints({
  endpoints: (builder) => ({
    getPurchases: builder.query({
      query: ({
        supplierId = "",
        productId = "",
        entryType = "",
        q = "",
        dateFrom = "",
        dateTo = "",
      } = {}) => {
        const params = new URLSearchParams();
        if (supplierId) params.set("supplierId", supplierId);
        if (productId) params.set("productId", productId);
        if (entryType) params.set("entryType", entryType);
        if (q) params.set("q", q);
        if (dateFrom) params.set("dateFrom", dateFrom);
        if (dateTo) params.set("dateTo", dateTo);
        const query = params.toString();
        return query ? `/purchases?${query}` : "/purchases";
      },
      providesTags: ["Purchase"],
    }),
    getSupplierPurchaseReport: builder.query({
      query: (id) => `/purchases/supplier/${id}`,
      providesTags: (_, __, id) => [{ type: "SupplierDetail", id }],
    }),
    getStockOuts: builder.query({
      query: ({
        supplierId = "",
        productId = "",
        q = "",
        dateFrom = "",
        dateTo = "",
      } = {}) => {
        const params = new URLSearchParams();
        if (supplierId) params.set("supplierId", supplierId);
        if (productId) params.set("productId", productId);
        if (q) params.set("q", q);
        if (dateFrom) params.set("dateFrom", dateFrom);
        if (dateTo) params.set("dateTo", dateTo);
        const query = params.toString();
        return query ? `/stock-outs?${query}` : "/stock-outs";
      },
      providesTags: ["Purchase"],
    }),
    createStockOut: builder.mutation({
      query: (body) => ({
        url: "/stock-outs",
        method: "POST",
        body,
      }),
      invalidatesTags: ["Purchase", "Product", "Dashboard", "Supplier"],
    }),
    createStockOutBulk: builder.mutation({
      query: (body) => ({
        url: "/stock-outs/bulk",
        method: "POST",
        body,
      }),
      invalidatesTags: ["Purchase", "Product", "Dashboard", "Supplier"],
    }),
  }),
});

export const {
  useGetPurchasesQuery,
  useGetSupplierPurchaseReportQuery,
  useGetStockOutsQuery,
  useCreateStockOutMutation,
  useCreateStockOutBulkMutation,
} = purchaseService;
