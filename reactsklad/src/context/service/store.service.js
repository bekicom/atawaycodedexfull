import { apiSlice } from "./api.service";

export const storeService = apiSlice.injectEndpoints({
  endpoints: (builder) => ({
    getStores: builder.query({
      query: () => "/stores",
      providesTags: ["Store"],
    }),
    getStoreById: builder.query({
      query: (id) => `/stores/${id}`,
      providesTags: (_, __, id) => [{ type: "Store", id }],
    }),
    createStore: builder.mutation({
      query: (body) => ({
        url: "/stores",
        method: "POST",
        body,
      }),
      invalidatesTags: ["Store"],
    }),
    updateStore: builder.mutation({
      query: ({ id, ...body }) => ({
        url: `/stores/${id}`,
        method: "PUT",
        body,
      }),
      invalidatesTags: ["Store"],
    }),
    deleteStore: builder.mutation({
      query: (id) => ({
        url: `/stores/${id}`,
        method: "DELETE",
      }),
      invalidatesTags: ["Store"],
    }),
  }),
});

export const {
  useGetStoresQuery,
  useGetStoreByIdQuery,
  useCreateStoreMutation,
  useUpdateStoreMutation,
  useDeleteStoreMutation,
} = storeService;
