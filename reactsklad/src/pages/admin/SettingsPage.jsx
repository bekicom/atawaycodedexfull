import { useMemo, useState } from "react";
import { BarcodeTag } from "../../components/print/BarcodeTag";
import { PageHeader } from "../../components/page_header/PageHeader";
import {
  BARCODE_LABEL_OPTIONS,
  BARCODE_PRINT_DEFAULTS,
  getBarcodeLabelOption,
  getBarcodePrintSettings,
  getBarcodeTicketDimensions,
  saveBarcodePrintSettings,
} from "../../utils/barcodeSettings";

const PREVIEW_PRODUCT = {
  name: "TEST MAHSULOT",
  code: "4512",
  category: "Kiyimlar",
  barcode: "2427000098116",
  retailPrice: 25000,
  sizeOptions: ["5-8"],
  colorOptions: ["Multikolor"],
  gender: "ogil_bola",
};

export function SettingsPage() {
  const [settings, setSettings] = useState(() => getBarcodePrintSettings());
  const [saved, setSaved] = useState("");

  const labelOption = useMemo(
    () => getBarcodeLabelOption(settings.labelSize),
    [settings.labelSize],
  );
  const { widthMm: previewWidthMm, heightMm: previewHeightMm } = getBarcodeTicketDimensions(settings);
  const previewWidth = previewWidthMm * 4;
  const previewHeight = previewHeightMm * 4;

  const updateSettings = (patch) => {
    setSaved("");
    setSettings((prev) => ({ ...prev, ...patch }));
  };

  const handleSave = () => {
    saveBarcodePrintSettings(settings);
    setSaved("Sozlamalar saqlandi");
  };

  const handleReset = () => {
    saveBarcodePrintSettings(BARCODE_PRINT_DEFAULTS);
    setSettings(BARCODE_PRINT_DEFAULTS);
    setSaved("Standart sozlama tiklandi");
  };

  return (
    <div className="page-stack">
      <PageHeader
        title="Sozlamalar"
        subtitle="Shtixkod chop etishdan oldin label ko'rinishi va yo'nalishini sozlang"
      />

      <section className="panel-box barcode-settings-panel">
        <div className="barcode-settings-head">
          <div className="barcode-settings-title">
            <span className="settings-icon-box" aria-hidden="true">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                <path d="M4 7h2M4 12h4M4 17h2M10 7h1M10 17h1M15 7h1M15 12h1M15 17h1M19 7h1M19 12h1M19 17h1" />
              </svg>
            </span>
            <div>
              <h3>Shtixkod chop etish sozlamalari</h3>
            </div>
          </div>
          <div className="page-actions">
            <button type="button" className="ghost-btn" onClick={handleReset}>Standart holat</button>
            <button type="button" className="primary-btn" onClick={handleSave}>Saqlash</button>
          </div>
        </div>

        {saved ? <div className="success-inline-box">{saved}</div> : null}

        <div className="barcode-settings-grid">
          <label>
            Label o'lchami
            <input type="text" value={BARCODE_LABEL_OPTIONS[0].label} readOnly />
          </label>

          <label>
            Har chop etishda nusxa soni
            <input
              type="number"
              min="1"
              max="20"
              value={settings.copies}
              onChange={(event) => updateSettings({ copies: Math.max(1, Number(event.target.value) || 1) })}
            />
          </label>

          <label>
            Yo'nalish
            <select
              value={settings.orientation}
              onChange={(event) => updateSettings({ orientation: event.target.value })}
            >
              <option value="portrait">Kitob</option>
              <option value="landscape">Albom</option>
            </select>
          </label>
        </div>

        <div className="barcode-settings-checks">
          <span>Ko'rinadigan ma'lumotlar</span>
          <label className="checkbox-row">
            <input
              type="checkbox"
              checked={settings.showName}
              onChange={(event) => updateSettings({ showName: event.target.checked })}
            />
            Nomi
          </label>
          <label className="checkbox-row">
            <input
              type="checkbox"
              checked={settings.showPrice}
              onChange={(event) => updateSettings({ showPrice: event.target.checked })}
            />
            Narx
          </label>
          <label className="checkbox-row">
            <input
              type="checkbox"
              checked={settings.showCode}
              onChange={(event) => updateSettings({ showCode: event.target.checked })}
            />
            Kod
          </label>
          <label className="checkbox-row">
            <input
              type="checkbox"
              checked={settings.showCategory}
              onChange={(event) => updateSettings({ showCategory: event.target.checked })}
            />
            Kategoriya
          </label>
        </div>

        <div className="barcode-preview-block">
          <BarcodeTag
            product={PREVIEW_PRODUCT}
            settings={settings}
            preview
            style={{
              width: `${previewWidth}px`,
              minHeight: `${previewHeight}px`,
              "--ticket-width-mm": `${previewWidthMm}mm`,
              "--ticket-height-mm": `${previewHeightMm}mm`,
            }}
            className="barcode-ticket-preview"
          />
        </div>
      </section>
    </div>
  );
}
