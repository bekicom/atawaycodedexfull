import bcrypt from "bcryptjs";
import { Admin } from "../models/Admin.js";

export async function ensureDefaultAdmin() {
  const username = String(process.env.DEFAULT_ADMIN_USERNAME || "admin").trim();
  const password = String(process.env.DEFAULT_ADMIN_PASSWORD || "0000");
  const fullName = String(
    process.env.DEFAULT_ADMIN_FULL_NAME || "Sklad Admin",
  ).trim();

  const existing = await Admin.findOne({ username });
  if (existing) {
    return existing;
  }

  const passwordHash = bcrypt.hashSync(password, 10);
  return Admin.create({
    username,
    passwordHash,
    fullName,
    role: "admin",
    isActive: true,
  });
}
