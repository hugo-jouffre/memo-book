/**
 * Smoke du pipeline complet, exécutable à la main :
 *
 *   npm run smoke            → tout simulé, aucune clé, aucun appel réseau
 *   npm run smoke -- --live  → OpenAI + APITemplate pour de vrai, affiche l'URL du PDF
 *
 * Utile pour vérifier d'un coup que la chaîne rejoint bien le template
 * `templates/travel-journal/` après un changement de schéma ou de prompt.
 */
import { buildApp } from "../src/app.js";
import { createContext } from "../src/context.js";
import { loadEnv } from "../src/env.js";
import { InlineQueue } from "../src/jobs/queue.js";
import { validatePayload } from "../src/services/payloadValidator.js";

const live = process.argv.includes("--live");

const SCRIPT = [
  {
    capturedAt: "2026-01-03T09:00:00.000Z",
    place: "Bogotá, Colombie",
    text: "On arrive à Bogotá après un vol de nuit. La première claque, c'est l'altitude : chaque marche est un petit défi. On se perd volontairement dans les rues colorées de La Candelaria.",
  },
  {
    capturedAt: "2026-01-04T09:00:00.000Z",
    place: "Monserrate",
    text: "Lever tôt pour monter à Monserrate. Le funiculaire grimpe dans la brume avant de dévoiler toute la ville sous nos pieds.",
  },
  {
    capturedAt: "2026-01-05T09:00:00.000Z",
    place: "Guatapé",
    text: "Guatapé ressemble à une boîte de crayons de couleur renversée. La Piedra del Peñol nous essouffle mais la vue vaut chaque goutte de sueur.",
  },
];

function step(message: string): void {
  process.stdout.write(`\n▸ ${message}\n`);
}

async function main(): Promise<void> {
  const env = loadEnv({
    ...process.env,
    PIPELINE_MODE: live ? "live" : "fake",
    LOG_LEVEL: "warn",
  });

  // File en ligne : chaque étape se termine avant la suivante, ce qui rend la
  // sortie du script lisible de haut en bas.
  const context = createContext(env, { overrides: { queue: new InlineQueue() } });
  const app = await buildApp(context);
  await app.ready();

  step(`Mode : ${env.live ? "LIVE (appels réels)" : "FAKE (aucun appel réseau)"}`);

  try {
    const device = await app.inject({
      method: "POST",
      url: "/v1/devices",
      payload: { platform: "ios" },
    });
    const authorization = `Bearer ${device.json<{ token: string }>().token}`;
    step("Appareil enregistré");

    const memo = await app.inject({
      method: "POST",
      url: "/v1/memos",
      headers: { authorization },
      payload: {
        title: "Claire et Gus en Colombie",
        subtitle: "Un carnet de voyage raconté à l'oral",
        authors: "Claire et Augustin",
        theme: "voyage",
      },
    });
    const memoId = memo.json<{ id: string }>().id;
    step(`Carnet créé : ${memoId}`);

    for (const entry of SCRIPT) {
      // En mode `fake` la transcription est simulée : on envoie donc le texte
      // directement, pour que la matière du carnet soit lisible dans la sortie.
      const response = await app.inject({
        method: "POST",
        url: `/v1/memos/${memoId}/entries`,
        headers: { authorization },
        payload: {
          kind: "text",
          transcript: entry.text,
          capturedAt: entry.capturedAt,
          placeLabel: entry.place,
        },
      });

      if (response.statusCode !== 201) {
        throw new Error(`Entrée refusée (${response.statusCode}) : ${response.body}`);
      }
      step(`Souvenir ajouté — ${entry.place}`);
    }

    const render = await app.inject({
      method: "POST",
      url: `/v1/memos/${memoId}/renders`,
      headers: { authorization },
    });

    const body = render.json<{ id: string; status: string; pdfUrl: string | null; error: string | null }>();

    if (body.status !== "ready") {
      throw new Error(`Génération en échec : ${body.error ?? "raison inconnue"}`);
    }

    const stored = await context.prisma.render.findUniqueOrThrow({
      where: { id: body.id },
    });
    const validation = validatePayload(stored.payload);
    const payload = stored.payload as { days?: unknown[] };

    step("Carnet généré");
    process.stdout.write(
      [
        `  journées      : ${payload.days?.length ?? 0}`,
        `  payload valide: ${validation.valid ? "oui" : "NON"}`,
        `  avertissements: ${validation.warnings.length}`,
        `  PDF           : ${body.pdfUrl ?? "—"}`,
        "",
      ].join("\n"),
    );

    for (const warning of validation.warnings) {
      process.stdout.write(`  ⚠ ${warning.path} — ${warning.message}\n`);
    }

    if (!validation.valid) {
      for (const issue of validation.errors) {
        process.stderr.write(`  ✗ ${issue.path} — ${issue.message}\n`);
      }
      throw new Error("Le payload généré ne respecte pas le schéma du template.");
    }

    process.stdout.write("\n✅ Pipeline complet OK\n");
  } finally {
    await app.close();
    await context.prisma.$disconnect();
  }
}

main().catch((error: unknown) => {
  process.stderr.write(`\n❌ ${error instanceof Error ? error.message : String(error)}\n`);
  process.exit(1);
});
