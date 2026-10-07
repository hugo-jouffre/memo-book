/*
 * Cartes de chapitre, côté atelier.
 *
 * **Recopie de `backend/src/services/mapSvg.ts`** : même projection (Mercator),
 * même cadrage sur la première région, même contour lissé, mêmes épingles.
 * L'atelier envoie son payload directement à APITemplate, sans passer par le
 * back-end qui y insère `map_svg` : il doit donc dessiner la carte lui-même.
 * `backend/test/carteAtelier.test.ts` compare les deux sorties — une retouche
 * d'un côté sans l'autre le fait échouer.
 *
 * Un ajout propre à l'atelier : les **points secondaires** (`secondaire:
 * true`), les étapes déjà parcourues. Ils se dessinent en petit, sans nom,
 * reliés par le trajet en pointillé : sur une carte de la Grèce entière, Paros,
 * Naxos et Ios tiennent dans un centimètre, et trois noms s'y chevaucheraient.
 * Seul le lieu du chapitre porte son nom.
 *
 * Les contours (`assets/maps/countries.json`, Natural Earth 110 m) sont lus sur
 * GitHub au moment de dessiner, comme les polices du gabarit.
 */
(function (racine) {
  "use strict";

  const MAX_LAT = 84;
  const OUTLINE = "#19532b";
  const FILL = "rgba(25, 83, 43, 0.05)";
  const PIN = "#f86015";
  const TENSION = 0.22;

  const mercatorX = (lon) => (lon * Math.PI) / 180;
  function mercatorY(lat) {
    const clamped = Math.max(-MAX_LAT, Math.min(MAX_LAT, lat));
    const rad = (clamped * Math.PI) / 180;
    return Math.log(Math.tan(Math.PI / 4 + rad / 2));
  }

  function buildFrame(rings, width, height) {
    let minX = Infinity;
    let maxX = -Infinity;
    let minY = Infinity;
    let maxY = -Infinity;
    for (const ring of rings) {
      for (const [lon, lat] of ring) {
        const x = mercatorX(lon);
        const y = mercatorY(lat);
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
    const padding = 10;
    const usableW = width - padding * 2;
    const usableH = height - padding * 2;
    const scale = Math.min(usableW / (maxX - minX || 1), usableH / (maxY - minY || 1));
    return { minX, maxX, minY, maxY, scale, width, height, padding };
  }

  function project(frame, lon, lat) {
    const spanX = (frame.maxX - frame.minX) * frame.scale;
    const spanY = (frame.maxY - frame.minY) * frame.scale;
    const offsetX = (frame.width - spanX) / 2;
    const offsetY = (frame.height - spanY) / 2;
    const x = offsetX + (mercatorX(lon) - frame.minX) * frame.scale;
    const y = offsetY + (frame.maxY - mercatorY(lat)) * frame.scale;
    return [Math.round(x * 10) / 10, Math.round(y * 10) / 10];
  }

  function smoothPath(points) {
    const n = points.length;
    const at = (i) => points[((i % n) + n) % n];
    const round = (v) => Math.round(v * 10) / 10;
    const start = at(0);
    let d = `M${start[0]} ${start[1]}`;
    for (let i = 0; i < n; i += 1) {
      const p0 = at(i - 1);
      const p1 = at(i);
      const p2 = at(i + 1);
      const p3 = at(i + 2);
      const c1x = p1[0] + (p2[0] - p0[0]) * TENSION;
      const c1y = p1[1] + (p2[1] - p0[1]) * TENSION;
      const c2x = p2[0] - (p3[0] - p1[0]) * TENSION;
      const c2y = p2[1] - (p3[1] - p1[1]) * TENSION;
      d += ` C${round(c1x)} ${round(c1y)} ${round(c2x)} ${round(c2y)} ${round(p2[0])} ${round(p2[1])}`;
    }
    return `${d}Z`;
  }

  const escapeXml = (value) =>
    String(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");

  /**
   * Le SVG de la carte. `contours` est le contenu de `countries.json`.
   * Sans point secondaire, la sortie est celle de `renderMapSvg` du back-end,
   * à l'octet près.
   */
  function renderMapSvg(contours, request) {
    const { regions, points = [], widthPt = 200, heightPt = 260 } = request;
    if (!regions || regions.length === 0) throw new Error("Une carte demande au moins une région.");

    const shapes = regions.map((code) => {
      const country = contours[String(code).toUpperCase()];
      if (!country) throw new Error(`Région « ${code} » inconnue.`);
      return { code, rings: country.rings };
    });
    const frame = buildFrame(shapes[0].rings, widthPt, heightPt);

    const paths = shapes
      .map(({ rings }) =>
        rings
          .map((ring) => {
            const pts = ring.map(([lon, lat]) => project(frame, lon, lat));
            if (pts.length < 4) return "";
            return (
              `<path d="${smoothPath(pts)}" fill="${FILL}" stroke="${OUTLINE}" ` +
              `stroke-width="1.1" stroke-linejoin="round" stroke-linecap="round" ` +
              `stroke-dasharray="3.2 2.6"/>`
            );
          })
          .join(""),
      )
      .join("");

    // Le trajet : les étapes parcourues, dans l'ordre, jusqu'au lieu du chapitre.
    const avecTrajet = points.some((p) => p.secondaire);
    const trajet = avecTrajet
      ? `<polyline points="${points
          .map((p) => project(frame, p.lon, p.lat).join(","))
          .join(" ")}" fill="none" stroke="${PIN}" stroke-width="0.9" stroke-dasharray="2 2" stroke-linecap="round"/>`
      : "";

    const pins = points
      .map((point) => {
        const [x, y] = project(frame, point.lon, point.lat);
        if (point.secondaire) {
          return `<circle cx="${x}" cy="${y}" r="2.2" fill="#fff" stroke="${PIN}" stroke-width="1.1"/>`;
        }
        const pin =
          `<path d="M${x} ${y} c-3.4 -4.6 -5.2 -6.8 -5.2 -9.4 a5.2 5.2 0 1 1 10.4 0 ` +
          `c0 2.6 -1.8 4.8 -5.2 9.4Z" fill="${PIN}"/>` +
          `<circle cx="${x}" cy="${y - 9.4}" r="1.9" fill="#fff"/>`;
        const label =
          `<text x="${x}" y="${y + 9}" text-anchor="middle" fill="${PIN}" ` +
          `font-family="Playfair Display, serif" font-weight="900" font-size="7.5">` +
          `${escapeXml(point.label)}</text>`;
        return pin + label;
      })
      .join("");

    return (
      `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${widthPt} ${heightPt}" ` +
      `width="${widthPt}" height="${heightPt}">${paths}${trajet}${pins}</svg>`
    );
  }

  /** Le SVG en data URI, tel qu'il part dans `map_svg`. */
  function renderMapDataUri(contours, request) {
    const svg = renderMapSvg(contours, request);
    const octets = new TextEncoder().encode(svg);
    let binaire = "";
    for (const octet of octets) binaire += String.fromCharCode(octet);
    return `data:image/svg+xml;base64,${btoa(binaire)}`;
  }

  const api = { renderMapSvg, renderMapDataUri };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else racine.Carte = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
