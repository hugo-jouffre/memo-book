#!/usr/bin/env tsx
/**
 * Faire rédiger un voyage entier, et relire ce qui en sort.
 *
 *   npm run redaction:eval -- --label avant          rédige toutes les étapes, garde le rapport
 *   npm run redaction:eval -- --until 13             s'arrête à l'étape dont l'id contient « 13 »
 *   npm run redaction:eval -- --model claude-opus-5-5
 *   npm run redaction:eval -- --compare avant après  les deux rapports côte à côte
 *   npm run redaction:eval -- --compare avant après --judge
 *                                                    … et un relecteur qui note chaque texte
 *
 * La rédaction se juge sur un **voyage**, pas sur un vocal : la fiche de
 * cohérence et les étapes déjà écrites passent d'une étape à la suivante,
 * exactement comme dans le job `redact`. Une étape se rédige donc toujours
 * après les précédentes, jamais seule.
 *
 * Comme `conversation:eval`, **ce n'est pas un test** : le modèle n'entre pas
 * en CI. Une machine ne rattrape ici que la forme — longueurs du barème,
 * tournures proscrites. Le fond se lit, et chaque étape de la scène rappelle
 * ses pièges (`watch`) : c'est sur eux qu'on juge si l'écrivain a compris ce
 * que le voyageur voulait dire.
 *
 * Rien n'est écrit en base. Les rapports vont dans `.redaction-eval/`.
 */
import Anthropic from "@anthropic-ai/sdk";
import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { loadWritingRules } from "../src/lib/templates.js";
import { STEP_SIZES } from "../src/services/payloadValidator.js";
import {
  AnthropicRedactor,
  EMPTY_COHERENCE_SHEET,
  type CoherenceSheet,
  type RedactedNeighbour,
  type RedactionInput,
  type RedactionResult,
} from "../src/services/redaction.js";

const here = dirname(fileURLToPath(import.meta.url));
const SCENE_PATH = resolve(here, "../test/fixtures/redaction/grece-maxime.json");
const OUT_DIR = resolve(here, "../.redaction-eval");

const { values, positionals } = parseArgs({
  allowPositionals: true,
  options: {
    label: { type: "string" },
    until: { type: "string" },
    scene: { type: "string", default: SCENE_PATH },
    model: { type: "string", default: process.env.ANTHROPIC_REDACTION_MODEL ?? "claude-opus-5" },
    compare: { type: "boolean", default: false },
    judge: { type: "boolean", default: false },
    "judge-model": { type: "string", default: "claude-opus-5-5" },
  },
});

// ---------------------------------------------------------------------------
// La scène
// ---------------------------------------------------------------------------

interface SceneStep {
  id: string;
  recordedAt: string;
  place: string | null;
  transcript: string;
  watch: string[];
}

interface Scene {
  name: string;
  why?: string;
  memo: {
    title: string;
    startDate?: string | null;
    endDate?: string | null;
    destination?: string | null;
    narrationPace?: string | null;
    tripContext?: string[];
  };
  narrator: { firstName: string | null; companions: string[] };
  steps: SceneStep[];
}

interface StepReport {
  id: string;
  transcript: string;
  watch: string[];
  result: RedactionResult | null;
  error: string | null;
  milliseconds: number;
  checks: string[];
}

interface RunReport {
  label: string;
  scene: string;
  model: string;
  rulesHash: string;
  date: string;
  steps: StepReport[];
}

function dayOrNull(value: string | null | undefined): Date | null {
  return value ? new Date(`${value}T12:00:00Z`) : null;
}

// ---------------------------------------------------------------------------
// Ce qu'une machine sait vérifier
// ---------------------------------------------------------------------------

/** Les tournures que § 7 proscrit et qu'un texte dicté laisse passer le plus souvent. */
const PROSCRIBED = [
  /\bdu coup\b/i,
  /\ben fait\b/i,
  /\bpar contre\b/i,
  /\bvu que\b/i,
  /\bau final\b/i,
  /\bdes fois\b/i,
  /\bgenre\b/i,
  /\bune après-midi\b/i,
  /\bon (?:a|est allés?) manger\b(?! (?:un|une|des|du|de la|le|la|les)\b)/i,
];

