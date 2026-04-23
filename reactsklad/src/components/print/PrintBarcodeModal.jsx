import { BarcodeTag, buildBarcodeTagMarkup } from "./BarcodeTag";
import { ModalShell } from "../modal/ModalShell";
import { getBarcodeLabelOption, getBarcodePrintSettings, getBarcodeTicketDimensions } from "../../utils/barcodeSettings";

function buildPrintDocument({ product, settings, copies }) {
  const { widthMm, heightMm } = getBarcodeTicketDimensions(settings);
  const tickets = Array.from({ length: copies }, () => buildBarcodeTagMarkup(product, settings)).join("");

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
          .barcode-tag {
            width: 100%;
            min-height: 100%;
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

export function PrintBarcodeModal({ open, product, onClose }) {
  const settings = getBarcodePrintSettings();
  const labelOption = getBarcodeLabelOption(settings.labelSize);
  const tickets = Array.from({ length: settings.copies }, (_, index) => index);
  const { widthMm: ticketWidthMm, heightMm: ticketHeightMm } = getBarcodeTicketDimensions(settings);
  const ticketWidth = ticketWidthMm * 4;
  const ticketHeight = ticketHeightMm * 4;
  const handlePrint = () => {
    const printWindow = window.open("", "_blank", "width=900,height=700");
    if (!printWindow) return;

    printWindow.document.open();
    printWindow.document.write(buildPrintDocument({ product, settings, copies: settings.copies }));
    printWindow.document.close();
  };

  return (
      <ModalShell open={open} title="Shtixkodni chop etish" onClose={onClose} width="760px">
      <div className="print-sheet">
        <div className="print-settings-note">
          <span>{labelOption.label}</span>
          <span>{settings.orientation === "landscape" ? "Albom" : "Kitob"}</span>
          <span>{settings.copies} nusxa</span>
        </div>
        <div className={`barcode-sheet-grid ${settings.orientation === "landscape" ? "landscape" : ""}`}>
          {tickets.map((ticketIndex) => (
            <BarcodeTag
              key={ticketIndex}
              product={product}
              settings={settings}
              style={{
                width: `${ticketWidth}px`,
                minHeight: `${ticketHeight}px`,
                "--ticket-width-mm": `${ticketWidthMm}mm`,
                "--ticket-height-mm": `${ticketHeightMm}mm`,
              }}
            />
          ))}
        </div>
        <div className="modal-footer">
          <button type="button" className="ghost-btn" onClick={onClose}>Yopish</button>
          <button type="button" className="success-btn" onClick={handlePrint}>Print</button>
        </div>
      </div>
    </ModalShell>
  );
}
