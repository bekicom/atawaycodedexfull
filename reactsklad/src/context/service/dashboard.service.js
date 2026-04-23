import { apiSlice } from "./api.service";

export const dashboardService = apiSlice.injectEndpoints({
  endpoints: (builder) => ({
    getOverview: builder.query({
      query: () => "/dashboard/overview",
      providesTags: ["Dashboard"],
    }),
  }),
});

export const { useGetOverviewQuery } = dashboardService;
