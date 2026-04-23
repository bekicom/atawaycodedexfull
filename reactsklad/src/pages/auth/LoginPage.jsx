import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "../../context/AuthContext";
import { getApiErrorMessage } from "../../context/loading";
import { useLoginMutation } from "../../context/service/auth.service";

export function LoginPage() {
  const navigate = useNavigate();
  const { login } = useAuth();
  const [submitLogin, { isLoading }] = useLoginMutation();
  const [form, setForm] = useState({ username: "admin", password: "0000" });
  const [error, setError] = useState("");

  useEffect(() => {
    document.title = "ATAWAY SKLAD";
  }, []);

  const handleSubmit = async (event) => {
    event.preventDefault();
    setError("");
    try {
      const response = await submitLogin(form).unwrap();
      login(response.token, response.user);
      navigate("/", { replace: true });
    } catch (err) {
      setError(getApiErrorMessage(err, "Login xato"));
    }
  };

  return (
    <div className="login-page">
      <form className="login-card" onSubmit={handleSubmit}>
        <div className="login-head">
          <h1>ATAWAY SKLAD</h1>
        </div>

        <label>
          <span>Login</span>
          <input
            value={form.username}
            onChange={(event) => setForm((prev) => ({ ...prev, username: event.target.value }))}
            placeholder="Login kiriting"
          />
        </label>

        <label>
          <span>Parol</span>
          <input
            type="password"
            value={form.password}
            onChange={(event) => setForm((prev) => ({ ...prev, password: event.target.value }))}
            placeholder="Parol kiriting"
          />
        </label>

        {error ? <div className="error-box">{error}</div> : null}

        <button type="submit" className="login-submit-btn" disabled={isLoading}>
          {isLoading ? "Kirilmoqda..." : "Kirish"}
        </button>
      </form>
    </div>
  );
}
