import { apiSlice } from "./api.service";

export const masterService = apiSlice.injectEndpoints({
  endpoints: (builder) => ({
    getCategories: builder.query({
      query: () => "/categories",
      providesTags: ["Category"],
    }),
    createCategory: builder.mutation({
      query: (body) => ({
        url: "/categories",
        method: "POST",
        body,
      }),
      invalidatesTags: ["Category", "Product", "Dashboard"],
    }),
    updateCategory: builder.mutation({
      query: ({ id, ...body }) => ({
        url: `/categories/${id}`,
        method: "PUT",
        body,
      }),
      invalidatesTags: ["Category", "Product", "Dashboard"],
    }),
    deleteCategory: builder.mutation({
      query: (id) => ({
        url: `/categories/${id}`,
        method: "DELETE",
      }),
      invalidatesTags: ["Category", "Product", "Dashboard"],
    }),
    getSuppliers: builder.query({
      query: () => "/suppliers",
      providesTags: ["Supplier"],
    }),
    getSupplierById: builder.query({
      query: (id) => `/suppliers/${id}`,
      providesTags: (_, __, id) => [{ type: "SupplierDetail", id }],
    }),
    createSupplier: builder.mutation({
      query: (body) => ({
        url: "/suppliers",
        method: "POST",
        body,
      }),
      invalidatesTags: ["Supplier", "Dashboard"],
    }),
    updateSupplier: builder.mutation({
      query: ({ id, ...body }) => ({
        url: `/suppliers/${id}`,
        method: "PUT",
        body,
      }),
      invalidatesTags: (_, __, arg) => ["Supplier", "Dashboard", { type: "SupplierDetail", id: arg.id }],
    }),
    deleteSupplier: builder.mutation({
      query: (id) => ({
        url: `/suppliers/${id}`,
        method: "DELETE",
      }),
      invalidatesTags: ["Supplier", "Dashboard", "Product"],
    }),
    createSupplierPayment: builder.mutation({
      query: ({ id, ...body }) => ({
        url: `/suppliers/${id}/payments`,
        method: "POST",
        body,
      }),
      invalidatesTags: (_, __, arg) => ["Supplier", "Dashboard", "Purchase", { type: "SupplierDetail", id: arg.id }],
    }),
  }),
});

export const {
  useGetCategoriesQuery,
  useCreateCategoryMutation,
  useUpdateCategoryMutation,
  useDeleteCategoryMutation,
  useGetSuppliersQuery,
  useGetSupplierByIdQuery,
  useCreateSupplierMutation,
  useUpdateSupplierMutation,
  useDeleteSupplierMutation,
  useCreateSupplierPaymentMutation,
} = masterService;
