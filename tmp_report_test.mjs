const base = 'http://127.0.0.1:4000/api';
const stamp = new Date().toISOString().replace(/\D/g, '').slice(8, 14);
const cashier1 = `cashier_report_a_${stamp}`;
const cashier2 = `cashier_report_b_${stamp}`;
const pass = '1111';
const productName = `TEST report ${stamp}`;
const mainBarcode = `93001${stamp}`;
const alias1 = `93101${stamp}`;
const alias2 = `93201${stamp}`;

function eq(a,b){ return Math.abs(Number(a)-Number(b)) < 0.0001; }
function assert(cond,msg,obj){ if(!cond){ throw new Error(msg + (obj?` :: ${JSON.stringify(obj)}`:'')); } }

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
  if (!res.ok) throw new Error(`${res.status} ${url} ${JSON.stringify(data)}`);
  return data;
}

(async () => {
  const adminLogin = await j(`${base}/auth/login`, { method: 'POST', body: JSON.stringify({ username: 'admin', password: '0000' }) });
  const adminToken = adminLogin.token;
  const ah = { Authorization: `Bearer ${adminToken}` };

  const cats = await j(`${base}/categories`, { headers: ah });
  const sups = await j(`${base}/suppliers`, { headers: ah });
  const categoryId = (cats.categories || cats)[0]._id;
  const supplierId = (sups.suppliers || sups)[0]._id;

  await j(`${base}/admin/users`, { method: 'POST', headers: ah, body: JSON.stringify({ username: cashier1, password: pass, role: 'cashier' }) });
  await j(`${base}/admin/users`, { method: 'POST', headers: ah, body: JSON.stringify({ username: cashier2, password: pass, role: 'cashier' }) });

  const createdProduct = await j(`${base}/products`, {
    method: 'POST', headers: ah,
    body: JSON.stringify({
      name: productName,
      model: `TR-${stamp}`,
      barcode: mainBarcode,
      barcodeAliases: [alias1, alias2],
      categoryId, supplierId,
      purchasePrice: 70000,
      retailPrice: 100000,
      wholesalePrice: 95000,
      paymentType: 'naqd', paidAmount: 350000,
      quantity: 5,
      unit: 'pachka',
      allowPieceSale: true,
      pieceUnit: 'dona',
      pieceQtyPerBase: 10,
      piecePrice: 12000
    })
  });
  const product = createdProduct.product;

  const byMain = await j(`${base}/products?q=${mainBarcode}`, { headers: ah });
  const byAlias1 = await j(`${base}/products?q=${alias1}`, { headers: ah });
  const byAlias2 = await j(`${base}/products?q=${alias2}`, { headers: ah });
  assert((byMain.products||[]).some(p=>p._id===product._id),'main barcode qidiruvi ishlamadi');
  assert((byAlias1.products||[]).some(p=>p._id===product._id),'alias1 qidiruvi ishlamadi');
  assert((byAlias2.products||[]).some(p=>p._id===product._id),'alias2 qidiruvi ishlamadi');

  const login1 = await j(`${base}/auth/login`, { method: 'POST', body: JSON.stringify({ username: cashier1, password: pass }) });
  const h1 = { Authorization: `Bearer ${login1.token}` };
  const shift1 = (await j(`${base}/shifts/open`, { method: 'POST', headers: h1, body: '{}' })).shift;

  const salePack = (await j(`${base}/sales`, {
    method: 'POST', headers: h1,
    body: JSON.stringify({ paymentType: 'cash', items: [{ productId: product._id, quantity: 1, priceType: 'retail', unitPrice: 100000, saleMode: 'base', saleUnit: 'pachka', stockPerUnitInBase: 1 }] })
  })).sale;

  const salePieceCard = (await j(`${base}/sales`, {
    method: 'POST', headers: h1,
    body: JSON.stringify({ paymentType: 'card', items: [{ productId: product._id, quantity: 3, priceType: 'retail', unitPrice: 12000, saleMode: 'piece', saleUnit: 'dona', stockPerUnitInBase: 0.1 }] })
  })).sale;

  const salePieceClick = (await j(`${base}/sales`, {
    method: 'POST', headers: h1,
    body: JSON.stringify({ paymentType: 'click', items: [{ productId: product._id, quantity: 1, priceType: 'retail', unitPrice: 12000, saleMode: 'piece', saleUnit: 'dona', stockPerUnitInBase: 0.1 }] })
  })).sale;

  const afterCashier1 = (await j(`${base}/products?q=${mainBarcode}`, { headers: ah })).products[0];
  assert(eq(afterCashier1.quantity, 3.6), 'cashier1 sotuvlaridan keyin qoldiq xato', { qty: afterCashier1.quantity });

  const login2 = await j(`${base}/auth/login`, { method: 'POST', body: JSON.stringify({ username: cashier2, password: pass }) });
  const h2 = { Authorization: `Bearer ${login2.token}` };
  const shift2 = (await j(`${base}/shifts/open`, { method: 'POST', headers: h2, body: '{}' })).shift;

  const salePieceCash2 = (await j(`${base}/sales`, {
    method: 'POST', headers: h2,
    body: JSON.stringify({ paymentType: 'cash', items: [{ productId: product._id, quantity: 2, priceType: 'retail', unitPrice: 12000, saleMode: 'piece', saleUnit: 'dona', stockPerUnitInBase: 0.1 }] })
  })).sale;

  const refund = (await j(`${base}/sales/${salePieceCard._id}/returns`, {
    method: 'POST', headers: h2,
    body: JSON.stringify({ paymentType: 'cash', items: [{ productId: product._id, quantity: 2, variantSize: '', variantColor: '' }] })
  })).sale;

  const afterRefund = (await j(`${base}/products?q=${mainBarcode}`, { headers: ah })).products[0];
  assert(eq(afterRefund.quantity, 3.6), 'refunddan keyin qoldiq xato', { qty: afterRefund.quantity });

  const shift1Sales = await j(`${base}/sales?shiftId=${shift1._id}&limit=50`, { headers: ah });
  const shift2Sales = await j(`${base}/sales?shiftId=${shift2._id}&limit=50`, { headers: ah });
  const shifts1 = await j(`${base}/shifts?cashierUsername=${cashier1}&limit=20`, { headers: ah });
  const shifts2 = await j(`${base}/shifts?cashierUsername=${cashier2}&limit=20`, { headers: ah });

  const expectedShift1 = {
    totalRevenue: 148000,
    totalCollection: 148000,
    totalCash: 100000,
    totalCard: 36000,
    totalClick: 12000,
    totalReturnedAmount: 0,
    netRevenue: 148000,
    netCollection: 148000,
    totalProfit: 50000,
    totalExpense: 98000,
    totalSalesCount: 3,
  };
  const expectedShift2 = {
    totalRevenue: 24000,
    totalCollection: 24000,
    totalCash: 24000,
    totalCard: 0,
    totalClick: 0,
    totalReturnedAmount: 24000,
    netRevenue: 0,
    netCollection: 0,
    totalProfit: 10000,
    totalExpense: 14000,
    totalSalesCount: 1,
  };
  const expectedShiftRoute1 = {
    totalAmount: 148000,
    totalCash: 100000,
    totalCard: 36000,
    totalClick: 12000,
  };
  const expectedShiftRoute2 = {
    totalAmount: 0,
    totalCash: 0,
    totalCard: 0,
    totalClick: 0,
  };

  const s1 = shift1Sales.summary;
  const s2 = shift2Sales.summary;
  assert(eq(s1.totalRevenue, expectedShift1.totalRevenue), 'shift1 totalRevenue xato', s1);
  assert(eq(s1.totalCollection, expectedShift1.totalCollection), 'shift1 totalCollection xato', s1);
  assert(eq(s1.totalCash, expectedShift1.totalCash), 'shift1 totalCash xato', s1);
  assert(eq(s1.totalCard, expectedShift1.totalCard), 'shift1 totalCard xato', s1);
  assert(eq(s1.totalClick, expectedShift1.totalClick), 'shift1 totalClick xato', s1);
  assert(eq(s1.totalReturnedAmount, expectedShift1.totalReturnedAmount), 'shift1 totalReturnedAmount xato', s1);
  assert(eq(s1.netRevenue, expectedShift1.netRevenue), 'shift1 netRevenue xato', s1);
  assert(eq(s1.netCollection, expectedShift1.netCollection), 'shift1 netCollection xato', s1);
  assert(eq(s1.totalProfit, expectedShift1.totalProfit), 'shift1 totalProfit xato', s1);
  assert(eq(s1.totalExpense, expectedShift1.totalExpense), 'shift1 totalExpense xato', s1);
  assert(eq(s1.totalProfit + s1.totalExpense, s1.totalRevenue), 'shift1 profit+expense != revenue', s1);

  assert(eq(s2.totalRevenue, expectedShift2.totalRevenue), 'shift2 totalRevenue xato', s2);
  assert(eq(s2.totalCollection, expectedShift2.totalCollection), 'shift2 totalCollection xato', s2);
  assert(eq(s2.totalCash, expectedShift2.totalCash), 'shift2 totalCash xato', s2);
  assert(eq(s2.totalCard, expectedShift2.totalCard), 'shift2 totalCard xato', s2);
  assert(eq(s2.totalClick, expectedShift2.totalClick), 'shift2 totalClick xato', s2);
  assert(eq(s2.totalReturnedAmount, expectedShift2.totalReturnedAmount), 'shift2 totalReturnedAmount xato', s2);
  assert(eq(s2.netRevenue, expectedShift2.netRevenue), 'shift2 netRevenue xato', s2);
  assert(eq(s2.netCollection, expectedShift2.netCollection), 'shift2 netCollection xato', s2);
  assert(eq(s2.totalProfit, expectedShift2.totalProfit), 'shift2 totalProfit xato', s2);
  assert(eq(s2.totalExpense, expectedShift2.totalExpense), 'shift2 totalExpense xato', s2);
  assert(eq(s2.totalProfit + s2.totalExpense, s2.totalRevenue), 'shift2 profit+expense != revenue', s2);

  const sh1 = (shifts1.shifts || []).find(x => x._id === shift1._id) || shifts1.shifts?.[0];
  const sh2 = (shifts2.shifts || []).find(x => x._id === shift2._id) || shifts2.shifts?.[0];
  assert(eq(sh1.totalAmount, expectedShiftRoute1.totalAmount), 'shift route shift1 totalAmount xato', sh1);
  assert(eq(sh1.totalCash, expectedShiftRoute1.totalCash), 'shift route shift1 totalCash xato', sh1);
  assert(eq(sh1.totalCard, expectedShiftRoute1.totalCard), 'shift route shift1 totalCard xato', sh1);
  assert(eq(sh1.totalClick, expectedShiftRoute1.totalClick), 'shift route shift1 totalClick xato', sh1);
  assert(eq(sh2.totalAmount, expectedShiftRoute2.totalAmount), 'shift route shift2 totalAmount xato', sh2);
  assert(eq(sh2.totalCash, expectedShiftRoute2.totalCash), 'shift route shift2 totalCash xato', sh2);

  const latestReturn = [...refund.returns].sort((a,b)=>new Date(b.createdAt)-new Date(a.createdAt))[0];

  console.log(JSON.stringify({
    result: 'PASS',
    createdCashiers: [cashier1, cashier2],
    product: { name: productName, barcode: mainBarcode, aliases: [alias1, alias2] },
    barcodeSearch: { main: true, alias1: true, alias2: true },
    stockChecks: {
      afterCashier1Expected: 3.6,
      afterCashier1Actual: afterCashier1.quantity,
      afterRefundExpected: 3.6,
      afterRefundActual: afterRefund.quantity
    },
    shift1Expected: expectedShift1,
    shift1Actual: s1,
    shift2Expected: expectedShift2,
    shift2Actual: s2,
    refund: {
      cashier: latestReturn.cashierUsername,
      shift: latestReturn.shiftNumber,
      amount: latestReturn.totalAmount,
      quantity: latestReturn.items[0].quantity,
      baseQuantity: latestReturn.items[0].baseQuantity
    }
  }, null, 2));
})().catch(err => { console.error(String(err)); process.exit(1); });
