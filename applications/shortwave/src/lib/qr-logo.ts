/** Trusted built-in asset; stored styles use this key, never caller-supplied SVG. */
export const CLICKHOUSE_QR_LOGO = "clickhouse";

// Bar geometry from ClickHouse's SVG favicon: https://github.com/ClickHouse/ClickHouse/blob/master/programs/server/jemalloc.html
// Transparent background with monochrome bars; data URLs keep downloads self-contained.
function clickHouseImage(fill: "#000000" | "#ffffff") {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="54" height="48" viewBox="0 0 11 10"><g fill="${fill}"><path d="M1,1 h1 v8 h-1 z"/><path d="M3,1 h1 v8 h-1 z"/><path d="M5,1 h1 v8 h-1 z"/><path d="M7,1 h1 v8 h-1 z"/><path d="M9,4.25 h1 v1.5 h-1 z"/></g></svg>`;
  return `data:image/svg+xml,${encodeURIComponent(svg)}`;
}
export const CLICKHOUSE_QR_IMAGE = clickHouseImage("#000000");
const whiteClickHouseImage = clickHouseImage("#ffffff");

export function qrLogoImage(logo: string | null | undefined, background = "#ffffff"): string {
  if (logo && logo !== CLICKHOUSE_QR_LOGO) return logo;
  const color = /^#[0-9a-f]{6}$/i.test(background) ? background : "#ffffff";
  const channels = [1, 3, 5].map((offset) => {
    const value = parseInt(color.slice(offset, offset + 2), 16) / 255;
    return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  });
  const luminance = channels[0]! * 0.2126 + channels[1]! * 0.7152 + channels[2]! * 0.0722;
  const blackContrast = (luminance + 0.05) / 0.05;
  const whiteContrast = 1.05 / (luminance + 0.05);
  return blackContrast >= whiteContrast ? CLICKHOUSE_QR_IMAGE : whiteClickHouseImage;
}