function checksOf(result: RedactionResult): string[] {
  const findings: string[] = [];
  const paragraphs = result.text.split(/\n\s*\n/).map((paragraph) => paragraph.trim()).filter(Boolean);
  const total = paragraphs.join(" ").length;

  const size = (Object.entries(STEP_SIZES) as [string, { min: number; max: number }][]).find(
    ([, range]) => total >= range.min && total <= range.max,
  );
  findings.push(`${total} caractères, ${paragraphs.length} paragraphe(s) — ${size ? size[0] : "hors barème"}`);

  for (const [index, paragraph] of paragraphs.entries()) {
    if (paragraph.length > STEP_SIZES.S.max) {
      findings.push(`⚠️ paragraphe ${index + 1} : ${paragraph.length} caractères (plafond ${STEP_SIZES.S.max})`);
    }
  }
  for (const pattern of PROSCRIBED) {
    const match = result.text.match(pattern);
    if (match) findings.push(`⚠️ tournure proscrite : « ${match[0]} »`);
  }
  if (result.funFact && result.funFact.length > 140) {
    findings.push(`⚠️ encart de ${result.funFact.length} caractères (plafond 140)`);
  }
  return findings;
}

// ---------------------------------------------------------------------------
// Rédiger le voyage
// ---------------------------------------------------------------------------

async function run(client: Anthropic): Promise<RunReport> {
  const scene = JSON.parse(await readFile(values.scene, "utf8")) as Scene;
  const redactor = new AnthropicRedactor(client, values.model);

  let sheet: CoherenceSheet = EMPTY_COHERENCE_SHEET;
  const previous: RedactedNeighbour[] = [];
  const titles: string[] = [];
  const funFacts: string[] = [];
  const steps: StepReport[] = [];

  const lastIndex = values.until
    ? scene.steps.findIndex((step) => step.id.includes(values.until!))
    : scene.steps.length - 1;
  if (lastIndex < 0) throw new Error(`Aucune étape ne contient « ${values.until} ».`);

  for (const step of scene.steps.slice(0, lastIndex + 1)) {
    const input: RedactionInput = {
      memo: {
        title: scene.memo.title,
        subtitle: null,
        authors: null,
        theme: null,
        styleKey: null,
        tripContext: scene.memo.tripContext ?? [],
        startDate: dayOrNull(scene.memo.startDate),
        endDate: dayOrNull(scene.memo.endDate),
        destination: scene.memo.destination ?? null,
        narrationPace: scene.memo.narrationPace ?? null,
      },
      narrator: scene.narrator,
      entry: {
        transcript: step.transcript,
        capturedAt: new Date(step.recordedAt),
        placeLabel: step.place,
        precisions: [],
        step: null,
      },
      coherenceSheet: sheet,
      previous: previous.slice(-3),
      earlier: { titles: [...titles], funFacts: [...funFacts] },
    };

    process.stderr.write(`→ ${step.id}… `);
    const started = Date.now();
    try {
      const result = await redactor.redact(input);
      const milliseconds = Date.now() - started;
      process.stderr.write(`${Math.round(milliseconds / 1000)} s\n`);
      steps.push({ ...step, result, error: null, milliseconds, checks: checksOf(result) });

      sheet = result.coherenceSheet;
      previous.push({ capturedAt: new Date(step.recordedAt), placeLabel: step.place, title: result.title, text: result.text });
      titles.push(result.title);
      if (result.funFact) funFacts.push(result.funFact);
    } catch (cause) {
      const message = cause instanceof Error ? cause.message : String(cause);
      process.stderr.write(`échec : ${message}\n`);
      steps.push({ ...step, result: null, error: message, milliseconds: Date.now() - started, checks: [] });
    }
  }

  return {
    label: values.label ?? new Date().toISOString().replace(/[:.]/g, "-"),
    scene: scene.name,
    model: values.model,
    rulesHash: createHash("sha256").update(loadWritingRules()).digest("hex").slice(0, 10),
    date: new Date().toISOString(),
    steps,
  };
}

function runToMarkdown(report: RunReport): string {
  const lines = [
    `# ${report.scene} — ${report.label}`,
    "",
    `Modèle : \`${report.model}\` · règles \`${report.rulesHash}\` · ${report.date}`,
  ];
  for (const step of report.steps) {
    lines.push("", `## ${step.id}${step.result ? ` — ${step.result.title}` : ""}`, "");
    if (!step.result) {
      lines.push(`**Échec** : ${step.error}`);
      continue;
    }
    lines.push(step.result.text, "");
    if (step.result.funFact) lines.push(`> ${step.result.funFactTitle ?? "Fun fact"} — ${step.result.funFact}`, "");
    if (step.result.doubts && step.result.doubts.length > 0) {
      lines.push(`Doutes : ${step.result.doubts.map((doubt) => `« ${doubt} »`).join(", ")}`, "");
    }
    lines.push(...step.checks.map((check) => `- ${check}`));
  }
  return lines.join("\n");
}

