import { apiSlice } from "./api.service";

export const sectionService = apiSlice.injectEndpoints({
  endpoints: (builder) => ({
    getSections: builder.query({
      query: () => "/sections",
      providesTags: ["Section", "Dashboard"],
    }),
    createSection: builder.mutation({
      query: (body) => ({
        url: "/sections",
        method: "POST",
        body,
      }),
      invalidatesTags: ["Section", "Dashboard"],
    }),
    updateSection: builder.mutation({
      query: ({ id, ...body }) => ({
        url: `/sections/${id}`,
        method: "PUT",
        body,
      }),
      invalidatesTags: ["Section", "Dashboard"],
    }),
    deleteSection: builder.mutation({
      query: (id) => ({
        url: `/sections/${id}`,
        method: "DELETE",
      }),
      invalidatesTags: ["Section", "Dashboard"],
    }),
    getSectionAllocations: builder.query({
      query: (id) => `/sections/${id}/allocations`,
      providesTags: (_, __, id) => [{ type: "Section", id }],
    }),
    setSectionAllocations: builder.mutation({
      query: ({ id, items }) => ({
        url: `/sections/${id}/allocations`,
        method: "PUT",
        body: { items },
      }),
      invalidatesTags: (_, __, arg) => ["Section", "Dashboard", { type: "Section", id: arg.id }, "Product"],
    }),
  }),
});

export const {
  useGetSectionsQuery,
  useCreateSectionMutation,
  useUpdateSectionMutation,
  useDeleteSectionMutation,
  useGetSectionAllocationsQuery,
  useSetSectionAllocationsMutation,
} = sectionService;
