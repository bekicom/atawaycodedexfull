import { createApi, fetchBaseQuery } from "@reduxjs/toolkit/query/react";

const baseQuery = fetchBaseQuery({
  baseUrl: import.meta.env.VITE_API_BASE_URL || "http://127.0.0.1:4100/api",
  prepareHeaders: (headers) => {
    const token = localStorage.getItem("sklad_token");
    if (token) headers.set("Authorization", `Bearer ${token}`);
    return headers;
  },
});

const baseQueryWithReauth = async (args, api, extraOptions) => {
  const result = await baseQuery(args, api, extraOptions);

  if (result?.error?.status === 401) {
    localStorage.removeItem("sklad_token");
    localStorage.removeItem("sklad_user");
  }

  return result;
};

export const apiSlice = createApi({
  reducerPath: "api",
  baseQuery: baseQueryWithReauth,
  tagTypes: ["Auth", "Dashboard", "Category", "Supplier", "SupplierDetail", "Product", "Purchase", "Transfer", "Store", "Section", "StoreReturn"],
  endpoints: () => ({}),
});
