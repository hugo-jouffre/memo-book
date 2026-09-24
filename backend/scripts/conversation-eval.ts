#!/usr/bin/env tsx
/**
 * Faire parler MEMO, et relire ce qu'il dit.
 *
 *   npm run conversation:eval                    Claude, sur toutes les scènes
 *   npm run conversation:eval -- --heuristic     le moteur de règles (sans clé)
 *   npm run conversation:eval -- --only refus    les scènes dont le nom de
 *                                                fichier contient « refus »
 *   npm run conversation:eval -- --json          la sortie brute, pour differ
 *                                                deux versions du prompt
 *
 * **Ce n'est pas un test, et ça n'en deviendra pas un.** Le modèle n'entre
 * jamais en CI (`docs/conversation.md` § 13) : ce qui se vérifie sans lui est
 * dans `src/services/conversationAnthropic.test.ts`. Ici, une machine ne peut
 * rattraper que la forme — une question, trois bulles, le catalogue, les mots
 * interdits. Le reste se lit, avec la grille du § 13, et c'est pour ça que
 * chaque scène rappelle ce qu'elle éprouve.
 *
 * Rien n'est écrit en base : le script n'appelle que le répondeur.
 */
import Anthropic from "@anthropic-ai/sdk";
import { readFile, readdir } from "node:fs/promises";
import { basename, resolve } from "node:path";
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import {
  EMPTY_CONVERSATION_STATE,
  MAX_BEATS,
  type ConversationInput,
  type ConversationReply,
  type MemoResponder,
} from "../src/services/conversation.js";
import { AnthropicResponder } from "../src/services/conversationAnthropic.js";
import { HeuristicResponder } from "../src/services/conversationHeuristics.js";
import { EMPTY_COHERENCE_SHEET } from "../src/services/redaction.js";

const here = dirname(fileURLToPath(import.meta.url));
const SCENES_DIR = resolve(here, "../test/fixtures/conversation");

const { values } = parseArgs({
  options: {
    heuristic: { type: "boolean", default: false },
    only: { type: "string" },
    json: { type: "boolean", default: false },
    model: { type: "string", default: process.env.ANTHROPIC_CONVERSATION_MODEL ?? "claude-sonnet-5" },
  },
});

// ---------------------------------------------------------------------------
// Les scènes
// ---------------------------------------------------------------------------

interface Scene {
  name: string;
  why?: string;
  memo?: {
    title?: string;
    theme?: string | null;
    destinationCity?: string | null;
    narrationPace?: string | null;
    prompt?: string | null;
    people?: string[];
    places?: string[];
  };
  traveller?: { firstName?: string | null; memberCount?: number };
  step?: { number: number; placeName?: string | null } | null;
  history?: { author: "memo" | "traveller"; authorName?: string | null; text: string | null }[];
  message?: {
    kind?: "text" | "voice" | "photos";
    text?: string | null;
    suggestionId?: string | null;
    photoCount?: number;
    durationSeconds?: number | null;
    transcriptFailed?: boolean;
  };
  currentEntry?: { text: string | null; validatedAt?: string | null; placeLabel?: string | null } | null;
  recentEntries?: { text: string; placeLabel?: string | null; capturedAt?: string }[];
  allows?: { roseEpineGraine?: boolean };
  expect?: { disposition?: ConversationReply["disposition"] };
}

const NOW = new Date("2026-09-21T18:00:00Z");

