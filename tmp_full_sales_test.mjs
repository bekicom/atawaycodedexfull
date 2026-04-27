const base = 'http://127.0.0.1:4000/api';
const stamp = new Date().toISOString().replace(/\D/g, '').slice(8, 14);
const cashier1 = `cashier_pack_a_${stamp}`;
const cashier2 = `cashier_pack_b_${stamp}`;
const pass = '1111';
const productName = `TEST pack ${stamp}`;
const mainBarcode = `90001${stamp}`;
const alias1 = `91001${stamp}`;
const alias2 = `92001${stamp}`;

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
    method: 'POST',
    headers: ah,
    body: JSON.stringify({
      name: productName,
      model: `TP-${stamp}`,
      barcode: mainBarcode,
      barcodeAliases: [alias1, alias2],
      categoryId,
      supplierId,
      purchasePrice: 70000,
      retailPrice: 100000,
      wholesalePrice: 95000,
      paymentType: 'naqd',
      paidAmount: 350000,
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

  const login1 = await j(`${base}/auth/login`, { method: 'POST', body: JSON.stringify({ username: cashier1, password: pass }) });
  const h1 = { Authorization: `Bearer ${login1.token}` };
  await j(`${base}/shifts/open`, { method: 'POST', headers: h1, body: '{}' });

  const packSale = await j(`${base}/sales`, {
    method: 'POST',
    headers: h1,
    body: JSON.stringify({
      paymentType: 'cash',
      items: [{
        productId: product._id,
        quantity: 1,
        priceType: 'retail',
        unitPrice: 100000,
        saleMode: 'base',
        saleUnit: 'pachka',
        stockPerUnitInBase: 1
      }]
    })
  });

  const afterPack = (await j(`${base}/products?q=${mainBarcode}`, { headers: ah })).products[0];

  const pieceSale = await j(`${base}/sales`, {
    method: 'POST',
    headers: h1,
    body: JSON.stringify({
      paymentType: 'cash',
      items: [{
        productId: product._id,
        quantity: 3,
        priceType: 'retail',
        unitPrice: 12000,
        saleMode: 'piece',
        saleUnit: 'dona',
        stockPerUnitInBase: 0.1
      }]
    })
  });

  const afterPiece = (await j(`${base}/products?q=${mainBarcode}`, { headers: ah })).products[0];

  const login2 = await j(`${base}/auth/login`, { method: 'POST', body: JSON.stringify({ username: cashier2, password: pass }) });
  const h2 = { Authorization: `Bearer ${login2.token}` };
  await j(`${base}/shifts/open`, { method: 'POST', headers: h2, body: '{}' });

  const cashier2OwnSale = await j(`${base}/sales`, {
    method: 'POST',
    headers: h2,
    body: JSON.stringify({
      paymentType: 'cash',
      items: [{
        productId: product._id,
        quantity: 2,
        priceType: 'retail',
        unitPrice: 12000,
        saleMode: 'piece',
        saleUnit: 'dona',
        stockPerUnitInBase: 0.1
      }]
    })
  });

  const afterCashier2OwnSale = (await j(`${base}/products?q=${mainBarcode}`, { headers: ah })).products[0];

  const refund = await j(`${base}/sales/${pieceSale.sale._id}/returns`, {
    method: 'POST',
    headers: h2,
    body: JSON.stringify({
      paymentType: 'cash',
      items: [{ productId: product._id, quantity: 2, variantSize: '', variantColor: '' }]
    })
  });

  const afterRefund = (await j(`${base}/products?q=${mainBarcode}`, { headers: ah })).products[0];
  const latestReturn = [...refund.sale.returns].sort((a,b)=>new Date(b.createdAt)-new Date(a.createdAt))[0];

  console.log(JSON.stringify({
    createdCashiers: [
      { username: cashier1, password: pass },
      { username: cashier2, password: pass }
    ],
    tempProduct: {
      id: product._id,
      name: product.name,
      barcode: product.barcode,
      aliases: product.barcodeAliases,
      unit: product.unit,
      quantityInitial: product.quantity,
      retailPrice: product.retailPrice,
      allowPieceSale: product.allowPieceSale,
      pieceQtyPerBase: product.pieceQtyPerBase,
      piecePrice: product.piecePrice
    },
    barcodeSearch: {
      mainBarcodeMatched: (byMain.products || []).some(p => p._id === product._id),
      alias1Matched: (byAlias1.products || []).some(p => p._id === product._id),
      alias2Matched: (byAlias2.products || []).some(p => p._id === product._id)
    },
    stockFlow: {
      initial: product.quantity,
      afterPackSale: afterPack.quantity,
      afterPieceSale: afterPiece.quantity,
      afterCashier2OwnPieceSale: afterCashier2OwnSale.quantity,
      afterRefund: afterRefund.quantity
    },
    packSale: {
      saleId: packSale.sale._id,
      cashier: packSale.sale.cashierUsername,
      shift: packSale.sale.shiftNumber,
      line: packSale.sale.items[0],
      totalAmount: packSale.sale.totalAmount
    },
    pieceSale: {
      saleId: pieceSale.sale._id,
      cashier: pieceSale.sale.cashierUsername,
      shift: pieceSale.sale.shiftNumber,
      line: pieceSale.sale.items[0],
      totalAmount: pieceSale.sale.totalAmount
    },
    cashier2OwnPieceSale: {
      saleId: cashier2OwnSale.sale._id,
      cashier: cashier2OwnSale.sale.cashierUsername,
      shift: cashier2OwnSale.sale.shiftNumber,
      line: cashier2OwnSale.sale.items[0],
      totalAmount: cashier2OwnSale.sale.totalAmount
    },
    refundFromCashier2: {
      refundCashier: latestReturn.cashierUsername,
      refundShift: latestReturn.shiftNumber,
      refundQuantity: latestReturn.items[0].quantity,
      refundBaseQuantity: latestReturn.items[0].baseQuantity,
      refundAmount: latestReturn.totalAmount,
      paymentType: latestReturn.paymentType
    }
  }, null, 2));
})().catch(err => { console.error(String(err)); process.exit(1); });

