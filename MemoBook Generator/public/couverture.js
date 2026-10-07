/*
 * Couverture imprimée — le plat recto, le dos et le plat verso d'un livre
 * relié Pumbo, d'un seul tenant, au format exact de la commande.
 *
 * Pourquoi un fichier à part : la couverture d'un relié n'est pas une page du
 * carnet. Sa largeur dépend du nombre de pages (le dos), elle a son propre
 * fond perdu, et Pumbo l'imprime sur un autre papier que l'intérieur. Elle ne
 * passe donc pas par APITemplate, dont le format de papier est fixé une fois
 * pour toutes dans le tableau de bord : elle est composée ici, dans le
 * navigateur, et enregistrée en PDF par la boîte d'impression de Chrome, qui
 * respecte la taille `@page` au dixième de millimètre.
 *
 * Les dimensions viennent de la **fiche technique Pumbo** — le script
 * InDesign (`.jsx`) que produit leur outil de couverture pour une commande
 * donnée. Elles ne se devinent pas : la largeur du dos dépend du nombre de
 * pages et du papier, et Pumbo ne publie pas de barème. Sans fiche, on part de
 * celle d'un relié 154 × 216 mm de 48 pages (dos de 8 mm), en le disant.
 *
 * Règles et schéma : `templates/travel-journal/LAYOUT_KB.md`, § « Couverture
 * imprimée (Pumbo) ».
 */
