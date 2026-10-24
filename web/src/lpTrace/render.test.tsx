import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { LpView } from "./LpView";
import { normalizeTrace } from "./model";
import { sampleDocumentTrace, sampleLotTrace, sampleLpTrace } from "./sample";
import { TreeView } from "./TreeView";

const noop = () => undefined;

describe("rendering", () => {
  it("renders the LP trace with orphan flag, mixed sources and timeline", () => {
    const html = renderToStaticMarkup(<LpView trace={normalizeTrace(sampleLpTrace)} onTrace={noop} />);
    expect(html).toContain("LP001740");
    expect(html).toContain("Yetim");
    expect(html).toContain("2 farklı kaynak");
    expect(html).toContain("Aktarım geldi");
    expect(html).toContain("PU001130");
    expect(html).toContain("Bulunamadı");
    // Bulgularda hata önce gelir.
    expect(html.indexOf("lt-insight--error")).toBeLessThan(html.indexOf("lt-insight--info"));
  });

  it("renders the lot tree with excess state and paged LP list", () => {
    const html = renderToStaticMarkup(<TreeView trace={normalizeTrace(sampleLotTrace)} onTrace={noop} />);
    expect(html).toContain("LP fazlası 45.000");
    expect(html).toContain("Tüm LP&#x27;leri göster (90)");
    expect(html).toContain("geri alındı → 15412");
  });

  it("renders emptied LPs of an undone receipt", () => {
    const html = renderToStaticMarkup(<TreeView trace={normalizeTrace(sampleDocumentTrace)} onTrace={noop} />);
    expect(html).toContain("Boşalmış / geçmiş LP");
    expect(html).toContain("45 geri alma ile boşaltıldı");
    expect(html).toContain("LP001975");
  });
});

describe("rendering flags", () => {
  it("marks a vanished assignment document and LPs on undone entries", () => {
    const lpHtml = renderToStaticMarkup(<LpView trace={normalizeTrace(sampleLpTrace)} onTrace={noop} />);
    expect(lpHtml).toContain('<span class="lt-strike">PU001130</span>');
    const lotHtml = renderToStaticMarkup(<TreeView trace={normalizeTrace(sampleLotTrace)} onTrace={noop} />);
    expect(lotHtml).toContain("geri alınan girişte");
  });
});
