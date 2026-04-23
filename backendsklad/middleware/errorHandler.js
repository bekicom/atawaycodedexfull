export function notFoundHandler(req, res) {
  return res.status(404).json({
    message: `Route topilmadi: ${req.method} ${req.originalUrl}`,
  });
}

export function errorHandler(error, _req, res, _next) {
  console.error("Unhandled backend error:", error);

  if (res.headersSent) {
    return;
  }

  const statusCode =
    Number.isInteger(error?.statusCode) && error.statusCode >= 400
      ? error.statusCode
      : 500;

  return res.status(statusCode).json({
    message: error?.message || "Server xatosi",
  });
}
