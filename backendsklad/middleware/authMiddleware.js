import jwt from "jsonwebtoken";
import { Admin } from "../models/Admin.js";

export async function authMiddleware(req, res, next) {
  try {
    const authHeader = String(req.headers.authorization || "");
    const [, token] = authHeader.split(" ");

    if (!token) {
      return res.status(401).json({ message: "Token kerak" });
    }

    const payload = jwt.verify(token, process.env.JWT_SECRET);
    const admin = await Admin.findById(payload.id).lean();

    if (!admin || !admin.isActive) {
      return res.status(401).json({ message: "Sessiya yaroqsiz" });
    }

    req.user = {
      id: String(admin._id),
      username: admin.username,
      fullName: admin.fullName,
      role: admin.role,
    };

    return next();
  } catch (_error) {
    return res.status(401).json({ message: "Token noto'g'ri yoki eskirgan" });
  }
}
