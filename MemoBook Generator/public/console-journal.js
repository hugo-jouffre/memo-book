/* Console de l'atelier — un panneau latéral droit, ouvert au survol de sa
   languette, qui raconte tout ce qui se passe : chaque appel réseau (OpenAI,
   Anthropic, APITemplate, GitHub, OpenStreetMap, fichiers de l'atelier), les
   clics sur les boutons, les messages des modules et les erreurs non
   rattrapées.

   Chargé **avant** tous les autres scripts : il remplace `window.fetch` et
   double `console.*`, si bien que rien n'a besoin d'être modifié ailleurs pour
   apparaître ici. `Journal.log(niveau, categorie, message, details)` sert à
   ce qui mérite d'être dit en clair.

   Les clés n'y passent jamais : les en-têtes ne sont pas journalisés, et
   tout champ ou paramètre dont le nom évoque une clé est masqué. Les images
   en base64 sont résumées à leur poids. */

(() => {
  const MAX_ENTREES = 3000;
  const entrees = [];
  let suivant = 1;
  let nonLues = 0;
  let panneau = null;

  const etatUi = {
    ouvert: false,
    epingle: lireLocal("atelier-journal-epingle") === "1",
    filtre: "tout",
    recherche: "",
    suivre: true,
  };

  function lireLocal(cle) {
    try {
      return localStorage.getItem(cle);
    } catch {
      return null;
    }
  }

  function ecrireLocal(cle, valeur) {
    try {
      localStorage.setItem(cle, valeur);
    } catch {
      /* navigation privée */
    }
  }

  /* ------------------------------------------------------------ masquage --- */

  const NOM_SECRET = /(^|_|-)(key|apikey|api_key|token|secret|password|authorization|cle)($|_|-)|^x-api-key$|^cle[A-Z]/i;

  /** Une valeur lisible et sans secret : base64 résumé, longues chaînes tronquées. */
  function assainir(valeur, profondeur = 0) {
    if (valeur == null) return valeur;
    if (typeof valeur === "string") {
      if (/^data:[\w/+.-]+;base64,/.test(valeur)) {
        return `[${valeur.slice(5, valeur.indexOf(";"))} base64, ${poids(valeur.length * 0.75)}]`;
      }
      if (valeur.length > 400 && /^[A-Za-z0-9+/=\s]+$/.test(valeur.slice(0, 400))) {
        return `[base64, ${poids(valeur.length * 0.75)}]`;
      }
      if (/^(sk-|sk-ant-)[\w-]{8,}/.test(valeur)) return "[clé masquée]";
      return valeur.length > 600 ? `${valeur.slice(0, 600)}… (+${valeur.length - 600} car.)` : valeur;
    }
    if (typeof valeur !== "object") return valeur;
    if (profondeur > 5) return "[…]";
    if (Array.isArray(valeur)) {
      const tete = valeur.slice(0, 20).map((v) => assainir(v, profondeur + 1));
      if (valeur.length > 20) tete.push(`… +${valeur.length - 20} élément(s)`);
      return tete;
    }
    if (valeur instanceof Error) return { nom: valeur.name, message: valeur.message, pile: valeur.stack };
    const sortie = {};
    for (const [cle, v] of Object.entries(valeur)) {
      sortie[cle] = NOM_SECRET.test(cle) && v ? "[masqué]" : assainir(v, profondeur + 1);
    }
    return sortie;
  }

  function urlLisible(brute) {
    try {
      const url = new URL(brute, location.href);
      for (const cle of [...url.searchParams.keys()]) {
        if (NOM_SECRET.test(cle)) url.searchParams.set(cle, "masqué");
      }
      return url.origin === location.origin ? `${url.pathname}${url.search}` : url.href;
    } catch {
      return String(brute);
    }
  }

  function serviceDe(url) {
    const u = String(url);
    if (u.includes("api.openai.com")) return "OpenAI";
    if (u.includes("api.anthropic.com")) return "Anthropic";
    if (u.includes("apitemplate.io")) return "APITemplate";
    if (u.includes("githubusercontent.com") || u.includes("api.github.com")) return "GitHub";
    if (u.includes("overpass")) return "OpenStreetMap";
    if (u.includes("nominatim")) return "Nominatim";
    if (u.includes("/api/")) return "Serveur local";
    return "Fichier";
  }

  function poids(octets) {
    if (!Number.isFinite(octets)) return "?";
    if (octets < 1024) return `${Math.round(octets)} o`;
    if (octets < 1024 * 1024) return `${(octets / 1024).toFixed(0)} Ko`;
    return `${(octets / 1024 / 1024).toFixed(1)} Mo`;
  }

  /** Ce que porte une requête, sans les secrets ni les images. */
  function resumerCorps(corps) {
    if (corps == null) return undefined;
    if (typeof corps === "string") {
      try {
        return assainir(JSON.parse(corps));
      } catch {
        return assainir(corps);
      }
    }
    if (typeof FormData !== "undefined" && corps instanceof FormData) {
      const champs = {};
      for (const [cle, v] of corps.entries()) {
        champs[cle] =
          typeof v === "string"
            ? NOM_SECRET.test(cle)
              ? "[masqué]"
              : assainir(v)
            : `[fichier ${v.name || "sans nom"}, ${v.type || "?"}, ${poids(v.size)}]`;
      }
      return { formulaire: champs };
    }
    if (corps instanceof Blob) return `[${corps.type || "binaire"}, ${poids(corps.size)}]`;
    if (corps instanceof ArrayBuffer) return `[binaire, ${poids(corps.byteLength)}]`;
    return `[${corps.constructor?.name || typeof corps}]`;
  }

  /* -------------------------------------------------------------- entrées --- */

  /**
   * niveau : "debug" | "info" | "succes" | "avert" | "erreur"
   * categorie : "api" | "action" | "atelier" | "console"
   */
  function log(niveau, categorie, message, details) {
    const entree = {
      id: suivant++,
      quand: new Date(),
      niveau,
      categorie,
      message: String(message),
      details: details === undefined ? undefined : assainir(details),
    };
    entrees.push(entree);
    if (entrees.length > MAX_ENTREES) entrees.splice(0, entrees.length - MAX_ENTREES);
    if (niveau === "erreur" && !etatUi.ouvert) nonLues++;
    planifierRendu(entree);
    return entree;
  }

  /** Complète une entrée déjà affichée (la réponse d'un appel en cours). */
  function completer(entree, patch) {
    Object.assign(entree, patch);
    if (patch.details !== undefined) entree.details = assainir(patch.details);
    if (patch.niveau === "erreur" && !etatUi.ouvert) nonLues++;
    planifierRendu(entree, true);
  }

  /* ------------------------------------------------------------ fetch --- */

  const fetchOrigine = window.fetch.bind(window);

  window.fetch = async function fetchJournalise(ressource, init = {}) {
    const brute = typeof ressource === "string" || ressource instanceof URL ? String(ressource) : ressource.url;
    const methode = (init.method || ressource?.method || "GET").toUpperCase();
    const service = serviceDe(brute);
    const url = urlLisible(brute);
    // Les polices, le logo, les contours : utiles quand ils manquent, du bruit
    // quand ils arrivent. Ils ne s'affichent qu'en « Debug » s'ils réussissent.
    const discret = service === "Fichier" && methode === "GET";
    const debut = performance.now();
    const entree = log(discret ? "debug" : "info", "api", `${service} · ${methode} ${url} …`, {
      requete: init.body !== undefined ? resumerCorps(init.body) : undefined,
    });
    entree.enCours = true;

    let reponse;
    try {
      reponse = await fetchOrigine(ressource, init);
    } catch (erreur) {
      completer(entree, {
        enCours: false,
        niveau: "erreur",
        message: `${service} · ${methode} ${url} — échec réseau (${Math.round(performance.now() - debut)} ms)`,
        details: {
          requete: entree.details?.requete,
          erreur: `${erreur.name} : ${erreur.message}`,
          piste:
            erreur.name === "AbortError"
              ? "Appel interrompu (délai dépassé ou annulé)."
              : "Pas de réponse : réseau coupé, adresse injoignable, ou appel bloqué par le navigateur (CORS). L'onglet Réseau des outils de développement en dit plus.",
        },
      });
      throw erreur;
    }

    const duree = Math.round(performance.now() - debut);
    const type = reponse.headers.get("content-type") || "";
    const taille = Number(reponse.headers.get("content-length"));
    const ok = reponse.ok;
    const details = {
      requete: entree.details?.requete,
      statut: `${reponse.status} ${reponse.statusText}`.trim(),
      type: type || undefined,
      taille: Number.isFinite(taille) && taille > 0 ? poids(taille) : undefined,
    };

    // Le corps se lit sur une copie, pour ne rien retirer à l'appelant. Pas
    // pour les flux (la transcription en direct) ni pour les binaires.
    const flux = /ndjson|event-stream/.test(type);
    const lisible = /json|text|xml|html/.test(type) && !flux && !(taille > 400_000);
    if (lisible && (!ok || !discret)) {
      try {
        const texte = await reponse.clone().text();
        try {
          details.reponse = JSON.parse(texte);
        } catch {
          details.reponse = texte.slice(0, 2000);
        }
      } catch {
        /* corps illisible : le statut suffit */
      }
    }

    const message = ok
      ? `${service} · ${methode} ${url} — ${reponse.status} en ${duree} ms`
      : `${service} · ${methode} ${url} — ${reponse.status} ${reponse.statusText || ""} en ${duree} ms`.replace(/\s+en/, " en");
    completer(entree, {
      enCours: false,
      niveau: ok ? (discret ? "debug" : "succes") : discret && reponse.status === 404 ? "avert" : "erreur",
      message,
      details,
    });
    return reponse;
  };

  /* ------------------------------------------------------------ console --- */

  const NIVEAU_CONSOLE = { debug: "debug", log: "debug", info: "info", warn: "avert", error: "erreur" };
  for (const [methode, niveau] of Object.entries(NIVEAU_CONSOLE)) {
    const origine = console[methode].bind(console);
    console[methode] = (...args) => {
      origine(...args);
      try {
        const textes = args.filter((a) => typeof a !== "object" || a === null).map(String);
        const objets = args.filter((a) => typeof a === "object" && a !== null);
        let message = textes.join(" ") || (objets[0] instanceof Error ? objets[0].message : "(objet)");
        const erreur = objets.find((o) => o instanceof Error);
        if (erreur && textes.length) message += ` — ${erreur.message}`;
        const categorie = /^\[(carnet|template|couverture|carte|analyse|atelier)/.test(message) ? "atelier" : "console";
        // Un `debugCarnet("… impossible", erreur)` est un échec rattrapé : il
        // mérite d'être vu sans passer en mode Debug.
        const niveauFinal = niveau === "debug" && erreur ? "avert" : niveau;
        log(niveauFinal, categorie, message, objets.length ? (objets.length === 1 ? objets[0] : objets) : undefined);
      } catch {
        /* le journal ne doit jamais casser l'atelier */
      }
    };
  }

  window.addEventListener("error", (ev) => {
    log("erreur", "console", `Erreur JavaScript : ${ev.message}`, {
      fichier: ev.filename ? `${ev.filename.split("/").pop()}:${ev.lineno}:${ev.colno}` : undefined,
      pile: ev.error?.stack,
    });
  });

  window.addEventListener("unhandledrejection", (ev) => {
    const r = ev.reason;
    log("erreur", "console", `Promesse rejetée sans traitement : ${r?.message || r}`, { pile: r?.stack });
  });

  /* ------------------------------------------------------------ actions --- */

  function libelle(el) {
    const texte = (el.getAttribute("aria-label") || el.textContent || "").replace(/\s+/g, " ").trim();
    return texte || el.getAttribute("title") || el.dataset.action || el.tagName.toLowerCase();
  }

  document.addEventListener(
    "click",
    (ev) => {
      const el = ev.target.closest?.("button, a.btn, [data-action], summary");
      if (!el || el.closest(".journal-panneau, .journal-languette")) return;
      log("info", "action", `Clic : « ${libelle(el).slice(0, 80)} »`, el.dataset.action ? { action: el.dataset.action } : undefined);
    },
    true,
  );

  document.addEventListener(
    "change",
    (ev) => {
      const el = ev.target;
      if (!(el instanceof HTMLInputElement || el instanceof HTMLSelectElement)) return;
      if (el.closest(".journal-panneau")) return;
      const etiquette = (el.closest("label")?.textContent || el.name || el.placeholder || "").replace(/\s+/g, " ").trim().slice(0, 80);
      if (el.type === "file") {
        const fichiers = [...(el.files || [])];
        if (!fichiers.length) return;
        log("info", "action", `Fichiers choisis : ${fichiers.length}${etiquette ? ` (${etiquette})` : ""}`, {
          fichiers: fichiers.slice(0, 30).map((f) => `${f.name} — ${poids(f.size)}`),
        });
      } else if (el.type === "checkbox" || el.type === "radio") {
        log("info", "action", `${el.checked ? "Coché" : "Décoché"} : ${etiquette || el.name || "case"}`);
      } else if (el instanceof HTMLSelectElement) {
        log("info", "action", `Choix : ${etiquette || "liste"} → ${el.selectedOptions[0]?.textContent?.trim() || el.value}`);
      } else if (el.type !== "password" && !NOM_SECRET.test(el.name || "")) {
        // Un champ texte modifié : on dit lequel, pas ce qu'il contient.
        log("debug", "action", `Champ modifié : ${etiquette || el.placeholder || "texte"}`);
      }
    },
    true,
  );

  // Les dépôts de fichiers par glisser-déposer ne passent pas par un <input>.
  document.addEventListener(
    "drop",
    (ev) => {
      const n = ev.dataTransfer?.files?.length || 0;
      if (n) log("info", "action", `Dépôt de ${n} fichier(s)`);
    },
    true,
  );

  /* --------------------------------------------------------------- panneau --- */

  const FILTRES = [
    ["tout", "Tout"],
    ["api", "API"],
    ["action", "Actions"],
    ["erreur", "Erreurs"],
    ["debug", "Debug"],
  ];

  const HEURE = new Intl.DateTimeFormat("fr-FR", { hour: "2-digit", minute: "2-digit", second: "2-digit" });

  function el(tag, attrs = {}, ...enfants) {
    const n = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs)) {
      if (v == null || v === false) continue;
      if (k === "class") n.className = v;
      else if (k.startsWith("on")) n.addEventListener(k.slice(2), v);
      else n.setAttribute(k, v === true ? "" : v);
    }
    for (const e of enfants.flat()) if (e != null && e !== false) n.append(e.nodeType ? e : document.createTextNode(String(e)));
    return n;
  }

  function visible(e) {
    const f = etatUi.filtre;
    if (f === "erreur" && !(e.niveau === "erreur" || e.niveau === "avert")) return false;
    if (f === "api" && e.categorie !== "api") return false;
    if (f === "action" && e.categorie !== "action") return false;
    if (f !== "debug" && f !== "erreur" && e.niveau === "debug") return false;
    if (etatUi.recherche) {
      const q = etatUi.recherche.toLowerCase();
      const blob = `${e.message} ${e.details ? JSON.stringify(e.details) : ""}`.toLowerCase();
      if (!blob.includes(q)) return false;
    }
    return true;
  }

  function ligne(e) {
    const details = e.details && Object.values(e.details).some((v) => v !== undefined);
    const tete = el(
      "div",
      { class: "journal-tete" },
      el("span", { class: "journal-heure" }, HEURE.format(e.quand)),
      el("span", { class: `journal-puce niveau-${e.niveau}`, title: e.niveau }),
      el("span", { class: "journal-cat" }, { api: "API", action: "action", atelier: "atelier", console: "console" }[e.categorie] || e.categorie),
      el("span", { class: "journal-msg" }, e.message),
    );
    if (!details) return el("div", { class: `journal-entree niveau-${e.niveau}`, "data-id": e.id }, tete);
    const bloc = el(
      "details",
      { class: `journal-entree niveau-${e.niveau}`, "data-id": e.id },
      el("summary", {}, tete),
      el("pre", { class: "journal-details" }, JSON.stringify(e.details, null, 2)),
    );
    return bloc;
  }

  let renduPrevu = false;
  const aRemplacer = new Set();

  function planifierRendu(entree, remplacement = false) {
    if (remplacement) aRemplacer.add(entree.id);
    if (renduPrevu) return;
    renduPrevu = true;
    requestAnimationFrame(() => {
      renduPrevu = false;
      rendreIncrement();
    });
  }

  let dernierRendu = 0;

  function rendreIncrement() {
    if (!panneau) return;
    majLanguette();
    const liste = panneau.liste;
    // Les entrées complétées (réponse arrivée) remplacent leur ligne en place,
    // en gardant ouvert ce qui l'était.
    for (const id of aRemplacer) {
      const ancienne = liste.querySelector(`[data-id="${id}"]`);
      const e = entrees.find((x) => x.id === id);
      if (!ancienne || !e) continue;
      if (!visible(e)) {
        ancienne.remove();
        continue;
      }
      const neuve = ligne(e);
      if (ancienne.open) neuve.open = true;
      ancienne.replaceWith(neuve);
    }
    aRemplacer.clear();
    const bas = liste.scrollHeight - liste.scrollTop - liste.clientHeight < 40;
    for (const e of entrees) {
      if (e.id <= dernierRendu) continue;
      if (visible(e)) liste.append(ligne(e));
    }
    dernierRendu = entrees.length ? entrees[entrees.length - 1].id : dernierRendu;
    while (liste.childElementCount > 800) liste.firstElementChild.remove();
    if (bas && etatUi.suivre) liste.scrollTop = liste.scrollHeight;
    majCompteurs();
  }

  function rendreTout() {
    if (!panneau) return;
    const visibles = entrees.filter(visible).slice(-800);
    panneau.liste.replaceChildren(...visibles.map(ligne));
    if (!visibles.length) panneau.liste.append(el("p", { class: "journal-vide" }, "Rien pour l'instant."));
    dernierRendu = entrees.length ? entrees[entrees.length - 1].id : 0;
    panneau.liste.scrollTop = panneau.liste.scrollHeight;
    for (const b of panneau.filtres.children) b.classList.toggle("actif", b.dataset.filtre === etatUi.filtre);
    majCompteurs();
    majLanguette();
  }

  function majCompteurs() {
    if (!panneau) return;
    const erreurs = entrees.filter((e) => e.niveau === "erreur").length;
    const appels = entrees.filter((e) => e.categorie === "api" && e.niveau !== "debug").length;
    panneau.compteurs.textContent = `${appels} appel(s) · ${erreurs} erreur(s)`;
  }

  function majLanguette() {
    if (!panneau) return;
    panneau.badge.hidden = nonLues === 0;
    panneau.badge.textContent = nonLues > 99 ? "99+" : String(nonLues);
    const enCours = entrees.some((e) => e.enCours);
    panneau.languette.classList.toggle("en-cours", enCours);
  }

  function ouvrir() {
    if (etatUi.ouvert) return;
    etatUi.ouvert = true;
    nonLues = 0;
    panneau.racine.classList.add("ouvert");
    rendreTout();
  }

  function fermer() {
    if (etatUi.epingle) return;
    etatUi.ouvert = false;
    panneau.racine.classList.remove("ouvert");
  }

  function basculerEpingle() {
    etatUi.epingle = !etatUi.epingle;
    ecrireLocal("atelier-journal-epingle", etatUi.epingle ? "1" : "0");
    panneau.epingle.classList.toggle("actif", etatUi.epingle);
    panneau.epingle.title = etatUi.epingle ? "Désépingler (le panneau se refermera en quittant)" : "Épingler ouvert";
    document.body.classList.toggle("journal-epingle", etatUi.epingle);
    if (etatUi.epingle) ouvrir();
  }

  function enTexte() {
    return entrees
      .map((e) => {
        const tete = `${e.quand.toISOString()} [${e.niveau}] [${e.categorie}] ${e.message}`;
        return e.details ? `${tete}\n${JSON.stringify(e.details, null, 2).replace(/^/gm, "    ")}` : tete;
      })
      .join("\n");
  }

  async function copier(bouton) {
    const texte = enTexte();
    try {
      await navigator.clipboard.writeText(texte);
      bouton.textContent = "Copié ✓";
    } catch {
      const zone = el("textarea", {}, texte);
      document.body.append(zone);
      zone.select();
      document.execCommand("copy");
      zone.remove();
      bouton.textContent = "Copié ✓";
    }
    setTimeout(() => (bouton.textContent = "Copier"), 1500);
  }

  function telecharger() {
    const blob = new Blob([enTexte()], { type: "text/plain" });
    const a = el("a", { href: URL.createObjectURL(blob), download: `atelier-journal-${new Date().toISOString().slice(0, 19).replace(/[:T]/g, "-")}.log` });
    document.body.append(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  }

  function construirePanneau() {
    const badge = el("span", { class: "journal-badge", hidden: true });
    const languette = el(
      "button",
      { class: "journal-languette", type: "button", title: "Console de l'atelier — survol pour ouvrir (Alt + J)", "aria-label": "Ouvrir la console" },
      el("span", { class: "journal-languette-texte" }, "Console"),
      badge,
    );

    const filtres = el(
      "div",
      { class: "journal-filtres", role: "tablist" },
      FILTRES.map(([cle, texte]) =>
        el(
          "button",
          {
            type: "button",
            class: "journal-filtre",
            "data-filtre": cle,
            onclick: () => {
              etatUi.filtre = cle;
              rendreTout();
            },
          },
          texte,
        ),
      ),
    );

    const recherche = el("input", {
      type: "search",
      class: "journal-recherche",
      placeholder: "Filtrer…",
      oninput: (ev) => {
        etatUi.recherche = ev.target.value.trim();
        rendreTout();
      },
    });

    const epingle = el(
      "button",
      { type: "button", class: `journal-outil${etatUi.epingle ? " actif" : ""}`, title: "Épingler ouvert", onclick: basculerEpingle },
      "📌",
    );

    const compteurs = el("span", { class: "journal-compteurs" });
    const liste = el("div", { class: "journal-liste" });

    const racine = el(
      "aside",
      { class: "journal-panneau", "aria-label": "Console de l'atelier" },
      el(
        "div",
        { class: "journal-entete" },
        el("strong", {}, "Console"),
        compteurs,
        el("span", { class: "journal-espace" }),
        el("button", { type: "button", class: "journal-outil", onclick: (ev) => copier(ev.currentTarget), title: "Copier tout le journal (pour le partager)" }, "Copier"),
        el("button", { type: "button", class: "journal-outil", onclick: telecharger, title: "Télécharger le journal en .log" }, "⤓"),
        el(
          "button",
          {
            type: "button",
            class: "journal-outil",
            title: "Vider le journal",
            onclick: () => {
              entrees.length = 0;
              nonLues = 0;
              rendreTout();
            },
          },
          "Vider",
        ),
        epingle,
        el(
          "button",
          {
            type: "button",
            class: "journal-outil",
            title: "Fermer",
            onclick: () => {
              if (etatUi.epingle) basculerEpingle();
              fermer();
            },
          },
          "✕",
        ),
      ),
      el("div", { class: "journal-barre" }, filtres, recherche),
      liste,
    );

    // Survol de la languette : le panneau glisse par-dessus la page. Il se
    // referme quand la souris le quitte, sauf s'il est épinglé.
    let minuteur = null;
    languette.addEventListener("mouseenter", () => {
      clearTimeout(minuteur);
      ouvrir();
    });
    languette.addEventListener("click", () => (etatUi.ouvert ? basculerEpingle() : ouvrir()));
    racine.addEventListener("mouseenter", () => clearTimeout(minuteur));
    racine.addEventListener("mouseleave", () => {
      minuteur = setTimeout(fermer, 350);
    });
    languette.addEventListener("mouseleave", () => {
      minuteur = setTimeout(fermer, 350);
    });

    document.addEventListener("keydown", (ev) => {
      if (ev.altKey && ev.code === "KeyJ") {
        ev.preventDefault();
        if (etatUi.ouvert) {
          if (etatUi.epingle) basculerEpingle();
          fermer();
        } else {
          ouvrir();
          if (!etatUi.epingle) basculerEpingle();
        }
      }
    });

    document.body.append(languette, racine);
    panneau = { racine, languette, badge, liste, filtres, compteurs, epingle };
    if (etatUi.epingle) {
      document.body.classList.add("journal-epingle");
      ouvrir();
    }
    rendreTout();
  }

  if (document.body) construirePanneau();
  else document.addEventListener("DOMContentLoaded", construirePanneau);

  log("info", "atelier", `Atelier ouvert — ${location.href.split("?")[0]}`, {
    navigateur: navigator.userAgent,
  });

  window.Journal = {
    log,
    debug: (categorie, message, details) => log("debug", categorie, message, details),
    info: (categorie, message, details) => log("info", categorie, message, details),
    succes: (categorie, message, details) => log("succes", categorie, message, details),
    avert: (categorie, message, details) => log("avert", categorie, message, details),
    erreur: (categorie, message, details) => log("erreur", categorie, message, details),
    ouvrir: () => panneau && ouvrir(),
    texte: enTexte,
  };
})();
