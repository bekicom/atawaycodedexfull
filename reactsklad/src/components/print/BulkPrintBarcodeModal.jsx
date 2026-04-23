import { useEffect, useMemo, useState } from "react";
import { buildBarcodeTagMarkup } from "./BarcodeTag";
import { ModalShell } from "../modal/ModalShell";
import { getBarcodeLabelOption, getBarcodePrintSettings, getBarcodeTicketDimensions } from "../../utils/barcodeSettings";

function buildPrintDocument({ tickets, settings }) {
  const { widthMm, heightMm } = getBarcodeTicketDimensions(settings);

  return `
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8" />
        <title>Shtix print</title>
        <style>
          @page {
            size: ${widthMm}mm ${heightMm}mm;
            margin: 0;
          }
          * {
            box-sizing: border-box;
            -webkit-print-color-adjust: exact;
            print-color-adjust: exact;
            color: #000000;
          }
          html, body {
            margin: 0;
            padding: 0;
            background: #ffffff;
            font-family: Arial, sans-serif;
          }
          body {
            width: ${widthMm}mm;
          }
          .print-root {
            width: ${widthMm}mm;
            display: grid;
            gap: 0;
          }
          .barcode-tag-print {
            width: ${widthMm}mm;
            min-width: ${widthMm}mm;
            max-width: ${widthMm}mm;
            min-height: ${heightMm}mm;
            max-height: ${heightMm}mm;
            overflow: hidden;
            page-break-after: always;
          }
          .barcode-tag-print:last-child {
            page-break-after: auto;
          }
          .barcode-simple {
            width: 100%;
            min-height: 100%;
            border: 0.25mm solid #202020;
            background: #ffffff;
            padding: 1.1mm;
            display: grid;
            grid-template-rows: auto auto auto minmax(0, 1fr);
            gap: 0.45mm;
          }
          .barcode-simple-title {
            margin-top: 0.4mm;
            padding-bottom: 0.8mm;
            font-size: 4.95mm;
            line-height: 1;
            font-weight: 900;
            text-transform: uppercase;
            text-align: center;
          }
          .barcode-simple-row {
            padding-bottom: 0.8mm;
            font-size: 3.6mm;
            line-height: 1.1;
            font-weight: 700;
            display: flex;
            gap: 1mm;
            align-items: center;
            justify-content: center;
            text-transform: uppercase;
          }
          .barcode-simple-row--code {
            letter-spacing: 0.08em;
          }
          .barcode-simple-row strong {
            font-weight: 900;
          }
          .barcode-simple-price {
            padding-bottom: 0.35mm;
            text-align: center;
            font-size: 8.9mm;
            line-height: 1;
            font-weight: 900;
          }
          .barcode-simple-barcode {
            display: grid;
            grid-template-rows: minmax(0, 1fr);
            gap: 0;
            align-items: stretch;
            justify-items: center;
            min-height: 0;
          }
          .barcode-simple-code-frame {
            width: 100%;
            min-height: 11.8mm;
            display: grid;
            place-items: center;
            overflow: hidden;
            border: 0;
            padding: 0;
          }
          .barcode-simple-code-frame svg {
            width: 100%;
            height: 100%;
            min-height: 0;
            max-height: none;
            shape-rendering: crispEdges;
            background: #ffffff;
            display: block;
          }
          .barcode-tag-print.landscape .barcode-simple {
            grid-template-rows: auto auto auto 1fr;
            gap: 0.35mm;
            padding: 0.75mm;
          }
          .barcode-tag-print.landscape .barcode-simple-title {
            font-size: 3.3mm;
            margin-top: 0.2mm;
            padding-bottom: 0.45mm;
          }
          .barcode-tag-print.landscape .barcode-simple-row {
            font-size: 2.45mm;
            padding-bottom: 0.25mm;
          }
          .barcode-tag-print.landscape .barcode-simple-price {
            font-size: 5.8mm;
            padding-bottom: 0.2mm;
          }
          .barcode-tag-print.landscape .barcode-simple-code-frame {
            min-height: 7.1mm;
          }
          .barcode-tag-print.landscape .barcode-simple-code-frame svg {
            height: 100%;
            min-height: 0;
            max-height: none;
          }
        </style>
      </head>
      <body>
        <div class="print-root">${tickets}</div>
        <script>
          window.addEventListener("load", function () {
            setTimeout(function () {
              window.print();
            }, 120);
          });
        </script>
      </body>
    </html>
  `;
}

