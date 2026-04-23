import { apiSlice } from "./api.service";

export const addProductService = apiSlice.injectEndpoints({
  endpoints: (builder) => ({
    getProducts: builder.query({
      query: ({ q = "", categoryId = "", supplierId = "" } = {}) => {
        const params = new URLSearchParams();
        if (q) params.set("q", q);
        if (categoryId) params.set("categoryId", categoryId);
        if (supplierId) params.set("supplierId", supplierId);
        const query = params.toString();
        return query ? `/products?${query}` : "/products";
      },
      providesTags: ["Product"],
    }),
    getProductById: builder.query({
      query: (id) => `/products/${id}`,
      providesTags: (_, __, id) => [{ type: "Product", id }],
    }),
    createProduct: builder.mutation({
      query: (body) => ({
        url: "/products",
        method: "POST",
        body,
      }),
      invalidatesTags: ["Product", "Supplier", "Dashboard", "Purchase", "Section"],
    }),
    updateProduct: builder.mutation({
      query: ({ id, ...body }) => ({
        url: `/products/${id}`,
        method: "PUT",
        body,
      }),
      invalidatesTags: (_, __, arg) => ["Product", "Supplier", "Dashboard", "Purchase", "Section", { type: "Product", id: arg.id }],
    }),
    deleteProduct: builder.mutation({
      query: (id) => ({
        url: `/products/${id}`,
        method: "DELETE",
      }),
      invalidatesTags: ["Product", "Supplier", "Dashboard", "Purchase", "Section"],
    }),
    restockProduct: builder.mutation({
      query: ({ id, ...body }) => ({
        url: `/products/${id}/restock`,
        method: "POST",
        body,
      }),
      invalidatesTags: (_, __, arg) => ["Product", "Supplier", "Dashboard", "Purchase", "Section", { type: "Product", id: arg.id }],
    }),
  }),
});

export const {
  useGetProductsQuery,
  useLazyGetProductsQuery,
  useGetProductByIdQuery,
  useCreateProductMutation,
  useUpdateProductMutation,
  useDeleteProductMutation,
  useRestockProductMutation,
} = addProductService;
