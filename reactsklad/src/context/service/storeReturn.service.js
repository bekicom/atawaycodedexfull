import { apiSlice } from "./api.service";

export const storeReturnService = apiSlice.injectEndpoints({
  endpoints: (builder) => ({
    getStoreReturns: builder.query({
      query: ({ status = "", page = 1, limit = 200, productId = "" } = {}) => {
        const params = new URLSearchParams();
        if (status) params.set("status", status);
        if (page) params.set("page", String(page));
        if (limit) params.set("limit", String(limit));
        if (productId) params.set("productId", productId);
        const query = params.toString();
        return query ? `/products/store-returns?${query}` : "/products/store-returns";
      },
      providesTags: ["StoreReturn", "Product", "Dashboard"],
    }),
    approveStoreReturn: builder.mutation({
      query: ({ id, note = "" }) => ({
        url: `/products/store-returns/${id}/approve`,
        method: "POST",
        body: { note },
      }),
      invalidatesTags: ["StoreReturn", "Product", "Dashboard"],
    }),
    rejectStoreReturn: builder.mutation({
      query: ({ id, note = "" }) => ({
        url: `/products/store-returns/${id}/reject`,
        method: "POST",
        body: { note },
      }),
      invalidatesTags: ["StoreReturn", "Product", "Dashboard"],
    }),
  }),
});

export const {
  useGetStoreReturnsQuery,
  useApproveStoreReturnMutation,
  useRejectStoreReturnMutation,
} = storeReturnService;