export function BulkPrintBarcodeModal({ open, products, onClose }) {
  const settings = getBarcodePrintSettings();
  const labelOption = getBarcodeLabelOption(settings.labelSize);
  const [selectedMap, setSelectedMap] = useState({});
  const [qtyMap, setQtyMap] = useState({});
  const [searchValue, setSearchValue] = useState("");

  const printableProducts = useMemo(
    () => (products || []).filter((item) => Number(item?.quantity || 0) > 0),
    [products],
  );

  const visibleProducts = useMemo(() => {
    const query = searchValue.trim().toLowerCase();
    if (!query) return printableProducts;

    return printableProducts.filter((item) =>
      [item.name, item.code, item.model, item.barcode]
        .filter(Boolean)
        .join(" ")
        .toLowerCase()
        .includes(query),
    );
  }, [printableProducts, searchValue]);

  useEffect(() => {
    if (!open) return;

    const nextSelected = {};
    const nextQty = {};
    for (const item of printableProducts) {
      nextSelected[item._id] = true;
      nextQty[item._id] = Math.max(1, Math.round(Number(item.quantity || 1)));
    }
    setSelectedMap(nextSelected);
    setQtyMap(nextQty);
    setSearchValue("");
  }, [open, printableProducts]);

  const allSelected = visibleProducts.length > 0 && visibleProducts.every((item) => selectedMap[item._id]);
  const selectedCount = visibleProducts.filter((item) => selectedMap[item._id]).length;
  const totalLabels = visibleProducts.reduce((sum, item) => {
    if (!selectedMap[item._id]) return sum;
    return sum + Math.max(0, Math.round(Number(qtyMap[item._id] || 0)));
  }, 0);

  const toggleAll = (checked) => {
    setSelectedMap((prev) => {
      const next = { ...prev };
      for (const item of visibleProducts) {
        next[item._id] = checked;
      }
      return next;
    });
  };

  const handlePrint = () => {
    const tickets = printableProducts
      .flatMap((item) => {
        if (!selectedMap[item._id]) return [];
        const qty = Math.max(0, Math.round(Number(qtyMap[item._id] || 0)));
        if (qty < 1) return [];
        return Array.from({ length: qty }, () => buildBarcodeTagMarkup(item, settings));
      })
      .join("");

    if (!tickets) return;

    const printWindow = window.open("", "_blank", "width=900,height=700");
    if (!printWindow) return;

    printWindow.document.open();
    printWindow.document.write(buildPrintDocument({ tickets, settings }));
    printWindow.document.close();
  };

  return (
    <ModalShell open={open} title="Mahsulotlar pechati" onClose={onClose} width="900px">
      <div className="bulk-print-sheet">
        <div className="print-toolbar">
          <label className="print-search-wrap">
            <span>Qidiruv</span>
            <input
              className="print-search-input"
              type="search"
              value={searchValue}
              onChange={(event) => setSearchValue(event.target.value)}
              placeholder="Nomi, kodi, shtixi"
            />
          </label>

          <div className="print-settings-note">
            <span>{labelOption.label}</span>
            <span>{settings.orientation === "landscape" ? "Albom" : "Kitob"}</span>
            <span>Tanlangan: {selectedCount}</span>
            <span>Jami etiketka: {totalLabels}</span>
          </div>
        </div>

        <div className="bulk-print-actions">
          <label className="checkbox-row">
            <input
              type="checkbox"
              checked={allSelected}
              onChange={(event) => toggleAll(event.target.checked)}
            />
            Hammasini tanlash
          </label>
        </div>

        <div className="bulk-print-list">
          {visibleProducts.map((item) => (
            <div className="bulk-print-row" key={item._id}>
              <label className="checkbox-row">
                <input
                  type="checkbox"
                  checked={Boolean(selectedMap[item._id])}
                  onChange={(event) => setSelectedMap((prev) => ({ ...prev, [item._id]: event.target.checked }))}
                />
                <span>{item.name} ({item.code || item.model || "-"})</span>
              </label>

              <div className="bulk-print-meta">Miqdori: {item.quantity}</div>
              <div className="bulk-print-meta">Shtix: {item.barcode}</div>

              <label className="bulk-print-qty">
                Chop soni
                <input
                  type="number"
                  min="0"
                  value={qtyMap[item._id] ?? 0}
                  onChange={(event) => {
                    const next = Math.max(0, Number(event.target.value || 0));
                    setQtyMap((prev) => ({ ...prev, [item._id]: next }));
                  }}
                />
              </label>
            </div>
          ))}
          {!visibleProducts.length ? <div className="empty-text">Chop uchun mahsulot topilmadi</div> : null}
        </div>

        <div className="modal-footer">
          <button type="button" className="ghost-btn" onClick={onClose}>Yopish</button>
          <button type="button" className="success-btn" onClick={handlePrint} disabled={!totalLabels}>Tanlanganlarni pechat</button>
        </div>
      </div>
    </ModalShell>
  );
}