// ---------------------------------------------------------------------------
// Comparer deux rapports — et, sur demande, les faire relire
// ---------------------------------------------------------------------------

const CRITERIA = ["intention", "fluidite", "fidelite", "voix", "francais"] as const;
type Criterion = (typeof CRITERIA)[number];

interface Verdict {
  scores: Record<Criterion, number>;
  traps: { trap: string; verdict: "évité" | "raté" | "sans objet"; note: string }[];
  defects: string[];
}

const VERDICT_SCHEMA = {
  type: "object",
  properties: {
    scores: {
      type: "object",
      properties: Object.fromEntries(CRITERIA.map((criterion) => [criterion, { type: "integer" }])),
      required: [...CRITERIA],
      additionalProperties: false,
    },
    traps: {
      type: "array",
      items: {
        type: "object",
        properties: {
          trap: { type: "string" },
          verdict: { type: "string", enum: ["évité", "raté", "sans objet"] },
          note: { type: "string" },
        },
        required: ["trap", "verdict", "note"],
        additionalProperties: false,
      },
    },
    defects: { type: "array", items: { type: "string" } },
  },
  required: ["scores", "traps", "defects"],
  additionalProperties: false,
} as const;

const JUDGE_SYSTEM = [
  "Tu es le relecteur éditorial de MemoBook, un carnet de voyage imprimé écrit à partir des vocaux",
  "du voyageur. On te donne la transcription brute d'un vocal, les pièges connus de ce vocal, et le",
  "texte qu'un écrivain en a tiré. Tu juges ce texte comme le voyageur le lirait dans son livre.",
  "",
  "Note chaque critère de 1 à 5, sans complaisance — 5 veut dire « rien à reprendre » :",
  "- intention : le texte a-t-il compris ce que le voyageur voulait dire et faire ressentir ? Le cœur",
  "  de la journée est-il au centre ? Les blagues restent-elles des blagues ? Aucun contresens ?",
  "- fluidite : se lit-il d'une traite, sans phrase qui demande une seconde lecture, sans liste",
  "  mécanique, avec des enchaînements naturels ?",
  "- fidelite : rien d'inventé (détail, émotion, lieu, personne) et rien de trahi ?",
  "- voix : sonne-t-il comme ce voyageur-là, ses mots et son registre, sans être lissé ni singé ?",
  "- francais : grammaire, usage, typographie d'un livre ?",
  "",
  "Pour chaque piège, dis s'il est évité, raté, ou sans objet, en une phrase. Puis liste les défauts",
  "précis du texte, chacun avec la phrase fautive entre guillemets. Tu réponds uniquement par l'objet",
  "JSON demandé.",
].join("\n");

async function judge(client: Anthropic, step: StepReport): Promise<Verdict | null> {
  if (!step.result) return null;
  const response = await client.messages.create({
    model: values["judge-model"],
    max_tokens: 8_000,
    thinking: { type: "adaptive" },
    output_config: { effort: "high", format: { type: "json_schema", schema: VERDICT_SCHEMA } },
    system: JUDGE_SYSTEM,
    messages: [
      {
        role: "user",
        content: [
          "## Transcription brute",
          step.transcript,
          "",
          "## Pièges connus",
          ...step.watch.map((trap) => `- ${trap}`),
          "",
          "## Le texte rédigé",
          `Titre : ${step.result.title}`,
          "",
          step.result.text,
        ].join("\n"),
      },
    ],
  });
  const text = response.content.find((block) => block.type === "text")?.text;
  return text ? (JSON.parse(text) as Verdict) : null;
}

async function loadReport(name: string): Promise<RunReport> {
  const path = name.endsWith(".json") ? resolve(name) : resolve(OUT_DIR, `${name}.json`);
  return JSON.parse(await readFile(path, "utf8")) as RunReport;
}

function average(verdicts: (Verdict | null)[], criterion: Criterion): string {
  const scores = verdicts.flatMap((verdict) => (verdict ? [verdict.scores[criterion]] : []));
  return scores.length === 0 ? "—" : (scores.reduce((sum, score) => sum + score, 0) / scores.length).toFixed(1);
}