/** Une scène du dossier vers l'entrée que le répondeur attend. */
function toInput(scene: Scene): ConversationInput {
  const memo = scene.memo ?? {};
  const message = scene.message ?? {};

  return {
    memo: {
      id: "eval",
      title: memo.title ?? "Rome 2026",
      theme: memo.theme ?? null,
      destinationCity: memo.destinationCity ?? null,
      startDate: new Date("2026-09-15T00:00:00Z"),
      endDate: new Date("2026-09-28T00:00:00Z"),
      narrationPace: memo.narrationPace ?? null,
      prompt: memo.prompt ?? null,
      coherenceSheet: {
        ...EMPTY_COHERENCE_SHEET,
        people: (memo.people ?? []).map((canonicalName) => ({ canonicalName, notes: "" })),
        places: (memo.places ?? []).map((canonicalName) => ({ canonicalName, notes: "" })),
      },
      state: EMPTY_CONVERSATION_STATE,
    },
    traveller: {
      firstName: scene.traveller?.firstName ?? "Hugo",
      memberCount: scene.traveller?.memberCount ?? 1,
    },
    step: scene.step
      ? {
          id: "step",
          number: scene.step.number,
          placeName: scene.step.placeName ?? null,
          startDate: null,
          endDate: null,
        }
      : null,
    history: (scene.history ?? []).map((turn, index) => ({
      author: turn.author,
      authorName: turn.authorName ?? null,
      kind: "text" as const,
      text: turn.text,
      disposition: null,
      // Espacés d'une minute, dans l'ordre du fichier.
      sentAt: new Date(NOW.getTime() - (scene.history!.length - index) * 60_000),
    })),
    message: {
      id: "message",
      kind: message.kind ?? "text",
      text: message.text ?? null,
      suggestionId: message.suggestionId ?? null,
      photoCount: message.photoCount ?? 0,
      durationSeconds: message.durationSeconds ?? null,
      transcriptFailed: message.transcriptFailed ?? false,
      sentAt: NOW,
    },
    currentEntry: scene.currentEntry
      ? {
          id: "entry",
          text: scene.currentEntry.text,
          redactionStatus: "ready",
          validatedAt: scene.currentEntry.validatedAt ? new Date(scene.currentEntry.validatedAt) : null,
          capturedAt: new Date(NOW.getTime() - 3_600_000),
          placeLabel: scene.currentEntry.placeLabel ?? null,
        }
      : null,
    recentEntries: (scene.recentEntries ?? []).map((entry) => ({
      capturedAt: entry.capturedAt ? new Date(entry.capturedAt) : new Date(NOW.getTime() - 86_400_000),
      placeLabel: entry.placeLabel ?? null,
      title: null,
      text: entry.text,
    })),
    allows: { roseEpineGraine: scene.allows?.roseEpineGraine ?? false },
    now: NOW,
  };
}

// ---------------------------------------------------------------------------
// Ce qu'une machine sait relire
// ---------------------------------------------------------------------------

/** Les mots que MEMO n'emploie jamais — `agents/agent-conversation.md` § 5. */
const FORBIDDEN = [
  // MEMO parle en son nom : personne d'autre n'existe pour le voyageur (§ 1).
  "agent de rédaction",
  "l'écrivain",
  "un écrivain",
  "le système",
  "token",
  "jeton",
  "quota",
  "crédit",
  "intelligence artificielle",
  "prompt",
  "utilisateur",
  "entrée",
];

/**
 * Le vouvoiement — mais **aucune machine ne sait le distinguer du « vous »
 * d'un groupe**. « La burrata coupée devant vous », quand le voyageur était
 * avec Clara, est du français correct et non un changement de registre.
 *
 * On ne tranche donc que le cas sûr : personne d'autre en scène. Dès qu'il y a
 * un co-voyageur ou quelqu'un de nommé, la ligne passe en lecture à la main
 * plutôt qu'en manquement — un faux positif répété apprend à ignorer la grille.
 */
const VOUVOIEMENT = /\b(vous (?:êtes|avez|pouvez|voulez|devez)|votre|vos)\b/i;

interface Check {
  label: string;
  ok: boolean;
  detail?: string;
}

/** Les scènes où un « vous » a été employé avec quelqu'un d'autre en scène. */
const ambiguousVouvoiement = new Set<string>();

