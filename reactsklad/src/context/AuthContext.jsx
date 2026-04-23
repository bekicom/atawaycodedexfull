import { createContext, useContext, useMemo, useState } from "react";
import { useDispatch } from "react-redux";
import { apiSlice } from "./service/api.service";

const AuthContext = createContext(null);

function readStoredUser() {
  try {
    const raw = localStorage.getItem("sklad_user");
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

export function AuthProvider({ children }) {
  const dispatch = useDispatch();
  const [token, setToken] = useState(() => localStorage.getItem("sklad_token") || "");
  const [user, setUser] = useState(readStoredUser);

  const login = (nextToken, nextUser) => {
    localStorage.setItem("sklad_token", nextToken);
    localStorage.setItem("sklad_user", JSON.stringify(nextUser));
    setToken(nextToken);
    setUser(nextUser);
    dispatch(apiSlice.util.resetApiState());
  };

  const logout = () => {
    localStorage.removeItem("sklad_token");
    localStorage.removeItem("sklad_user");
    setToken("");
    setUser(null);
    dispatch(apiSlice.util.resetApiState());
  };

  const value = useMemo(() => ({
    token,
    user,
    login,
    logout,
  }), [token, user]);

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) throw new Error("useAuth must be used inside AuthProvider");
  return context;
}
