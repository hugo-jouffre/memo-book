/**
 * Pousse les gabarits de `templates/emails/` dans le compte Resend, en
 * **gabarits Resend** (`POST /templates`) plutôt qu'en HTML recollé à chaque
 * envoi.
 *
 * Pourquoi passer par des gabarits hébergés plutôt que d'envoyer le HTML :
 * c'est le niveau 2 de `docs/emails.md`. Le déclencheur reste l'API, mais la
 * copie et la mise en forme deviennent modifiables dans Resend — donc par une
 * équipe CRM, sans déploiement. L'envoi ne transporte plus que des variables.
 *
 *     npm run emails:sync -- --dry-run   # rend et écrit en local, n'appelle rien
 *     npm run emails:sync                # crée ou met à jour, puis publie
 *
 * **Le gabarit Resend est dérivé, jamais écrit à la main.** Il est rendu depuis
 * le même `.njk` que l'aperçu local, avec des marqueurs Resend à la place des
 * données. Les deux ne peuvent donc pas diverger — et si quelqu'un modifie le
 * gabarit dans l'interface Resend, la prochaine synchronisation l'écrase. Voir
 * « Qui écrit quoi » dans `templates/emails/README.md`.
 */

import { copyFileSync, existsSync, mkdirSync, readdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import nunjucks from "nunjucks";

const here = dirname(fileURLToPath(import.meta.url));

/**
 * Le `.env` du back-end, comme le serveur le lit — `env.ts` fait exactement
 * cela. Sans cette ligne, `RESEND_API_KEY` posée dans le fichier serait
 * ignorée, et le script annoncerait une clé manquante devant une clé présente.
 *
 * Les variables déjà dans l'environnement l'emportent : c'est ce qui permet
 * `RESEND_API_KEY=… npm run emails:sync` depuis un worktree, qui n'a pas de
 * `.env` à lui.
 */
const ENV_FILE = resolve(here, "../.env");
if (existsSync(ENV_FILE)) process.loadEnvFile(ENV_FILE);
const EMAILS_DIR = resolve(here, "../../templates/emails");
const ASSETS_DIR = resolve(here, "../../assets/emails");
const OUT_DIR = resolve(here, "../.mail-out/resend");

const API = "https://api.resend.com";

/**
 * La syntaxe de variable de Resend. **Triple accolade**, et non double : la
 * double est celle de nunjucks, qui a déjà consommé la sienne au moment où ce
 * fichier est produit.
 */
function v(key: string): string {
  return `{{{${key}}}}`;
}

interface TemplateVariable {
  key: string;
  type: "string" | "number";
  fallback_value?: string | number;
}

interface TemplateDefinition {
  /** L'identifiant stable côté envoi. `POST /emails` accepte l'alias. */
  alias: string;
  name: string;
  file: string;
  /**
   * Ce qu'on passe à nunjucks : des marqueurs Resend, pas des données.
   *
   * Tout ce qui **peut manquer** est composé côté back-end et arrive ici en une
   * seule variable — un gabarit Resend ne sait faire qu'une substitution, ni
   * condition ni boucle. C'est la contrainte qui a fait naître `GREETING`
   * plutôt qu'un prénom nu.
   */
  context: Record<string, unknown>;
  variables: TemplateVariable[];
  /** La version texte. Jamais celle que Resend déduirait d'un HTML en tables. */
  text: string;
  /**
   * De vraies valeurs, pour relire l'e-mail comme le lira le destinataire.
   * `--preview` rend avec celles-ci au lieu des marqueurs : un gabarit criblé
   * de `{{{MAJUSCULES}}}` ne dit rien de ce qu'on est en train d'écrire.
   */
  sample: Record<string, string | number>;
}

/** Constantes de marque, identiques pour tous les gabarits. */
const BRAND = {
  address: "12 rue des Voyages, 75011 Paris",
  supportEmail: "bonjour@memo-book.com",
  web: "https://memo-book.com",
};

const ASSETS_FALLBACK = "https://memo-book.com/emails";

const COMMON_VARIABLES: TemplateVariable[] = [
  { key: "ASSETS_BASE_URL", type: "string", fallback_value: ASSETS_FALLBACK },
  { key: "PREFERENCES_URL", type: "string", fallback_value: `${BRAND.web}/preferences` },
];

const TEMPLATES: TemplateDefinition[] = [
  {
    alias: "print-order-shipped",
    name: "Carnet expédié — suivi de commande",
    file: "print-order-shipped.njk",
    context: {
      brand: { ...BRAND, assetsBaseUrl: v("ASSETS_BASE_URL") },
      message: { class: "transactional", reason: "tu as commandé un carnet imprimé" },
      links: {
        web: BRAND.web,
        preferences: v("PREFERENCES_URL"),
        orderInApp: v("ORDER_IN_APP_URL"),
      },
      recipient: { greeting: v("GREETING") },
      order: {
        reference: v("ORDER_REF"),
        memoTitle: v("MEMO_TITLE"),
        coverImageUrl: v("COVER_URL"),
        // Le nombre de pages est facultatif en base : la légende entière vient
        // donc du back-end, plutôt qu'un « · pages » orphelin quand il manque.
        coverCaption: v("COVER_CAPTION"),
        copies: v("COPIES"),
        carrier: v("CARRIER"),
        trackingUrl: v("TRACKING_URL"),
        shippedOn: v("SHIPPED_ON"),
        estimatedRange: v("ESTIMATED_RANGE"),
        shipping: {
          name: v("SHIPPING_NAME"),
          line1: v("SHIPPING_LINE1"),
          cityLine: v("SHIPPING_CITY_LINE"),
          city: v("SHIPPING_CITY"),
        },
        // L'état est figé par l'identité même du gabarit : « expédié » veut dire
        // deux étapes faites, une en cours, une à venir. Un autre état, c'est un
        // autre gabarit — `print-order-delivered` — et non une condition ici.
        tracking: [
          { label: "Commande reçue", detail: v("STEP1_DETAIL"), state: "done" },
          { label: "Impression et reliure", detail: v("STEP2_DETAIL"), state: "done" },
          { label: "Expédié", detail: v("STEP3_DETAIL"), state: "current" },
          { label: "Livré", detail: v("STEP4_DETAIL"), state: "todo" },
        ],
      },
    },
    variables: [
      ...COMMON_VARIABLES,
      { key: "GREETING", type: "string", fallback_value: "" },
      { key: "MEMO_TITLE", type: "string", fallback_value: "ton carnet" },
      { key: "COVER_URL", type: "string", fallback_value: `${ASSETS_FALLBACK}/couverture-exemple.png` },
      { key: "COVER_CAPTION", type: "string", fallback_value: "" },
      { key: "ORDER_REF", type: "string" },
      { key: "COPIES", type: "number", fallback_value: 1 },
      { key: "CARRIER", type: "string", fallback_value: "le transporteur" },
      { key: "TRACKING_URL", type: "string" },
      { key: "ORDER_IN_APP_URL", type: "string", fallback_value: "memobook://orders" },
      { key: "SHIPPED_ON", type: "string", fallback_value: "aujourd'hui" },
      { key: "ESTIMATED_RANGE", type: "string" },
      { key: "SHIPPING_NAME", type: "string" },
      { key: "SHIPPING_LINE1", type: "string" },
      { key: "SHIPPING_CITY_LINE", type: "string" },
      { key: "SHIPPING_CITY", type: "string", fallback_value: "chez toi" },
      { key: "STEP1_DETAIL", type: "string", fallback_value: "" },
      { key: "STEP2_DETAIL", type: "string", fallback_value: "" },
      { key: "STEP3_DETAIL", type: "string", fallback_value: "" },
      { key: "STEP4_DETAIL", type: "string", fallback_value: "" },
    ],
    text: [
      "MemoBook",
      "",
      "TON CARNET EST EN ROUTE",
      "",
      `${v("GREETING")}« ${v("MEMO_TITLE")} » a quitté l'imprimerie ${v("SHIPPED_ON")}.`,
      `Le colis voyage maintenant vers ${v("SHIPPING_CITY")}.`,
      "",
      `Commande reçue — ${v("STEP1_DETAIL")}`,
      `Impression et reliure — ${v("STEP2_DETAIL")}`,
      `Expédié — ${v("STEP3_DETAIL")}`,
      `Livré — ${v("STEP4_DETAIL")}`,
      "",
      `Suivre le colis (${v("CARRIER")}) :`,
      v("TRACKING_URL"),
      "",
      `Commande ${v("ORDER_REF")}`,
      `Exemplaires : ${v("COPIES")}`,
      `Livraison estimée : ${v("ESTIMATED_RANGE")}`,
      `Adresse : ${v("SHIPPING_NAME")}, ${v("SHIPPING_LINE1")}, ${v("SHIPPING_CITY_LINE")}`,
      "",
      "L'adresse n'est pas la bonne, ou le colis n'arrive pas ? Réponds à cet",
      "e-mail avant la livraison, on rattrape ce qui peut l'être.",
      "",
      "Tu reçois cet e-mail parce que tu as commandé un carnet imprimé.",
      `Gérer mes e-mails : ${v("PREFERENCES_URL")}`,
      `MemoBook — ${BRAND.address}`,
    ].join("\n"),
    sample: {
      ASSETS_BASE_URL: ".",
      PREFERENCES_URL: `${BRAND.web}/preferences?t=jeton`,
      GREETING: "Clara, ",
      MEMO_TITLE: "Rome 2026",
      COVER_URL: "./couverture-exemple.png",
      COVER_CAPTION: "Rome 2026 · 68 pages",
      ORDER_REF: "MB-2609-0148",
      COPIES: 2,
      CARRIER: "Colissimo",
      TRACKING_URL: "https://www.laposte.fr/outils/suivre-vos-envois?code=6A12345678901",
      ORDER_IN_APP_URL: "memobook://orders/8f2c",
      SHIPPED_ON: "ce matin",
      ESTIMATED_RANGE: "entre le 22 et le 24 septembre",
      SHIPPING_NAME: "Clara Prunier",
      SHIPPING_LINE1: "24 rue de la Roquette",
      SHIPPING_CITY_LINE: "75011 Paris",
      SHIPPING_CITY: "Paris",
      STEP1_DETAIL: "15 septembre",
      STEP2_DETAIL: "17 — 19 septembre",
      STEP3_DETAIL: "aujourd'hui, 9 h 40",
      STEP4_DETAIL: "estimé entre le 22 et le 24 septembre",
    },
  },

  {
    alias: "password-reset",
    name: "Réinitialisation du mot de passe",
    file: "password-reset.njk",
    context: {
      brand: { ...BRAND, assetsBaseUrl: v("ASSETS_BASE_URL") },
      message: {
        class: "transactional",
        reason: "quelqu'un a demandé un nouveau mot de passe pour ton compte",
      },
      links: { web: BRAND.web, preferences: v("PREFERENCES_URL") },
      recipient: { greeting: v("GREETING") },
      reset: { url: v("RESET_URL"), validity: v("VALIDITY") },
    },
    variables: [
      ...COMMON_VARIABLES,
      { key: "GREETING", type: "string", fallback_value: "Bonjour," },
      { key: "RESET_URL", type: "string" },
      { key: "VALIDITY", type: "string", fallback_value: "30 minutes" },
    ],
    text: [
      "MemoBook",
      "",
      "RÉINITIALISE TON MOT DE PASSE",
      "",
      v("GREETING"),
      "",
      "Quelqu'un — toi, on l'espère — a demandé un nouveau mot de passe pour ton",
      "compte MemoBook. Ouvre ce lien pour en choisir un nouveau :",
      "",
      v("RESET_URL"),
      "",
      `Ce lien est valable ${v("VALIDITY")}, et ne fonctionne qu'une fois.`,
      "",
      "Tu n'as rien demandé ? Ignore cet e-mail : ton mot de passe reste celui que",
      "tu connais, et le lien s'éteint tout seul. Personne n'entre dans ton compte",
      "avec cet e-mail seul.",
      "",
      "Si ça se reproduit sans que tu y sois pour quelque chose, réponds à cet",
      "e-mail — on regardera ce qui se passe sur ton compte.",
      "",
      `MemoBook — ${BRAND.address}`,
    ].join("\n"),
    sample: {
      ASSETS_BASE_URL: ".",
      PREFERENCES_URL: `${BRAND.web}/preferences?t=jeton`,
      GREETING: "Bonjour Clara,",
      RESET_URL: "memobook://password/reset?token=8f2c4e1a9b7d3056",
      VALIDITY: "30 minutes",
    },
  },
];

interface RenderedTemplate {
  definition: TemplateDefinition;
  subject: string;
  html: string;
}

function render(definition: TemplateDefinition): RenderedTemplate {
  const env = nunjucks.configure(EMAILS_DIR, { autoescape: true });
  const html = env.render(definition.file, definition.context);

  // L'objet vit dans le `{% block subject %}` du gabarit, donc dans son <title> :
  // une seule source, et pas un objet qui dérive du corps qu'il annonce.
  const subject = /<title>([\s\S]*?)<\/title>/.exec(html)?.[1]?.trim();
  if (!subject) {
    throw new Error(`${definition.file} : pas de <title>, donc pas d'objet d'e-mail.`);
  }

  // Un marqueur mal formé — « {{FOO}} » au lieu de « {{{FOO}}} » — passerait
  // sans bruit et arriverait tel quel dans la boîte du client.
  const declared = new Set(definition.variables.map((variable) => variable.key));
  for (const match of html.matchAll(/\{\{\{([A-Z0-9_]+)\}\}\}/g)) {
    const key = match[1] ?? "";
    if (!declared.has(key)) {
      throw new Error(`${definition.file} : la variable ${key} n'est pas déclarée.`);
    }
  }
  for (const variable of definition.variables) {
    if (!html.includes(v(variable.key)) && !definition.text.includes(v(variable.key))) {
      throw new Error(`${definition.file} : ${variable.key} est déclarée mais jamais employée.`);
    }
  }

  return { definition, subject, html };
}

/**
 * Remplace les marqueurs par des valeurs, exactement comme Resend le fait à
 * l'envoi. Simuler la substitution plutôt que rendre un second jeu de données
 * garantit qu'on relit bien le gabarit qui sera poussé, et pas un cousin.
 */
function substitute(text: string, sample: Record<string, string | number>): string {
  return text.replaceAll(/\{\{\{([A-Z0-9_]+)\}\}\}/g, (marker, key: string) =>
    key in sample ? String(sample[key]) : marker,
  );
}

async function call(path: string, apiKey: string, body?: unknown) {
  const response = await fetch(`${API}${path}`, {
    method: body === undefined ? "GET" : "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      ...(body === undefined ? {} : { "Content-Type": "application/json" }),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const payload = (await response.json().catch(() => ({}))) as Record<string, unknown>;
  if (!response.ok) {
    throw new Error(
      `Resend a refusé ${path} (${response.status}) : ${JSON.stringify(payload)}`,
    );
  }
  return payload;
}

async function findByAlias(apiKey: string, alias: string): Promise<string | undefined> {
  const payload = await call("/templates", apiKey);
  const list = (payload.data ?? payload) as Array<{ id?: string; alias?: string }>;
  if (!Array.isArray(list)) return undefined;
  return list.find((template) => template.alias === alias)?.id;
}

async function sync(rendered: RenderedTemplate, apiKey: string): Promise<void> {
  const { definition, subject, html } = rendered;
  const body = {
    name: definition.name,
    alias: definition.alias,
    subject,
    html,
    text: definition.text,
    variables: definition.variables,
  };

  const existing = await findByAlias(apiKey, definition.alias);
  const result = existing
    ? await call(`/templates/${existing}`, apiKey, body)
    : await call("/templates", apiKey, body);

  const id = (result.id as string | undefined) ?? existing;
  if (!id) throw new Error(`${definition.alias} : Resend n'a pas renvoyé d'identifiant.`);

  // Sans publication, l'alias n'est pas envoyable : `POST /emails` ne résout
  // qu'un gabarit publié. Créer sans publier donnerait un brouillon invisible
  // depuis le code, et une erreur au premier envoi réel.
  await call(`/templates/${id}/publish`, apiKey, {});
  console.log(`  ✓ ${definition.alias} — ${existing ? "mis à jour" : "créé"} et publié (${id})`);
}

async function main() {
  const preview = process.argv.includes("--preview");
  const dryRun = preview || process.argv.includes("--dry-run");
  const apiKey = process.env.RESEND_API_KEY ?? "";

  const rendered = TEMPLATES.map(render);

  if (dryRun || apiKey === "") {
    mkdirSync(OUT_DIR, { recursive: true });
    // Les aperçus pointent sur `./logo.png` : sans les images à côté du HTML,
    // on relirait un e-mail à l'en-tête cassé et on chercherait le défaut dans
    // le gabarit. En production, ces fichiers viennent d'ASSETS_BASE_URL.
    if (preview && existsSync(ASSETS_DIR)) {
      for (const asset of readdirSync(ASSETS_DIR)) {
        copyFileSync(resolve(ASSETS_DIR, asset), resolve(OUT_DIR, asset));
      }
    }
    for (const { definition, subject, html } of rendered) {
      const path = resolve(OUT_DIR, `${definition.alias}.html`);
      const sample = definition.sample;
      writeFileSync(path, preview ? substitute(html, sample) : html);
      writeFileSync(
        resolve(OUT_DIR, `${definition.alias}.txt`),
        preview ? substitute(definition.text, sample) : definition.text,
      );
      console.log(`  • ${definition.alias}`);
      console.log(`      objet     ${preview ? substitute(subject, sample) : subject}`);
      console.log(`      variables ${definition.variables.length}`);
      console.log(`      html      ${path}`);
    }
    if (!dryRun) {
      console.error(
        "\nRESEND_API_KEY est vide : rien n'a été poussé chez Resend.\n" +
          "Pose la clé dans backend/.env, puis relance sans --dry-run.",
      );
      process.exitCode = 1;
    }
    return;
  }

  console.log(`Synchronisation de ${rendered.length} gabarits chez Resend…`);
  for (const template of rendered) await sync(template, apiKey);
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
