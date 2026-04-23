import cors from "cors";
import dotenv from "dotenv";
import express from "express";

import { connectDb } from "./config/db.js";
import { errorHandler, notFoundHandler } from "./middleware/errorHandler.js";
import mainRoutes from "./routes/mainRoutes.js";
import { ensureDefaultAdmin } from "./utils/bootstrap.js";

dotenv.config();

const app = express();
const port = Number(process.env.PORT || 4100);
const mongoUri =
  process.env.MONGO_URI || "mongodb://127.0.0.1:27017/kiyim_dokon_sklad";

app.use(cors());
app.use(express.json({ limit: "10mb" }));

app.get("/health", (_req, res) => {
  res.json({
    ok: true,
    service: "backendsklad",
  });
});

app.use("/api", mainRoutes);

app.use(notFoundHandler);
app.use(errorHandler);

async function start() {
  await connectDb(mongoUri);
  await ensureDefaultAdmin();

  app.listen(port, () => {
    console.log(`Backendsklad API is running on http://localhost:${port}`);
  });
}

start().catch((error) => {
  console.error("Backendsklad startup failed:", error);
  process.exit(1);
});
