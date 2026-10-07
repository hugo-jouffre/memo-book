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
 *
 * Second ajout : la **carte cadrée sur le voyage** (`renderCarteCadree`). Le
 * back-end cadre sur le pays entier, et 110 m n'a pas les petites îles : un
 * voyage dans les Cyclades donnait le continent grec et une épingle en pleine
 * mer. L'atelier cadre sur la zone que les récits parcourent
 * (`MiseEnPage.cadreDuVoyage`) et dessine les contours de Natural Earth 10 m
 * (`assets/maps/detail/<ISO2>.json`, `backend/scripts/build-map-detail.ts`),
 * simplifiés à la volée au demi-point près.
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

  /* ------------------------------------------- carte cadrée sur le voyage --- */

  /** Simplification Douglas-Peucker, en points de page : le trait ne garde que ce qui se voit. */
  function simplifier(points, tolerance) {
    if (points.length < 4) return points;
    const garder = new Uint8Array(points.length);
    garder[0] = 1;
    garder[points.length - 1] = 1;
    const pile = [[0, points.length - 1]];
    while (pile.length) {
      const [a, b] = pile.pop();
      const [x1, y1] = points[a];
      const [x2, y2] = points[b];
      const dx = x2 - x1;
      const dy = y2 - y1;
      const l2 = dx * dx + dy * dy;
      let max = 0;
      let index = -1;
      for (let i = a + 1; i < b; i += 1) {
        const [x, y] = points[i];
        const t = l2 ? Math.max(0, Math.min(1, ((x - x1) * dx + (y - y1) * dy) / l2)) : 0;
        const d = Math.hypot(x - (x1 + t * dx), y - (y1 + t * dy));
        if (d > max) {
          max = d;
          index = i;
        }
      }
      if (max > tolerance && index > 0) {
        garder[index] = 1;
        pile.push([a, index], [index, b]);
      }
    }
    return points.filter((_, i) => garder[i]);
  }

  /**
   * Coupe un contour au rectangle `[x0, y0, x1, y1]` (Sutherland-Hodgman). Ce
   * qui sort de la carte n'a pas à peser dans le payload : sans cette coupe, le
   * continent grec entier partait dans une carte des Cyclades.
   */
  function couper(points, [x0, y0, x1, y1]) {
    const bords = [
      [(p) => p[0] >= x0, (a, b) => [x0, a[1] + ((b[1] - a[1]) * (x0 - a[0])) / (b[0] - a[0])]],
      [(p) => p[0] <= x1, (a, b) => [x1, a[1] + ((b[1] - a[1]) * (x1 - a[0])) / (b[0] - a[0])]],
      [(p) => p[1] >= y0, (a, b) => [a[0] + ((b[0] - a[0]) * (y0 - a[1])) / (b[1] - a[1]), y0]],
      [(p) => p[1] <= y1, (a, b) => [a[0] + ((b[0] - a[0]) * (y1 - a[1])) / (b[1] - a[1]), y1]],
    ];
    let sortie = points;
    for (const [dedans, croisement] of bords) {
      const entree = sortie;
      sortie = [];
      for (let i = 0; i < entree.length; i += 1) {
        const a = entree[(i + entree.length - 1) % entree.length];
        const b = entree[i];
        if (dedans(b)) {
          if (!dedans(a)) sortie.push(croisement(a, b));
          sortie.push(b);
        } else if (dedans(a)) sortie.push(croisement(a, b));
      }
      if (!sortie.length) break;
    }
    return sortie.map(([x, y]) => [Math.round(x * 10) / 10, Math.round(y * 10) / 10]);
  }

  const seCroisent = (a, b) => a[0] <= b[2] && b[0] <= a[2] && a[1] <= b[3] && b[1] <= a[3];
  const boiteDe = (ring) => {
    let o = Infinity;
    let s = Infinity;
    let e = -Infinity;
    let n = -Infinity;
    for (const [lon, lat] of ring) {
      if (lon < o) o = lon;
      if (lon > e) e = lon;
      if (lat < s) s = lat;
      if (lat > n) n = lat;
    }
    return [o, s, e, n];
  };

  /**
   * La carte d'un chapitre cadrée sur la zone que le voyage parcourt, et non
   * sur le pays entier : un voyage dans les Cyclades montre les Cyclades, pas
   * le continent grec avec une épingle en pleine mer.
   *
   * `detail` : les contours détaillés (`assets/maps/detail/<ISO2>.json`) des
   * pays qui touchent le cadre, indexés par code. `request.cadre` :
   * `[ouest, sud, est, nord]` en degrés, élargi ici au format de la carte. Tous
   * les pays chargés se dessinent — une côte voisine aide à se situer — et ce
   * qui sort du cadre est coupé par le SVG lui-même.
   */
  function renderCarteCadree(detail, request) {
    const { cadre, points = [], widthPt = 200, heightPt = 260 } = request;
    const padding = 10;
    // Le cadre en Mercator, élargi au format de la carte, centré.
    let minX = mercatorX(cadre[0]);
    let maxX = mercatorX(cadre[2]);
    let minY = mercatorY(cadre[1]);
    let maxY = mercatorY(cadre[3]);
    const largeurUtile = widthPt - padding * 2;
    const hauteurUtile = heightPt - padding * 2;
    const scale = Math.min(largeurUtile / (maxX - minX || 1e-6), hauteurUtile / (maxY - minY || 1e-6));
    const manqueX = (largeurUtile / scale - (maxX - minX)) / 2;
    const manqueY = (hauteurUtile / scale - (maxY - minY)) / 2;
    minX -= manqueX;
    maxX += manqueX;
    minY -= manqueY;
    maxY += manqueY;
    const frame = { minX, maxX, minY, maxY, scale, width: widthPt, height: heightPt, padding };
    const vue = [
      (minX * 180) / Math.PI - 0.5,
      ((2 * Math.atan(Math.exp(minY)) - Math.PI / 2) * 180) / Math.PI - 0.5,
      (maxX * 180) / Math.PI + 0.5,
      ((2 * Math.atan(Math.exp(maxY)) - Math.PI / 2) * 180) / Math.PI + 0.5,
    ];

    let paths = "";
    for (const pays of Object.values(detail || {})) {
      if (!pays?.rings || (pays.bbox && !seCroisent(pays.bbox, vue))) continue;
      for (const ring of pays.rings) {
        if (!seCroisent(boiteDe(ring), vue)) continue;
        // Coupé à 12 pt hors de la carte : le bord de coupe, droit, reste
        // invisible, et le lissage n'y fait pas de vague dans le cadre.
        const pts = simplifier(
          couper(
            ring.map(([lon, lat]) => project(frame, lon, lat)),
            [-12, -12, widthPt + 12, heightPt + 12],
          ),
          0.45,
        );
        // Un îlot de moins de deux points de large ne se lit pas : un trait
        // pointillé y ferait une tache.
        const [o, s, e, n] = boiteDe(pts);
        if (pts.length < 3 || (e - o < 2 && n - s < 2)) continue;
        paths +=
          `<path d="${smoothPath(pts)}" fill="${FILL}" stroke="${OUTLINE}" ` +
          `stroke-width="1.1" stroke-linejoin="round" stroke-linecap="round" ` +
          `stroke-dasharray="3.2 2.6"/>`;
      }
    }

    const trajet = points.some((p) => p.secondaire)
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
        return (
          `<path d="M${x} ${y} c-3.4 -4.6 -5.2 -6.8 -5.2 -9.4 a5.2 5.2 0 1 1 10.4 0 ` +
          `c0 2.6 -1.8 4.8 -5.2 9.4Z" fill="${PIN}"/>` +
          `<circle cx="${x}" cy="${y - 9.4}" r="1.9" fill="#fff"/>` +
          `<text x="${x}" y="${y + 9}" text-anchor="middle" fill="${PIN}" ` +
          `font-family="Playfair Display, serif" font-weight="900" font-size="7.5">` +
          `${escapeXml(point.label)}</text>`
        );
      })
      .join("");

    // Les côtes coupées par le cadre s'effacent en fondu sur les bords : un
    // trait tranché net au bord de la carte se lit comme une erreur.
    const fondu = (id, x2, y2) =>
      `<linearGradient id="${id}" x1="0" y1="0" x2="${x2}" y2="${y2}">` +
      `<stop offset="0" stop-color="#000"/><stop offset="0.09" stop-color="#fff"/>` +
      `<stop offset="0.91" stop-color="#fff"/><stop offset="1" stop-color="#000"/></linearGradient>`;
    const defs =
      `<defs>${fondu("fh", 1, 0)}${fondu("fv", 0, 1)}` +
      `<mask id="mh"><rect width="${widthPt}" height="${heightPt}" fill="url(#fh)"/></mask>` +
      `<mask id="mv"><rect width="${widthPt}" height="${heightPt}" fill="url(#fv)"/></mask></defs>`;

    return (
      `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${widthPt} ${heightPt}" ` +
      `width="${widthPt}" height="${heightPt}">${defs}` +
      `<g mask="url(#mh)"><g mask="url(#mv)">${paths}</g></g>${trajet}${pins}</svg>`
    );
  }

  const enDataUri = (svg) => {
    const octets = new TextEncoder().encode(svg);
    let binaire = "";
    for (const octet of octets) binaire += String.fromCharCode(octet);
    return `data:image/svg+xml;base64,${btoa(binaire)}`;
  };

  /** Le SVG en data URI, tel qu'il part dans `map_svg`. */
  function renderMapDataUri(contours, request) {
    return enDataUri(renderMapSvg(contours, request));
  }

  function renderCarteCadreeDataUri(detail, request) {
    return enDataUri(renderCarteCadree(detail, request));
  }

  const api = { renderMapSvg, renderMapDataUri, renderCarteCadree, renderCarteCadreeDataUri };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else racine.Carte = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