async function compare(client: Anthropic): Promise<string> {
  const [left, right] = positionals;
  if (!left || !right) throw new Error("--compare attend deux rapports : --compare avant après");
  const [a, b] = await Promise.all([loadReport(left), loadReport(right)]);
  // Les pièges se relisent dans la scène d'aujourd'hui : un piège précisé
  // depuis le premier rapport vaut pour les deux textes.
  const scene = JSON.parse(await readFile(values.scene, "utf8")) as Scene;
  const watchOf = (step: StepReport) => scene.steps.find((candidate) => candidate.id === step.id)?.watch ?? step.watch;

  const lines = [`# ${a.label} → ${b.label}`, "", `${a.scene}`, ""];
  const verdictsA: (Verdict | null)[] = [];
  const verdictsB: (Verdict | null)[] = [];
  const stepLines: string[] = [];

  for (const stepA of a.steps) {
    const stepB = b.steps.find((candidate) => candidate.id === stepA.id);
    if (!stepB) continue;
    process.stderr.write(`→ ${stepA.id}${values.judge ? " (relecture)" : ""}…\n`);
    const watch = watchOf(stepA);
    const [verdictA, verdictB] = values.judge
      ? await Promise.all([judge(client, { ...stepA, watch }), judge(client, { ...stepB, watch })])
      : [null, null];
    verdictsA.push(verdictA);
    verdictsB.push(verdictB);

    stepLines.push("", `## ${stepA.id}`, "", "**Pièges**", ...watch.map((trap) => `- ${trap}`));
    for (const [label, step, verdict] of [
      [a.label, stepA, verdictA],
      [b.label, stepB, verdictB],
    ] as const) {
      stepLines.push("", `### ${label}${step.result ? ` — ${step.result.title}` : ""}`, "");
      stepLines.push(step.result ? step.result.text : `**Échec** : ${step.error}`);
      if (step.result?.doubts && step.result.doubts.length > 0) {
        stepLines.push("", `Doutes : ${step.result.doubts.map((doubt) => `« ${doubt} »`).join(", ")}`);
      }
      stepLines.push("", ...step.checks.map((check) => `- ${check}`));
      if (verdict) {
        stepLines.push(
          "",
          `Notes : ${CRITERIA.map((criterion) => `${criterion} ${verdict.scores[criterion]}`).join(" · ")}`,
          ...verdict.traps.map((trap) => `- ${trap.verdict === "raté" ? "❌" : trap.verdict === "évité" ? "✅" : "·"} ${trap.trap} — ${trap.note}`),
          ...verdict.defects.map((defect) => `- défaut : ${defect}`),
        );
      }
    }
  }

  if (values.judge) {
    lines.push(
      "| Critère | " + `${a.label} | ${b.label} |`,
      "|---|---|---|",
      ...CRITERIA.map((criterion) => `| ${criterion} | ${average(verdictsA, criterion)} | ${average(verdictsB, criterion)} |`),
      "",
    );
    const missed = (verdicts: (Verdict | null)[]) =>
      verdicts.flatMap((verdict) => verdict?.traps ?? []).filter((trap) => trap.verdict === "raté").length;
    lines.push(`Pièges ratés : ${a.label} ${missed(verdictsA)} · ${b.label} ${missed(verdictsB)}`, "");
  }

  return [...lines, ...stepLines].join("\n");
}

// ---------------------------------------------------------------------------

async function main(): Promise<void> {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) throw new Error("ANTHROPIC_API_KEY manque : la rédaction ne se rejoue qu'avec le vrai modèle.");
  const client = new Anthropic({ apiKey });
  await mkdir(OUT_DIR, { recursive: true });

  if (values.compare) {
    const markdown = await compare(client);
    const name = `${positionals[0]}-vs-${positionals[1]}${values.judge ? "-relu" : ""}`.replace(/[^\w.-]+/g, "_");
    await writeFile(resolve(OUT_DIR, `${name}.md`), markdown);
    process.stdout.write(`${markdown}\n`);
    process.stderr.write(`\nRapport : .redaction-eval/${name}.md\n`);
    return;
  }

  const report = await run(client);
  await writeFile(resolve(OUT_DIR, `${report.label}.json`), JSON.stringify(report, null, 2));
  const markdown = runToMarkdown(report);
  await writeFile(resolve(OUT_DIR, `${report.label}.md`), markdown);
  process.stdout.write(`${markdown}\n`);
  process.stderr.write(`\nRapport : .redaction-eval/${report.label}.md\n`);
}

main().catch((cause) => {
  process.stderr.write(`${cause instanceof Error ? cause.message : String(cause)}\n`);
  process.exit(1);
});
