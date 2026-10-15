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
  /** Un halo couleur papier sous les noms : le trajet pointillé passe dessous sans les barrer. */
  const HALO = 'stroke="#fbf8f4" stroke-width="2.2" stroke-opacity="0.9" stroke-linejoin="round" paint-order="stroke"';
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

  /**
   * Les segments du trajet, chacun dessiné selon le moyen de transport qui
   * mène à son point d'arrivée (`mode`) :
   *
   * - avion : une courbe en pointillés, l'arc d'un vol, bombé vers le haut ;
   * - bateau : une ligne droite en pointillés ;
   * - terre : une ligne droite pleine ;
   * - inconnu : une ligne droite en pointillés, comme avant que les trajets
   *   soient connus. `defaut` le remplace (une carte de ville se parcourt à
   *   pied ou en métro : terre).
   *
   * `points` : `[{ x, y, mode }]`, déjà projetés. Renvoie `[{ mode, a, b, c }]`
   * — `c`, le point de contrôle de la courbe d'un vol.
   */
  function segmentsDuTrajet(points, defaut = null) {
    const r = (v) => Math.round(v * 10) / 10;
    const segments = [];
    for (let i = 1; i < points.length; i += 1) {
      const a = [points[i - 1].x, points[i - 1].y];
      const b = [points[i].x, points[i].y];
      const mode = points[i].mode || defaut;
      const l = Math.hypot(b[0] - a[0], b[1] - a[1]);
      if (l < 0.5) continue;
      let c = null;
      if (mode === "avion") {
        let nx = -(b[1] - a[1]) / l;
        let ny = (b[0] - a[0]) / l;
        if (ny > 0 || (ny === 0 && nx > 0)) {
          nx = -nx;
          ny = -ny;
        }
        c = [r((a[0] + b[0]) / 2 + nx * l * 0.22), r((a[1] + b[1]) / 2 + ny * l * 0.22)];
      }
      segments.push({ mode, a, b, c });
    }
    return segments;
  }

  /** Le trajet en SVG : un `<path>` par segment, au style de son moyen de transport. */
  function trajetSvg(segments, couleur, epaisseur = 0.9) {
    return segments
      .map(({ mode, a, b, c }) => {
        const d = c ? `M${a[0]} ${a[1]}Q${c[0]} ${c[1]} ${b[0]} ${b[1]}` : `M${a[0]} ${a[1]}L${b[0]} ${b[1]}`;
        const pointilles = mode === "terre" ? "" : ` stroke-dasharray="${mode === "avion" ? "1.4 1.8" : "2 2"}"`;
        return `<path d="${d}" fill="none" stroke="${couleur}" stroke-width="${epaisseur}"${pointilles} stroke-linecap="round"/>`;
      })
      .join("");
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

  /* ------------------------------------- rues et cours d'eau (OpenStreetMap) */

  /*
   * À l'échelle d'une ville, Natural Earth ne suffit plus : son tracé de la
   * Seine passait du mauvais côté de la tour Eiffel. Les cartes de ville — et
   * elles seules — prennent leurs grands axes et leurs cours d'eau dans
   * OpenStreetMap, demandés à Overpass avant la mise en page (`app.js`,
   * `chargerRuesDesVilles`). La licence ODbL oblige à créditer les
   * contributeurs : toute carte qui en dessine une donnée porte `MENTION_OSM`.
   * Recopie de `mapSvg.ts`.
   */
  const MENTION_OSM = "© les contributeurs d’OpenStreetMap";
  const RANGS_ROUTE = { motorway: 0, trunk: 0, primary: 1, secondary: 2, tertiary: 3 };
  /** Épaisseur et opacité des routes, par rang : sous le trajet (0,9 pt, orange), jamais par-dessus. */
  const STYLE_ROUTE = [
    [1.1, 0.45],
    [0.9, 0.38],
    [0.6, 0.3],
    [0.45, 0.25],
  ];
  /** La couleur du papier : l'eau d'une ville s'y découpe comme la mer sur les autres cartes. */
  const PAPIER = "#fbf8f4";

  /**
   * Ce qu'une carte de ville montre, arrondi au centième de degré vers
   * l'extérieur (~1 km) : la zone demandée à Overpass, et la clé de son cache.
   */
  function vueDeVille(cadre, widthPt = 200, heightPt = 260) {
    const { minX, maxX, minY, maxY } = cadrer(cadre, widthPt, heightPt, 10).frame;
    const lat = (y) => ((2 * Math.atan(Math.exp(y)) - Math.PI / 2) * 180) / Math.PI;
    const bas = (v) => Math.floor(v * 100) / 100;
    const haut = (v) => Math.ceil(v * 100) / 100;
    return [bas((minX * 180) / Math.PI), bas(lat(minY)), haut((maxX * 180) / Math.PI), haut(lat(maxY))];
  }

  /** La clé d'une vue : `<sud>_<ouest>_<nord>_<est>`. */
  const cleDeVue = (vue) => [vue[1], vue[0], vue[3], vue[2]].map((v) => v.toFixed(2)).join("_");

  /**
   * La requête Overpass d'une vue : les grands axes, les fleuves et canaux,
   * les plans d'eau. Plus la vue est grande, moins on descend dans les rangs.
   */
  function requeteOverpass(vue) {
    const [o, s, e, n] = vue;
    const etendue = Math.max(e - o, n - s);
    const types = ["motorway", "trunk", "primary"];
    if (etendue <= 0.15) types.push("secondary");
    if (etendue <= 0.06) types.push("tertiary");
    const bbox = [s, o, n, e].map((v) => v.toFixed(2)).join(",");
    return (
      `[out:json][timeout:50][bbox:${bbox}];` +
      `(way["highway"~"^(${types.join("|")})$"];way["waterway"~"^(river|canal)$"];way["natural"="water"];);` +
      `out geom qt;`
    );
  }

  /** Les morceaux d'une ligne qui passent dans `b`, avec un point de part et d'autre. */
  function rogner(trace, b) {
    const dedans = (p) => Boolean(p) && p[0] >= b[0] && p[0] <= b[2] && p[1] >= b[1] && p[1] <= b[3];
    const morceaux = [];
    let morceau = [];
    for (let i = 0; i < trace.length; i += 1) {
      if (dedans(trace[i]) || dedans(trace[i - 1]) || dedans(trace[i + 1])) morceau.push(trace[i]);
      else {
        if (morceau.length > 1) morceaux.push(morceau);
        morceau = [];
      }
    }
    if (morceau.length > 1) morceaux.push(morceau);
    return morceaux;
  }

  /** La réponse d'Overpass (`out geom`), réduite à ce que la carte dessine. */
  function ruesDOverpass(reponse, vue) {
    const elements = reponse?.elements;
    const rues = { routes: [], coursDEau: [], plansDEau: [] };
    if (!Array.isArray(elements)) return rues;
    // Un dixième de marge : un axe qui sort du cadre passe encore sous le fondu.
    const mx = (vue[2] - vue[0]) * 0.1;
    const my = (vue[3] - vue[1]) * 0.1;
    const boite = [vue[0] - mx, vue[1] - my, vue[2] + mx, vue[3] + my];
    const r5 = (v) => Math.round(v * 1e5) / 1e5;
    for (const element of elements) {
      if (element?.type !== "way" || !Array.isArray(element.geometry)) continue;
      const tags = element.tags ?? {};
      const trace = element.geometry
        .filter((p) => Number.isFinite(p?.lat) && Number.isFinite(p?.lon))
        .map((p) => [r5(p.lon), r5(p.lat)]);
      if (trace.length < 2) continue;
      const rang = RANGS_ROUTE[tags["highway"] ?? ""];
      if (rang !== undefined) {
        for (const t of rogner(trace, boite)) rues.routes.push({ rang, trace: t });
      } else if (tags["waterway"] === "river" || tags["waterway"] === "canal") {
        for (const t of rogner(trace, boite)) rues.coursDEau.push({ canal: tags["waterway"] === "canal", trace: t });
      } else if (tags["natural"] === "water") {
        const [a, z] = [trace[0], trace[trace.length - 1]];
        // Seuls les contours fermés : un bout de rive ne se remplit pas.
        if (trace.length >= 4 && a[0] === z[0] && a[1] === z[1] && seCroisent(boiteDe(trace), boite)) {
          rues.plansDEau.push(trace);
        }
      }
    }
    return rues;
  }

  const rueVide = (rues) => !rues || (!rues.routes.length && !rues.coursDEau.length && !rues.plansDEau.length);

  /**
   * Les rues et l'eau en SVG, sous le trajet : les plans d'eau, les fleuves
   * (un ruban couleur papier entre deux rives vertes), puis les routes, des
   * plus petites aux plus grandes, un trait par rang.
   */
  function ruesSvg(rues, frame, ptParKm) {
    const r = (v) => Math.round(v * 10) / 10;
    const projeter = (trace) =>
      simplifier(
        trace.map(([lon, lat]) => project(frame, lon, lat)),
        0.3,
      );
    const chemin = (pts) => pts.map(([x, y], i) => `${i ? "L" : "M"}${x} ${y}`).join("");
    const borne = (v, min, max) => r(Math.min(max, Math.max(min, v)));
    let svg = "";

    const plans = rues.plansDEau.map(projeter).filter((pts) => {
      const [o, s, e, n] = boiteDe(pts);
      // Moins de 4 pt : une fontaine, un bassin — une tache, pas un repère.
      return pts.length >= 4 && (e - o >= 4 || n - s >= 4);
    });
    if (plans.length) {
      svg +=
        `<path d="${plans.map((p) => `${chemin(p)}Z`).join("")}" fill="${PAPIER}" stroke="${OUTLINE}" ` +
        `stroke-width="0.5" stroke-opacity="0.6" stroke-linejoin="round"/>`;
    }
    for (const canal of [false, true]) {
      const traces = rues.coursDEau.filter((c) => c.canal === canal).map((c) => projeter(c.trace));
      const d = traces.filter((p) => p.length > 1).map(chemin).join("");
      if (!d) continue;
      const largeur = canal ? borne(0.03 * ptParKm, 0.8, 2.5) : borne(0.12 * ptParKm, 1.6, 7);
      const trait = `fill="none" stroke-linecap="round" stroke-linejoin="round"`;
      svg +=
        `<path d="${d}" ${trait} stroke="${OUTLINE}" stroke-opacity="0.55" stroke-width="${r(largeur + 1)}"/>` +
        `<path d="${d}" ${trait} stroke="${PAPIER}" stroke-width="${largeur}"/>`;
    }
    for (let rang = STYLE_ROUTE.length - 1; rang >= 0; rang -= 1) {
      const d = rues.routes
        .filter((route) => route.rang === rang)
        .map((route) => projeter(route.trace))
        .filter((p) => p.length > 1)
        .map(chemin)
        .join("");
      if (!d) continue;
      const [epaisseur, opacite] = STYLE_ROUTE[rang];
      svg +=
        `<path d="${d}" fill="none" stroke="${OUTLINE}" stroke-width="${epaisseur}" stroke-opacity="${opacite}" ` +
        `stroke-linecap="round" stroke-linejoin="round"/>`;
    }
    return svg;
  }

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
   *
   * Pour une carte de ville : `trajet` relie les points dans l'ordre — les
   * déplacements du séjour — même sans point secondaire, et `echelle` pose une
   * barre d'échelle (« 1 km ») qui dit les distances parcourues, et
   * `request.rues` (`ruesDOverpass`) y ajoute les grands axes et les cours
   * d'eau d'OpenStreetMap — Natural Earth, à cette échelle, mettait la tour
   * Eiffel sur la mauvaise rive de la Seine. Sans elles, la carte reste sobre.
   */
  function renderCarteCadree(detail, request) {
    const { cadre, points = [], widthPt = 200, heightPt = 260, ville = false, titre = "", rues = null } = request;
    const padding = 10;
    // Le cadre en Mercator, élargi au format de la carte, centré.
    const { frame } = cadrer(cadre, widthPt, heightPt, padding);
    const { minX, maxX, minY, maxY, scale } = frame;
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

    // Un degré de longitude vaut R·cos(φ) : l'échelle se lit au centre du cadre.
    const latCentre = (((cadre[1] + cadre[3]) / 2) * Math.PI) / 180;
    const ptParKm = scale / (6371.0088 * Math.cos(latCentre));
    const osm = ville && !rueVide(rues) ? ruesSvg(rues, frame, ptParKm) : "";

    const trajet =
      ville || points.some((p) => p.secondaire || p.mode)
        ? trajetSvg(
            segmentsDuTrajet(
              points.map((p) => {
                const [x, y] = project(frame, p.lon, p.lat);
                return { x, y, mode: p.mode };
              }),
              ville ? "terre" : null,
            ),
            PIN,
          )
        : "";
    // Sur une carte de ville, les lieux déjà passés gardent leur nom, en
    // petit : à droite du point, à gauche s'il y chevauche un autre nom, sinon
    // tu.
    const r = (v) => Math.round(v * 10) / 10;
    const occupes = points
      .filter((p) => !p.secondaire)
      .map((p) => {
        const [x, y] = project(frame, p.lon, p.lat);
        const l = String(p.label).length * 4.1;
        return [x - l / 2, y - 15, x + l / 2, y + 11];
      });
    if (titre) occupes.push([padding, padding, padding + 4 + String(titre).length * 7.5, padding + 12]);
    const libre = (b) => !occupes.some((o) => b[0] < o[2] && o[0] < b[2] && b[1] < o[3] && o[1] < b[3]);
    const pins = points
      .map((point) => {
        const [x, y] = project(frame, point.lon, point.lat);
        if (point.secondaire) {
          const rond = `<circle cx="${x}" cy="${y}" r="2.2" fill="#fff" stroke="${PIN}" stroke-width="1.1"/>`;
          if (!ville) return rond;
          const l = String(point.label).length * 2.9;
          const droite = [x + 4, y - 4, x + 4 + l, y + 3];
          const gauche = [x - 4 - l, y - 4, x - 4, y + 3];
          const place = libre(droite) ? ["start", droite[0], droite] : libre(gauche) ? ["end", gauche[2], gauche] : null;
          if (!place) return rond;
          occupes.push(place[2]);
          return (
            rond +
            `<text x="${r(place[1])}" y="${r(y + 2)}" text-anchor="${place[0]}" fill="${OUTLINE}" ` +
            `font-family="Playfair Display, serif" font-size="5.5" ${HALO}>${escapeXml(point.label)}</text>`
          );
        }
        return (
          `<path d="M${x} ${y} c-3.4 -4.6 -5.2 -6.8 -5.2 -9.4 a5.2 5.2 0 1 1 10.4 0 ` +
          `c0 2.6 -1.8 4.8 -5.2 9.4Z" fill="${PIN}"/>` +
          `<circle cx="${x}" cy="${y - 9.4}" r="1.9" fill="#fff"/>` +
          `<text x="${x}" y="${y + 9}" text-anchor="middle" fill="${PIN}" ` +
          `font-family="Playfair Display, serif" font-weight="900" font-size="7.5" ${HALO}>` +
          `${escapeXml(point.label)}</text>`
        );
      })
      .join("");
    // Le nom de la ville, en tête : c'est lui qui dit où l'on est.
    const enTete = titre
      ? `<text x="${padding + 2}" y="${padding + 9}" fill="${OUTLINE}" font-family="Playfair Display, serif" ` +
        `font-weight="900" font-size="9" letter-spacing="1.6">${escapeXml(String(titre).toUpperCase())}</text>`
      : "";

    // Barre d'échelle, en bas à gauche : la plus longue longueur ronde qui
    // tienne dans 60 pt.
    let echelle = "";
    if (ville) {
      const km = [100, 50, 20, 10, 5, 2, 1, 0.5, 0.25, 0.2, 0.1].find((k) => k * ptParKm <= 60) ?? 0.1;
      const l = Math.round(km * ptParKm * 10) / 10;
      const x0 = padding + 2;
      const y0 = heightPt - padding - 4;
      const texte = km < 1 ? `${Math.round(km * 1000)} m` : `${km} km`;
      echelle =
        `<path d="M${x0} ${y0 - 3}v3h${l}v-3" fill="none" stroke="${OUTLINE}" stroke-width="0.9" stroke-linejoin="round"/>` +
        `<text x="${x0 + l / 2}" y="${y0 - 5}" text-anchor="middle" fill="${OUTLINE}" ` +
        `font-family="Playfair Display, serif" font-size="6.5">${texte}</text>`;
    }
    // La mention qu'exige la licence ODbL, en bas à droite, face à l'échelle.
    const mention = osm
      ? `<text x="${widthPt - padding - 2}" y="${heightPt - padding - 1}" text-anchor="end" fill="${OUTLINE}" ` +
        `fill-opacity="0.8" font-family="Playfair Display, serif" font-size="4.2">${escapeXml(MENTION_OSM)}</text>`
      : "";

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
      `<g mask="url(#mh)"><g mask="url(#mv)">${paths}${osm}</g></g>${enTete}${echelle}${mention}${trajet}${pins}</svg>`
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

  /**
   * Le cadre élargi au format `largeur × hauteur` (n'importe quelle unité),
   * centré : le même calcul que `renderCarteCadree`, pour les cartes dessinées
   * ailleurs (la quatrième de couverture, `couverture.js`).
   */
  function cadrer(cadre, largeur, hauteur, padding = 0) {
    let minX = mercatorX(cadre[0]);
    let maxX = mercatorX(cadre[2]);
    let minY = mercatorY(cadre[1]);
    let maxY = mercatorY(cadre[3]);
    const largeurUtile = largeur - padding * 2;
    const hauteurUtile = hauteur - padding * 2;
    const scale = Math.min(largeurUtile / (maxX - minX || 1e-6), hauteurUtile / (maxY - minY || 1e-6));
    const manqueX = (largeurUtile / scale - (maxX - minX)) / 2;
    const manqueY = (hauteurUtile / scale - (maxY - minY)) / 2;
    minX -= manqueX;
    maxX += manqueX;
    minY -= manqueY;
    maxY += manqueY;
    const frame = { minX, maxX, minY, maxY, scale, width: largeur, height: hauteur, padding };
    const vue = [
      (minX * 180) / Math.PI - 0.5,
      ((2 * Math.atan(Math.exp(minY)) - Math.PI / 2) * 180) / Math.PI - 0.5,
      (maxX * 180) / Math.PI + 0.5,
      ((2 * Math.atan(Math.exp(maxY)) - Math.PI / 2) * 180) / Math.PI + 0.5,
    ];
    // Sans l'arrondi au dixième de `project` : la quatrième se dessine en
    // millimètres, où un dixième se verrait.
    const projeter = (lon, lat) => [
      padding + (mercatorX(lon) - minX) * scale,
      padding + (maxY - mercatorY(lat)) * scale,
    ];
    return { frame, vue, projeter };
  }

  const outils = { cadrer, simplifier, boiteDe, seCroisent, segmentsDuTrajet };

  const api = {
    renderMapSvg,
    renderMapDataUri,
    renderCarteCadree,
    renderCarteCadreeDataUri,
    vueDeVille,
    cleDeVue,
    requeteOverpass,
    ruesDOverpass,
    MENTION_OSM,
    outils,
  };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else racine.Carte = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