(function (racine) {
  "use strict";

  /**
   * La fiche d'un relié 154 × 216 mm de 48 pages, reçue de Pumbo le 07/10/2026.
   * Plats de 178 × 260 mm : le carton dépasse du bloc et le papier se rabat
   * dessus, d'où des plats plus grands que la page.
   */
  const FICHE_DEFAUT = {
    source: "fiche Pumbo d'un relié 154 × 216 mm de 48 pages",
    largeurPlat: 178,
    hauteurPlat: 260,
    dos: 8,
    fondPerdu: 3,
    marge: 19,
    parDefaut: true,
  };

  /**
   * Distance minimale entre le texte et le dos, sur chaque plat. La fiche ne
   * met aucune marge côté dos, mais un relié a une charnière : la couverture
   * s'y plie, et un mot posé dessus se lit mal et s'use le premier.
   */
  const CHARNIERE = 12;

  /** Sous cette largeur de dos, pas de texte dessus : il ne tiendrait pas lisible. */
  const DOS_MIN_TEXTE = 6;

  /** Résolution visée, et celle sous laquelle on prévient le voyageur. */
  const DPI_CIBLE = 300;
  const DPI_MIN = 200;

  /**
   * Lit la fiche `.jsx` de Pumbo. Le script InDesign donne, dans cet ordre :
   * le fond perdu (`documentBleedTopOffset`), les trois pages — verso, dos,
   * recto — avec leur largeur et leur hauteur, puis les marges des plats.
   * Renvoie `null` si le fichier n'a pas cette forme.
   */
  function lireFichePumbo(texte) {
    const source = String(texte || "");
    const pages = {};
    for (const m of source.matchAll(
      /pages\.item\((\d)\)\.adjustLayout\(\{\s*width\s*:\s*"([\d.,]+)mm"\s*,\s*height\s*:\s*"([\d.,]+)mm"/g,
    )) {
      pages[m[1]] = { largeur: nombre(m[2]), hauteur: nombre(m[3]) };
    }
    const fond = source.match(/documentBleed\w*Offset\s*:\s*"([\d.,]+)mm"/);
    // Les marges du recto (page 2) : haut, bas et bord extérieur. On garde la
    // plus grande, c'est la zone sûre la plus prudente.
    const marges = source.match(
      /pages\.item\(2\)\.marginPreferences\.properties\s*=\s*\{([^}]*)\}/,
    );
    const valeursMarges = marges
      ? [...marges[1].matchAll(/"([\d.,]+)mm"/g)].map((m) => nombre(m[1])).filter((v) => v > 0)
      : [];

    const verso = pages["0"];
    const dos = pages["1"];
    const recto = pages["2"];
    if (!verso || !dos || !recto) return null;
    return {
      source: "fiche Pumbo importée",
      largeurPlat: recto.largeur,
      hauteurPlat: recto.hauteur,
      dos: dos.largeur,
      fondPerdu: fond ? nombre(fond[1]) : FICHE_DEFAUT.fondPerdu,
      marge: valeursMarges.length ? Math.max(...valeursMarges) : FICHE_DEFAUT.marge,
      parDefaut: false,
    };
  }

  function nombre(texte) {
    return Number(String(texte).replace(",", "."));
  }

  /** Toutes les cotes de la feuille, en millimètres, origine en haut à gauche du fond perdu. */
  function geometrie(fiche) {
    const f = fiche.fondPerdu;
    const largeur = 2 * f + 2 * fiche.largeurPlat + fiche.dos;
    const hauteur = 2 * f + fiche.hauteurPlat;
    const debutDos = f + fiche.largeurPlat;
    const debutRecto = debutDos + fiche.dos;
    return {
      largeur,
      hauteur,
      verso: { x: 0, largeur: debutDos },
      dos: { x: debutDos, largeur: fiche.dos },
      recto: { x: debutRecto, largeur: largeur - debutRecto },
      // Format du recto fond perdu compris : c'est lui que la photo doit remplir.
      formatRecto: (largeur - debutRecto) / hauteur,
    };
  }

  /** Part de l'image perdue quand une photo de format `photo` remplit un cadre de format `cadre`. */
  function rognage(photo, cadre) {
    if (!photo || !cadre) return 0;
    return 1 - Math.min(cadre / photo, photo / cadre);
  }

  /** Résolution effective d'une photo étirée sur tout le recto (fond perdu compris). */
  function dpiSurRecto(photo, fiche) {
    if (!photo?.largeur || !photo?.hauteur) return 0;
    const g = geometrie(fiche);
    return Math.round(
      Math.min(photo.largeur / (g.recto.largeur / 25.4), photo.hauteur / (g.hauteur / 25.4)),
    );
  }

  /**
   * La photo de couverture. Celle que le voyageur a désignée, sinon la plus
   * adaptée au recto, qui est un portrait (format 0,68) :
   *
   * 1. jamais une photo de groupe — elle serait rognée, et une photo de groupe
   *    ne se rogne pas ;
   * 2. d'abord celles qui tiennent sous le plafond de rognage d'un tiers —
   *    une portrait, en pratique : une paysage 4:3 y perdrait la moitié ;
   * 3. puis celle qui atteint 300 dpi, puis la mieux résolue ;
   * 4. à égalité, la première du voyage.
   */
  function choisirPhotoCouverture(photos, fiche) {
    const avecImage = photos.filter((p) => p.data);
    const designee = avecImage.find((p) => p.couverture);
    if (designee) return designee;
    const format = geometrie(fiche).formatRecto;
    const candidates = avecImage.filter((p) => !p.groupe);
    const notees = (candidates.length ? candidates : avecImage).map((p, rang) => {
      const fmt = p.largeur && p.hauteur ? p.largeur / p.hauteur : 0;
      const dpi = dpiSurRecto(p, fiche);
      return {
        p,
        rang,
        lisible: fmt ? rognage(fmt, format) <= 1 / 3 : false,
        nette: dpi >= DPI_CIBLE,
        dpi,
      };
    });
    notees.sort(
      (a, b) =>
        Number(b.lisible) - Number(a.lisible) ||
        Number(b.nette) - Number(a.nette) ||
        b.dpi - a.dpi ||
        a.rang - b.rang,
    );
    return notees[0]?.p || null;
  }

  /** Ce qu'il faut dire au voyageur avant qu'il envoie le fichier. */
  function avertissements({ fiche, photo }) {
    const liste = [];
    if (fiche.parDefaut) {
      liste.push(
        `Dimensions de la ${fiche.source} (dos de ${fiche.dos} mm). Le dos dépend du nombre de pages : ` +
          "importe la fiche Pumbo de cette commande dans les réglages avant d'envoyer le fichier.",
      );
    }
    if (!photo) {
      liste.push("Aucune photo : le recto sera un aplat.");
      return liste;
    }
    const dpi = dpiSurRecto(photo, fiche);
    if (dpi && dpi < DPI_MIN) {
      liste.push(
        `La photo ne fait que ${dpi} dpi sur le recto (${DPI_CIBLE} visés) : elle sera floue à l'impression.`,
      );
    }
    const fmt = photo.largeur && photo.hauteur ? photo.largeur / photo.hauteur : 0;
    const perte = rognage(fmt, geometrie(fiche).formatRecto);
    if (photo.groupe && perte > 0.02) {
      liste.push(
        `C'est une photo de groupe, et le recto en rogne ${Math.round(perte * 100)} % : ` +
          "quelqu'un risque de sortir du cadre. Choisis-en une autre si c'est le cas.",
      );
    } else if (perte > 1 / 3) {
      liste.push(
        `Le recto rogne ${Math.round(perte * 100)} % de cette photo, au-delà du plafond d'un tiers : ` +
          "une photo en hauteur conviendrait mieux.",
      );
    }
    return liste;
  }

  const echapper = (t) =>
    String(t || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");

  /**
   * La page HTML de la couverture, prête à imprimer en PDF.
   *
   * Un seul style, celui de la couverture intérieure du carnet (« photo ») :
   * la photo en pleine page sur le recto, le titre en Playfair Display posé
   * dessus, le sous-titre sur un bandeau blanc incliné, les voyageurs et les
   * dates en bas. Le verso reprend la quatrième intérieure — « À suivre. » sur
   * le papier — et le dos porte le titre et les voyageurs, lisibles de bas en
   * haut, à la française.
   */
  function construireHtmlCouverture({ fiche, titre, sousTitre, auteurs, dates, photo, polices, logo, quatrieme, adresse }) {
    const g = geometrie(fiche);
    const f = fiche.fondPerdu;
    const m = fiche.marge;
    const mm = (v) => `${Math.round(v * 100) / 100}mm`;
    const texteDos = fiche.dos >= DOS_MIN_TEXTE;
    // Corps du texte du dos : 45 % de sa largeur, plafonné à 11 pt.
    const corpsDos = Math.min(11, (fiche.dos * 0.45 * 72) / 25.4);
    const focus = photo?.focus || "50% 35%";
    const alertes = avertissements({ fiche, photo });
    // `fonts.css` arrive enveloppé dans ses propres balises `<style>` (c'est la
    // forme qu'attend APITemplate) : posé tel quel dans la nôtre, il la
    // fermerait, et tout le CSS de la couverture partirait en texte.
    const css = String(polices || "").replace(/<\/?style[^>]*>/gi, "");

    return `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8" />
<title>Couverture — ${echapper(titre)}</title>
<style>
${css}
@page { size: ${mm(g.largeur)} ${mm(g.hauteur)}; margin: 0; }
:root {
  --encre: #2b231b;
  --papier: #f5ede6;
  --carotte: #f86015;
  --titre: "Playfair Display", "Times New Roman", serif;
}
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; }
body {
  background: #6b6259;
  -webkit-print-color-adjust: exact;
  print-color-adjust: exact;
  font-family: var(--titre);
}
.feuille {
  position: relative;
  width: ${mm(g.largeur)};
  height: ${mm(g.hauteur)};
  overflow: hidden;
  background: var(--papier);
}
.zone { position: absolute; top: 0; height: 100%; }
.verso { left: 0; width: ${mm(g.verso.largeur)}; background: var(--papier); }
.dos { left: ${mm(g.dos.x)}; width: ${mm(g.dos.largeur)}; background: var(--encre); }
.recto { left: ${mm(g.recto.x)}; width: ${mm(g.recto.largeur)}; background: var(--encre); }

.recto img.photo {
  position: absolute; inset: 0; width: 100%; height: 100%;
  object-fit: cover; object-position: ${echapper(focus)};
}
/* Un voile en haut seulement : le titre blanc reste lisible sur un ciel clair. */
.recto .voile {
  position: absolute; left: 0; right: 0; top: 0; height: 45%;
  background: linear-gradient(rgba(0,0,0,0.38), rgba(0,0,0,0));
}
.recto .tete {
  position: absolute;
  top: ${mm(f + m)};
  left: ${mm(CHARNIERE)};
  right: ${mm(f + m)};
  display: flex; flex-direction: column; align-items: center; gap: 5mm;
  text-align: center;
}
.recto h1 {
  margin: 0;
  font-weight: 900;
  font-size: ${titre && titre.length > 34 ? "17mm" : "21mm"};
  line-height: 1.02;
  letter-spacing: 0.01em;
  color: #fff;
  text-shadow: 0 0.45mm 0 rgba(0,0,0,0.42);
}
.recto .sous-titre {
  padding: 2.2mm 3.6mm;
  background: rgba(255,255,255,0.96);
  font-size: 4.6mm; line-height: 1.3;
  color: var(--encre);
  transform: rotate(-2deg);
}
.recto .signature {
  position: absolute;
  bottom: ${mm(f + m)};
  left: ${mm(CHARNIERE)};
  right: ${mm(f + m)};
  text-align: center;
  font-size: 7mm; line-height: 1.3; letter-spacing: 0.01em;
  color: #fff;
  text-shadow: 0 0.35mm 0 rgba(0,0,0,0.45);
}
.recto .signature p { margin: 0; }

.dos .texte {
  position: absolute; inset: ${mm(f + m)} 0;
  display: flex; align-items: center; justify-content: center;
  writing-mode: vertical-rl;
  transform: rotate(180deg); /* de bas en haut, à la française */
  white-space: nowrap;
  font-size: ${corpsDos.toFixed(1)}pt;
  color: #fff;
  letter-spacing: 0.04em;
}
.dos .texte .sep { margin: 2.5mm 0; color: var(--carotte); }

.verso .fin {
  position: absolute;
  top: 38%;
  left: ${mm(f + m)};
  right: ${mm(CHARNIERE)};
  text-align: center;
  font-size: 13mm; font-style: italic;
  color: var(--encre);
}
.verso .fin::after {
  content: ""; display: block; width: 16mm; height: 0.5mm;
  margin: 6mm auto 0; background: var(--carotte);
}
.verso .pied {
  position: absolute;
  bottom: ${mm(f + m)};
  left: ${mm(f + m)};
  right: ${mm(CHARNIERE)};
  display: flex; flex-direction: column; align-items: center; gap: 2.5mm;
  font-size: 3.6mm; color: var(--encre);
}
.verso .pied img { height: 9mm; }

/* À l'écran seulement : repères de coupe, de pli et de zone sûre. */
.repere { position: absolute; pointer-events: none; }
.coupe { border: 0.3mm dashed #e2342d; }
.pli { top: 0; bottom: 0; border-left: 0.3mm dashed #1f7a4d; }
.sure { border: 0.3mm dotted #1f5fd6; }
.barre {
  position: sticky; top: 0; z-index: 10;
  padding: 10px 16px; background: #fff; color: #2b231b;
  font: 13px/1.45 system-ui, sans-serif;
  box-shadow: 0 1px 4px rgba(0,0,0,0.2);
}
.barre strong { font-weight: 600; }
.barre ul { margin: 6px 0 0; padding-left: 18px; }
.barre .alerte { color: #b3261e; }
.barre button { font: inherit; padding: 4px 10px; margin-right: 8px; cursor: pointer; }
.cadre-ecran { padding: 24px; }
body.sans-reperes .repere { display: none; }

@media print {
  body { background: none; }
  .barre, .repere { display: none !important; }
  .cadre-ecran { padding: 0; }
}
</style>
</head>
<body>
<div class="barre">
  <strong>Couverture Pumbo — ${mm(g.largeur)} × ${mm(g.hauteur)}</strong>
  (plats ${mm(fiche.largeurPlat)} × ${mm(fiche.hauteurPlat)}, dos ${mm(fiche.dos)}, fond perdu ${mm(f)} ; ${echapper(fiche.source)}).
  <ul>
    <li>Pour le fichier : <em>Imprimer</em> → Destination <em>Enregistrer au format PDF</em>, Marges <em>Aucune</em>, <em>Graphiques d'arrière-plan</em> coché. Le format de la feuille est imposé par la page.</li>
    <li>Repères (à l'écran seulement) : <span style="color:#e2342d">coupe</span>, <span style="color:#1f7a4d">plis du dos</span>, <span style="color:#1f5fd6">zone sûre</span> — rien d'important hors de la zone sûre.</li>
    ${alertes.map((a) => `<li class="alerte">${echapper(a)}</li>`).join("\n    ")}
  </ul>
  <div style="margin-top:6px">
    <button onclick="window.print()">Enregistrer en PDF…</button>
    <button onclick="document.body.classList.toggle('sans-reperes')">Masquer / montrer les repères</button>
  </div>
</div>
<div class="cadre-ecran">
<div class="feuille">
  <div class="zone verso">
    <div class="fin">${echapper(quatrieme || "À suivre.")}</div>
    <div class="pied">
      ${logo ? `<img src="${echapper(logo)}" alt="" />` : ""}
      <span>${echapper(adresse || "memobook.fr")}</span>
    </div>
  </div>
  <div class="zone dos">
    ${
      texteDos
        ? `<div class="texte"><span>${echapper(titre)}</span>${
            auteurs ? `<span class="sep">·</span><span>${echapper(auteurs)}</span>` : ""
          }</div>`
        : ""
    }
  </div>
  <div class="zone recto">
    ${photo?.data ? `<img class="photo" src="${photo.data}" alt="" />` : ""}
    <div class="voile"></div>
    <div class="tete">
      <h1>${echapper(titre)}</h1>
      ${sousTitre ? `<div class="sous-titre">${echapper(sousTitre)}</div>` : ""}
    </div>
    ${
      auteurs || dates
        ? `<div class="signature">${auteurs ? `<p>${echapper(auteurs)}</p>` : ""}${
            dates ? `<p>${echapper(dates)}</p>` : ""
          }</div>`
        : ""
    }
  </div>

  <div class="repere coupe" style="left:${mm(f)};top:${mm(f)};right:${mm(f)};bottom:${mm(f)}"></div>
  <div class="repere pli" style="left:${mm(g.dos.x)}"></div>
  <div class="repere pli" style="left:${mm(g.recto.x)}"></div>
  <div class="repere sure" style="left:${mm(f + m)};top:${mm(f + m)};width:${mm(g.verso.largeur - f - m - CHARNIERE)};bottom:${mm(f + m)}"></div>
  <div class="repere sure" style="left:${mm(g.recto.x + CHARNIERE)};top:${mm(f + m)};right:${mm(f + m)};bottom:${mm(f + m)}"></div>
</div>
</div>
</body>
</html>`;
  }

  const api = {
    FICHE_DEFAUT,
    lireFichePumbo,
    geometrie,
    choisirPhotoCouverture,
    dpiSurRecto,
    avertissements,
    construireHtmlCouverture,
  };

  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else racine.Couverture = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
