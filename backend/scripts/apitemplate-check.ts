#!/usr/bin/env tsx
/**
 * La clé APITemplate posée sur un service fabrique-t-elle un PDF ? — **sans
 * toucher à la base, sans créer de souvenir, et sans jamais afficher la clé.**
 *
 *     railway run --service worker --environment production -- npm run apitemplate:check
 *
 * Le renderer du serveur, tel quel, envoie le jeu d'essai du gabarit
 * (`MemoBook Generator/templates/travel-journal/data.json`) à APITemplate et
 * attend une URL de téléchargement. Trois réponses, trois diagnostics :
 *
 * - une URL — la clé est **acceptée** et le gabarit existe : le vrai PDF
 *   marche, et c'est la seule preuve qui vaille ;
 * - « HTTP 403 » — la clé est **refusée**. Presque toujours la région : une
 *   clé d'un compte DE appelée sur `rest.apitemplate.io` est rejetée, pas
 *   redirigée. Vérifier `APITEMPLATE_BASE_URL` (voir `docs/apitemplate.md`) ;
 * - « template not found » — la clé est bonne, mais `APITEMPLATE_TEMPLATE_ID`
 *   ne désigne rien dans **ce** compte : le gabarit n'y a jamais été
 *   synchronisé (`.github/workflows/sync-apitemplate.yml`).
 *
 * Pourquoi ce script existe : `RENDERER=auto` retombe sur le rendu simulé
 * **en silence** quand la clé manque (`services/apitemplate.ts`). La
 * configuration a donc toujours l'air juste, et rien ne distingue un PDF réel
 * d'une URL `pdf.example.test` avant qu'un voyageur n'essaie de l'ouvrir.
 * C'est ce silence qui a coûté une journée (02/11/2026).
 *
 * Le rendu est facturé par APITemplate comme n'importe quel autre : un appel.
 */
import { loadSamplePayload } from "../src/lib/templates.js";
import { ApiTemplateRenderer } from "../src/services/apitemplate.js";

const apiKey = process.env.APITEMPLATE_API_KEY ?? "";
const templateId = process.env.APITEMPLATE_TEMPLATE_ID || "7a177b23210099d6";
const baseUrl = process.env.APITEMPLATE_BASE_URL || "https://rest-de.apitemplate.io/v2";

console.log(`APITEMPLATE_API_KEY      ${apiKey === "" ? "absente" : `posée (${apiKey.length} caractères)`}`);
console.log(`APITEMPLATE_TEMPLATE_ID  ${templateId}`);
console.log(`APITEMPLATE_BASE_URL     ${baseUrl}${baseUrl.includes("rest-de.") ? " (région DE)" : " ⚠️ pas la région DE"}`);

if (apiKey === "") {
  console.log("\nAbsente : le serveur compose un PDF simulé, dont l'URL ne mène nulle part.");
  process.exit(1);
}

// Pas de source de rues : les cartes de ville demandent un aller-retour OSM
// qui n'apprend rien sur APITemplate, et dont la panne se lirait comme la
// sienne. Le gabarit s'en passe, les cartes sortent sans leurs rues.
const renderer = new ApiTemplateRenderer(apiKey, templateId, baseUrl, "preview", null);

try {
  const { pdfUrl, transactionId } = await renderer.render(loadSamplePayload());
  console.log(`\nPDF fabriqué — transaction ${transactionId || "(sans référence)"}`);
  console.log(pdfUrl);
  process.exit(0);
} catch (cause) {
  console.log(`\n${cause instanceof Error ? cause.message : String(cause)}`);
  process.exit(1);
}
