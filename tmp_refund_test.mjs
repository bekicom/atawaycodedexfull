const base = 'http://127.0.0.1:4000/api';
const stamp = new Date().toISOString().replace(/\D/g, '').slice(8, 14);
const cashier1 = `cashier_a_${stamp}`;
const cashier2 = `cashier_b_${stamp}`;
const pass = '1111';

async function j(url, options = {}) {
  const res = await fetch(url, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...(options.headers || {}),
    },
  });
  const text = await res.text();
  let data;
  try { data = text ? JSON.parse(text) : {}; } catch { data = { raw: text }; }
  if (!res.ok) throw new Error(`${res.status} ${JSON.stringify(data)}`);
  return data;
}

(async () => {
  const adminLogin = await j(`${base}/auth/login`, { method: 'POST', body: JSON.stringify({ username: 'admin', password: '0000' }) });
  const adminToken = adminLogin.token;
  const ah = { Authorization: `Bearer ${adminToken}` };
  await j(`${base}/admin/users`, { method: 'POST', headers: ah, body: JSON.stringify({ username: cashier1, password: pass, role: 'cashier' }) });
  await j(`${base}/admin/users`, { method: 'POST', headers: ah, body: JSON.stringify({ username: cashier2, password: pass, role: 'cashier' }) });
  const productsResp = await j(`${base}/products`, { headers: ah });
  const product = productsResp.products.find(p => Number(p.quantity) >= 3 && Number(p.retailPrice) > 0);
  if (!product) throw new Error('No product with quantity >= 3');

  const login1 = await j(`${base}/auth/login`, { method: 'POST', body: JSON.stringify({ username: cashier1, password: pass }) });
  const h1 = { Authorization: `Bearer ${login1.token}` };
  await j(`${base}/shifts/open`, { method: 'POST', headers: h1, body: '{}' });
  const sale1 = (await j(`${base}/sales`, { method: 'POST', headers: h1, body: JSON.stringify({ paymentType: 'cash', items: [{ productId: product._id, quantity: 1, priceType: 'retail' }] }) })).sale;

  const login2 = await j(`${base}/auth/login`, { method: 'POST', body: JSON.stringify({ username: cashier2, password: pass }) });
  const h2 = { Authorization: `Bearer ${login2.token}` };
  await j(`${base}/shifts/open`, { method: 'POST', headers: h2, body: '{}' });
  const sale2 = (await j(`${base}/sales`, { method: 'POST', headers: h2, body: JSON.stringify({ paymentType: 'cash', items: [{ productId: product._id, quantity: 1, priceType: 'retail' }] }) })).sale;

  const updatedSale = (await j(`${base}/sales/${sale1._id}/returns`, { method: 'POST', headers: h2, body: JSON.stringify({ paymentType: 'cash', items: [{ productId: product._id, quantity: 1, variantSize: '', variantColor: '' }] }) })).sale;
  const latestReturn = [...updatedSale.returns].sort((a,b) => new Date(b.createdAt) - new Date(a.createdAt))[0];
  const returnsResp = await j(`${base}/sales/returns?period=today&limit=20`, { headers: ah });
  const returnHistory = returnsResp.returns.find(r => r.saleId === sale1._id);

  console.log(JSON.stringify({
    createdCashiers: [
      { username: cashier1, password: pass },
      { username: cashier2, password: pass }
    ],
    product: { id: product._id, name: product.name, model: product.model, price: product.retailPrice },
    originalSale: { saleId: sale1._id, cashier: sale1.cashierUsername, shift: sale1.shiftNumber, amount: sale1.totalAmount },
    cashier2OwnSale: { saleId: sale2._id, cashier: sale2.cashierUsername, shift: sale2.shiftNumber, amount: sale2.totalAmount },
    refundRecordInSale: { cashier: latestReturn.cashierUsername, shift: latestReturn.shiftNumber, amount: latestReturn.totalAmount, paymentType: latestReturn.paymentType },
    refundRecordInReturnsPage: returnHistory ? { cashier: returnHistory.cashierUsername, shift: returnHistory.shiftNumber, amount: returnHistory.totalAmount, paymentType: returnHistory.paymentType } : null
  }, null, 2));
})().catch(err => { console.error(String(err)); process.exit(1); });
