import { describe, expect, it } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import { HealthPanelApp } from "./HealthPanelApp";
import { normalizeHealth } from "./data";
import { SAMPLE_CLEAN_PAYLOAD, SAMPLE_PAYLOAD } from "./sample";

function render(payload: unknown) {
  return renderToStaticMarkup(<HealthPanelApp initialData={normalizeHealth(payload)} connect={false} />);
}

describe("HealthPanelApp rendering", () => {
  it("renders categories, counts and both quantities", () => {
    const html = render(SAMPLE_PAYLOAD);
    expect(html).toContain("Depo Sağlık Paneli");
    expect(html).toContain("9 sorun bulundu.");
    expect(html).toContain("LP miktarı ile stok tutmuyor");
    expect(html).toContain("45.000");
    expect(html).toContain("90.000");
    expect(html).toContain("+45.000");
    expect(html).toContain("Karşılaştır");
  });

  it("shows the devamı count for truncated categories", () => {
    expect(render(SAMPLE_PAYLOAD)).toContain("+15 bulgu daha var");
  });

  it("disables the fix button with a tooltip when the user cannot write", () => {
    const html = render(SAMPLE_PAYLOAD);
    const idx = html.indexOf('data-issue="5"');
    const card = html.slice(idx, html.indexOf("</article>", idx));
    expect(card).toContain("yazma yetkiniz yok");
    expect(card).toMatch(/<button[^>]*disabled=""[^>]*>LP&#x27;leri boşalt<\/button>/);
  });

  it("links LP source issues to LP trace and compare, with entry metrics", () => {
    const html = render(SAMPLE_PAYLOAD);
    const idx = html.indexOf('data-issue="6"');
    const card = html.slice(idx, html.indexOf("</article>", idx));
    expect(card).toContain("LP izini aç");
    expect(card).toContain("Karşılaştır");
    expect(card).toContain("Girişte kalan");
    expect(card).toContain("LP0003311");
  });

  it("enables fix for permitted issues and offers fix-all", () => {
    const html = render(SAMPLE_PAYLOAD);
    const idx = html.indexOf('data-issue="3"');
    const card = html.slice(idx, html.indexOf("</article>", idx));
    expect(card).not.toContain("disabled");
    expect(html).toContain("Tümünü serbest bırak");
  });

  it("puts clean categories in the sorunsuz list", () => {
    const html = render(SAMPLE_PAYLOAD);
    expect(html).toContain("Sorunsuz kontroller");
    expect(html).toContain("Eski veya pasif yazıcı eşleşmesi");
  });

  it("shows the all-clear state", () => {
    const html = render(SAMPLE_CLEAN_PAYLOAD);
    expect(html).toContain("Açık sorun yok.");
    expect(html).not.toContain("hp-issue ");
  });

  it("shows a loading state before data arrives", () => {
    const html = renderToStaticMarkup(<HealthPanelApp connect={false} />);
    expect(html).toContain("Depo taranıyor");
  });
});
