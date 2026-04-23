import { apiSlice } from "./api.service";

export const transferService = apiSlice.injectEndpoints({
  endpoints: (builder) => ({
    getTransfers: builder.query({
      query: ({ q = "", storeName = "" } = {}) => {
        const params = new URLSearchParams();
        if (q) params.set("q", q);
        if (storeName) params.set("storeName", storeName);
        const query = params.toString();
        return query ? `/transfers?${query}` : "/transfers";
      },
      providesTags: ["Transfer", "Product", "Dashboard"],
    }),
    createTransfer: builder.mutation({
      query: (body) => ({
        url: "/transfers",
        method: "POST",
        body,
      }),
      invalidatesTags: ["Transfer", "Product", "Dashboard"],
    }),
  }),
});

export const {
  useGetTransfersQuery,
  useCreateTransferMutation,
} = transferService;
