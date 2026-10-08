/*
 * Le voyage tel que les récits le racontent : l'itinéraire, les trajets et
 * leurs moyens de transport, et les chiffres qui en découlent — kilomètres
 * parcourus, pays et villes visités.
 *
 * Tout vient de l'analyse d'étape (`consigneAnalyseEtape`, `partage.js`) :
 *
 * - `lieu` et `lieux` : les endroits où le récit emmène le voyageur, avec leur
 *   `genre` (une ville ou un village, ou un site : une plage, un musée) ;
 * - `trajets` : les déplacements racontés, avec leur départ, leur arrivée et
 *   leur `mode` — avion, bateau ou terre.
 *
 * Ce fichier ne touche ni au DOM ni au réseau : `backend/test/voyageAtelier.test.ts`
 * le teste tel quel.
 */
(function (racine) {
  "use strict";

  const RAYON_TERRE_KM = 6371.0088;
  /**
   * Un trajet par la route ou le rail n'est pas une ligne droite : 1,3 fois le
   * vol d'oiseau, l'ordre de grandeur relevé sur les réseaux routiers
   * européens. L'avion et le bateau se comptent à vol d'oiseau.
   */
  const DETOUR_TERRE = 1.3;
  const MODES = ["avion", "bateau", "terre"];

  const normaliser = (t) =>
    String(t || "")
      .normalize("NFD")
      .replace(/[̀-ͯ]/g, "")
      .toLowerCase()
      .split(",")[0]
      .trim();

  /** Un lieu exploitable : un nom, un pays ISO, des coordonnées qui ne sont pas l'origine par défaut. */
  function lieuValide(lieu) {
    if (!lieu) return null;
    const lat = Number(lieu.lat);
    const lon = Number(lieu.lon);
    const pays = String(lieu.pays || "").toUpperCase();
    const nom = String(lieu.nom || "").trim();
    if (!nom || !/^[A-Z]{2}$/.test(pays) || !Number.isFinite(lat) || !Number.isFinite(lon)) return null;
    if (lat === 0 && lon === 0) return null;
    if (Math.abs(lat) > 90 || Math.abs(lon) > 180) return null;
    const genre = lieu.genre === "ville" || lieu.genre === "site" ? lieu.genre : null;
    return { nom, pays, lat, lon, genre };
  }

  /** Le moyen de transport, ramené aux trois façons de le dessiner. */
  function modeDe(valeur) {
    const v = normaliser(valeur);
    if (MODES.includes(v)) return v;
    if (/avion|vol|aerien/.test(v)) return "avion";
    if (/bateau|ferry|ferr|navette maritime|voilier|catamaran|croisiere/.test(v)) return "bateau";
    if (/train|bus|voiture|scooter|velo|pied|marche|taxi|metro|tram|moto|route|car\b|terre/.test(v)) return "terre";
    return null;
  }

  /** Distance orthodromique, en kilomètres. */
  function distanceKm(a, b) {
    const rad = Math.PI / 180;
    const dLat = (b.lat - a.lat) * rad;
    const dLon = (b.lon - a.lon) * rad;
    const h =
      Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLon / 2) ** 2;
    return 2 * RAYON_TERRE_KM * Math.asin(Math.min(1, Math.sqrt(h)));
  }

  /**
   * Le point de départ du voyage — la maison, l'aéroport de départ : le
   * départ du premier trajet raconté, s'il n'est pas lui-même un lieu de
   * l'étape. Il compte dans les kilomètres, pas parmi les lieux visités.
   */
  function domicile(etapes) {
    for (const etape of etapes) {
      const analyse = etape.analyse || {};
      const premier = (analyse.trajets || []).map((t) => lieuValide(t?.depart)).find(Boolean);
      if (!premier) continue;
      const cle = normaliser(premier.nom);
      const dansLEtape = [analyse.lieu, ...(analyse.lieux || [])].some((l) => normaliser(l?.nom) === cle);
      return dansLEtape ? null : cle;
    }
    return null;
  }

  /** Les trajets racontés, dans l'ordre des étapes puis du récit. */
  function trajetsDuVoyage(etapes) {
    const trajets = [];
    for (const etape of etapes) {
      for (const t of etape.analyse?.trajets || []) {
        const depart = lieuValide(t?.depart);
        const arrivee = lieuValide(t?.arrivee);
        if (!depart || !arrivee || normaliser(depart.nom) === normaliser(arrivee.nom)) continue;
        trajets.push({ depart, arrivee, mode: modeDe(t.mode) });
      }
    }
    return trajets;
  }

  /**
   * Les lieux visités, dans l'ordre de visite : pour chaque étape, les
   * arrivées de ses trajets, puis son lieu principal, puis les autres lieux de
   * son récit. Le point de départ du premier trajet (la maison, l'aéroport du
   * départ) n'est pas un lieu visité : il compte dans les kilomètres, pas sur
   * la carte.
   *
   * Chaque lieu porte `mode`, le moyen de transport qui y a mené quand le
   * récit le dit, et `revisite` quand le voyageur y revient.
   */
  function itineraire(etapes) {
    const ordre = [];
    const vus = new Set();
    const maison = domicile(etapes);
    for (const etape of etapes) {
      const analyse = etape.analyse || {};
      const arrivees = new Map();
      const candidats = [];
      for (const t of analyse.trajets || []) {
        const arrivee = lieuValide(t?.arrivee);
        const depart = lieuValide(t?.depart);
        if (!arrivee || (depart && normaliser(depart.nom) === normaliser(arrivee.nom))) continue;
        arrivees.set(normaliser(arrivee.nom), modeDe(t.mode));
        candidats.push(arrivee);
      }
      const principal = lieuValide(analyse.lieu);
      if (principal) candidats.push(principal);
      for (const l of analyse.lieux || []) {
        const v = lieuValide(l);
        if (v) candidats.push(v);
      }
      for (const lieu of candidats) {
        const cle = normaliser(lieu.nom);
        // La maison n'est pas un lieu visité : le retour y mène, la carte s'arrête avant.
        if (maison && cle === maison) continue;
        // Deux fois de suite le même lieu n'est pas un déplacement.
        if (ordre.length && normaliser(ordre[ordre.length - 1].nom) === cle) continue;
        // Le genre se garde d'une mention à l'autre : un lieu nommé deux fois
        // n'est pas toujours qualifié deux fois.
        const deja = ordre.find((l) => normaliser(l.nom) === cle);
        ordre.push({
          ...lieu,
          genre: lieu.genre || deja?.genre || null,
          mode: arrivees.has(cle) ? arrivees.get(cle) : null,
          revisite: vus.has(cle),
        });
        vus.add(cle);
      }
    }
    return ordre;
  }

  /**
   * Les lieux de séjour, dans l'ordre : le lieu principal de chaque étape — la
   * ville, ou l'île pour un voyage d'île en île —, sans les sites visités en
   * chemin (une plage, un musée, un village d'excursion), ni les escales de
   * transit, ni la maison. C'est ce que montre la carte de la quatrième de
   * couverture : « Paros, Naxos, Ios, Mykonos », pas chaque plage.
   *
   * Chaque lieu porte `mode`, le moyen de transport qui y a mené, cherché dans
   * les trajets de son étape puis de l'étape d'avant (on raconte souvent le
   * ferry du soir à la fin de la journée précédente).
   */
  function lieuxDeSejour(etapes) {
    const maison = domicile(etapes);
    const ordre = [];
    const arriveeA = (analyse, cle) => {
      const t = (analyse?.trajets || []).find((x) => normaliser(x?.arrivee?.nom) === cle);
      return t ? modeDe(t.mode) : undefined;
    };
    etapes.forEach((etape, i) => {
      const lieu = lieuValide(etape.analyse?.lieu);
      if (!lieu) return;
      const cle = normaliser(lieu.nom);
      if ((maison && cle === maison) || (ordre.length && normaliser(ordre[ordre.length - 1].nom) === cle)) return;
      const mode = arriveeA(etape.analyse, cle) ?? arriveeA(etapes[i - 1]?.analyse, cle) ?? null;
      ordre.push({ ...lieu, mode, revisite: ordre.some((l) => normaliser(l.nom) === cle) });
    });
    return ordre;
  }

  /**
   * Les chiffres du voyage tirés des récits :
   *
   * - `km` : la somme des trajets racontés — à vol d'oiseau pour l'avion et le
   *   bateau, 1,3 fois pour la terre —, arrondie au kilomètre ; `null` si le
   *   récit n'en raconte aucun ;
   * - `pays` et `villes` : les pays et les villes (ou villages) distincts où le
   *   récit emmène le voyageur. Une plage ou un musée est un lieu, pas une
   *   ville.
   */
  function chiffresDuVoyage(etapes) {
    const trajets = trajetsDuVoyage(etapes);
    const visites = itineraire(etapes);
    const km = trajets.length
      ? Math.round(
          trajets.reduce(
            (total, t) => total + distanceKm(t.depart, t.arrivee) * (t.mode === "terre" ? DETOUR_TERRE : 1),
            0,
          ),
        )
      : null;
    const pays = [...new Set(visites.map((l) => l.pays))];
    const villes = [
      ...new Map(visites.filter((l) => l.genre === "ville").map((l) => [normaliser(l.nom), l.nom])).values(),
    ];
    const analysees = etapes.filter((e) => e.analyse).length;
    return { km, pays, villes, trajets: trajets.length, analysees, etapes: etapes.length };
  }

  /** « 22k », « 1 250 », « 640 » : le nombre tel qu'il tient dans une case de la quatrième. */
  function nombreCourt(n) {
    if (n === null || n === undefined) return "—";
    if (n >= 10000) return `${Math.round(n / 1000)}k`;
    return new Intl.NumberFormat("fr-FR").format(n);
  }

  const api = {
    lieuValide,
    modeDe,
    distanceKm,
    domicile,
    trajetsDuVoyage,
    itineraire,
    lieuxDeSejour,
    chiffresDuVoyage,
    nombreCourt,
    normaliser,
  };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else racine.Voyage = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
