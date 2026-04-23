export function isApiErrorWithMessage(error) {
  return Boolean(error?.data?.message || error?.message);
}

export function getApiErrorMessage(error, fallback = "Xatolik yuz berdi") {
  return error?.data?.message || error?.message || fallback;
}