function automaticChecks(
  reply: ConversationReply,
  input: ConversationInput,
  file: string,
): Check[] {
  const text = reply.beats.map((beat) => beat.text).join(" ");
  const questions = (text.match(/[?？]/g) ?? []).length;
  const received = (input.message.text ?? "").toLowerCase();

  // « Au moins un mot du voyageur » : un mot de plus de quatre lettres, hors
  // mots outils, qu'on retrouve dans la reformulation.
  const travellerWords = received
    .split(/[^\p{L}]+/u)
    .filter((word) => word.length > 4 && !STOP_WORDS.has(word));
  const reformulation = (reply.beats[0]?.text ?? "").toLowerCase();
  const echoed = travellerWords.filter((word) => reformulation.includes(word));

  const forbidden = FORBIDDEN.filter((word) => text.toLowerCase().includes(word));
  // « stop » seul en a été retiré le 24/09 : un vrai vocal de testeur disait
  // « on a fait un bon petit stop avant de prendre le ferry » (une halte, pas
  // un refus) — faux positif sur le premier essai en vraie voix, comme les
  // deux du 23/09. Les autres formules restent, plus explicites en français.
  const refused = /\b(plus tard|pas maintenant|pas envie|laisse[- ]moi)\b/i.test(received);

  // « C'était où, et avec qui ? » n'a qu'un point d'interrogation et pose deux
  // questions. On cherche deux mots interrogatifs dans la même phrase.
  const INTERROGATIVES =
    /\b(où|qui|quoi|quand|comment|pourquoi|combien|quel|quelle|quels|quelles|lequel|laquelle)\b/gi;
  const doubled = reply.beats
    .flatMap((beat) => beat.text.split(/(?<=[.!?…])\s+/))
    .filter((sentence) => sentence.includes("?"))
    .map((sentence) => sentence.match(INTERROGATIVES)?.length ?? 0);

  const checks: Check[] = [
    { label: "Une seule question", ok: questions <= 1, detail: `${questions} point(s) d'interrogation` },
    {
      label: "Une seule demande dans la question",
      ok: doubled.every((count) => count <= 1),
      detail: doubled.some((count) => count > 1) ? "deux mots interrogatifs dans la même phrase" : undefined,
    },
    {
      label: `${MAX_BEATS} bulles au plus`,
      ok: reply.beats.length <= MAX_BEATS,
      detail: `${reply.beats.length} bulle(s)`,
    },

    {
      label: "Aucun mot interdit",
      ok: forbidden.length === 0,
      detail: forbidden.join(", ") || undefined,
    },
    { label: "Ni Markdown ni emoji", ok: !/[*_#`]|\p{Extended_Pictographic}/u.test(text) },
    {
      label: "La relance se lit seule",
      ok: reply.prompt === null || reply.prompt.split(/\s+/).length >= 4,
      detail: reply.prompt ?? "(inchangée)",
    },
  ];

  // Sur un refus, il n'y a rien à reformuler : exiger l'écho serait exiger
  // d'insister.
  // Quelqu'un d'autre est en scène : un co-voyageur, une personne de la fiche
  // de cohérence, ou un prénom dans le message.
  const someoneElse =
    input.traveller.memberCount > 1 ||
    input.memo.coherenceSheet.people.length > 0 ||
    input.history.some((turn) => turn.authorName !== null);
  const vouvoiement = VOUVOIEMENT.exec(text)?.[0];

  if (someoneElse) {
    if (vouvoiement) ambiguousVouvoiement.add(file);
  } else {
    checks.push({ label: "Tutoiement", ok: vouvoiement === undefined, detail: vouvoiement });
  }

  if (travellerWords.length > 0 && !refused) {
    checks.push({
      label: "La reformulation reprend un mot du voyageur",
      ok: echoed.length > 0,
      detail: echoed.slice(0, 3).join(", ") || undefined,
    });
  }
  if (refused) {
    checks.push({ label: "Aucune question après un refus", ok: questions === 0 });
  }
  if (input.allows.roseEpineGraine) {
    checks.push({
      label: "Rose/épine/graine posée",
      ok: reply.asksRoseEpineGraine,
      detail: reply.asksRoseEpineGraine ? undefined : "autorisée, mais non posée",
    });
  }
  if (!input.allows.roseEpineGraine) {
    checks.push({ label: "Pas de rose/épine/graine non autorisée", ok: !reply.asksRoseEpineGraine });
  }

  return checks;
}

const STOP_WORDS = new Set([
  "alors",
  "après",
  "avec",
  "beaucoup",
  "c'est",
  "cette",
  "comme",
  "dans",
  "était",
  "faire",
  "franchement",
  "juste",
  "mais",
  "parce",
  "pour",
  "quand",
  "sur",
  "tout",
  "toute",
  "très",
  "vraiment",
]);

/** Ce qu'aucune machine ne relit à notre place — la grille du § 13. */
const BY_HAND = [
  "Aucun fait inventé",
  "La question n'est pas déjà répondue dans le fil ou le souvenir",
  "La question est la plus utile au carnet (lieu → avec qui → détail → ressenti)",
  "Ça sonne comme quelqu'un, pas comme un formulaire",
];

// ---------------------------------------------------------------------------
// Le déroulé
// ---------------------------------------------------------------------------

function responderFor(): { responder: MemoResponder; label: string } {
  if (values.heuristic) return { responder: new HeuristicResponder(), label: "moteur de règles" };

  const apiKey = process.env.ANTHROPIC_API_KEY ?? "";
  if (apiKey === "") {
    console.error(
      "ANTHROPIC_API_KEY est vide. Lance avec --heuristic pour le moteur de règles,\n" +
        "ou avec la clé : npm run conversation:eval (le script lit .env).",
    );
    process.exit(1);
  }
  return { responder: new AnthropicResponder(new Anthropic({ apiKey }), values.model), label: values.model };
}

async function main(): Promise<void> {
  const files = (await readdir(SCENES_DIR))
    .filter((name) => name.endsWith(".json"))
    .filter((name) => !values.only || name.includes(values.only))
    .sort();

  if (files.length === 0) {
    console.error(`Aucune scène dans ${SCENES_DIR}${values.only ? ` pour « ${values.only} »` : ""}.`);
    process.exit(1);
  }

  const { responder, label } = responderFor();
  const results: unknown[] = [];
  let failures = 0;

  if (!values.json) {
    console.log(`\nMEMO — ${label}, ${files.length} scène(s)\n${"=".repeat(60)}`);
  }

  for (const file of files) {
    const scene = JSON.parse(await readFile(resolve(SCENES_DIR, file), "utf8")) as Scene;
    const input = toInput(scene);

    let reply: ConversationReply;
    try {
      reply = await responder.reply(input);
    } catch (cause) {
      failures += 1;
      console.error(`\n✗ ${scene.name} (${basename(file)}) — ${(cause as Error).message}`);
      continue;
    }

    const checks = automaticChecks(reply, input, file);
    const dispositionCheck: Check | null = scene.expect?.disposition
      ? {
          label: `Classement attendu : ${scene.expect.disposition}`,
          ok: reply.disposition === scene.expect.disposition,
          detail: reply.disposition,
        }
      : null;
    const all = dispositionCheck ? [...checks, dispositionCheck] : checks;
    failures += all.filter((check) => !check.ok).length;

    if (values.json) {
      results.push({ file, name: scene.name, reply, checks: all });
      continue;
    }

    console.log(`\n${scene.name}  ·  ${basename(file)}`);
    if (scene.why) console.log(`  ↳ ${scene.why}`);
    console.log("");
    if (input.message.text) console.log(`  Le voyageur : « ${shorten(input.message.text)} »`);
    else console.log(`  Le voyageur : (${input.message.kind}, sans texte)`);
    console.log("");
    for (const beat of reply.beats) {
      console.log(`  MEMO (${beat.pauseMilliseconds} ms) : ${beat.text}`);
    }
    console.log("");
    console.log(
      `  classement : ${reply.disposition}   puces : ${reply.suggestionIds.join(", ") || "aucune"}`,
    );
    console.log(`  relance : ${reply.prompt ?? "(inchangée)"}`);
    console.log("");
    for (const check of all) {
      const detail = check.detail ? `  — ${check.detail}` : "";
      console.log(`  ${check.ok ? "✓" : "✗"} ${check.label}${detail}`);
    }
    const byHand = [...BY_HAND];
    if (ambiguousVouvoiement.has(file)) {
      byHand.unshift("Le « vous » lu à haute voix : groupe (bon) ou vouvoiement (faute) ?");
    }
    console.log(`  ${byHand.map((item) => `☐ ${item}`).join("\n  ")}`);
    console.log("-".repeat(60));
  }

  if (values.json) {
    console.log(JSON.stringify(results, null, 2));
    return;
  }

  console.log(
    failures === 0
      ? "\nAucun manquement de forme. Le reste se lit — grille § 13.\n"
      : `\n${failures} manquement(s) de forme ci-dessus. Le reste se lit — grille § 13.\n`,
  );
}

function shorten(text: string): string {
  const clean = text.trim().replace(/\s+/g, " ");
  return clean.length > 160 ? `${clean.slice(0, 159)}…` : clean;
}

await main();
