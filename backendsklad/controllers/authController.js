import bcrypt from "bcryptjs";
import jwt from "jsonwebtoken";
import { Admin } from "../models/Admin.js";
import { asyncHandler } from "../utils/asyncHandler.js";

function signToken(admin) {
  return jwt.sign(
    {
      id: String(admin._id),
      username: admin.username,
      role: admin.role,
    },
    process.env.JWT_SECRET,
    { expiresIn: "12h" },
  );
}

export const login = asyncHandler(async (req, res) => {
  const username = String(req.body?.username || "").trim();
  const password = String(req.body?.password || "");

  if (!username || !password) {
    return res.status(400).json({ message: "Login va parol kerak" });
  }

  const admin = await Admin.findOne({ username });
  if (!admin || !admin.isActive) {
    return res.status(401).json({ message: "Login yoki parol noto'g'ri" });
  }

  const isValid = bcrypt.compareSync(password, admin.passwordHash);
  if (!isValid) {
    return res.status(401).json({ message: "Login yoki parol noto'g'ri" });
  }

  admin.lastLoginAt = new Date();
  await admin.save();

  return res.json({
    token: signToken(admin),
    user: {
      id: admin._id,
      username: admin.username,
      fullName: admin.fullName,
      role: admin.role,
    },
  });
});

export const me = asyncHandler(async (req, res) => {
  const admin = await Admin.findById(req.user.id).lean();

  if (!admin) {
    return res.status(404).json({ message: "Foydalanuvchi topilmadi" });
  }

  return res.json({
    user: {
      id: admin._id,
      username: admin.username,
      fullName: admin.fullName,
      role: admin.role,
      lastLoginAt: admin.lastLoginAt,
    },
  });
});
