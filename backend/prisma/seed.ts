import { PrismaClient } from "@prisma/client";
import { generateToken, hashToken } from "../src/lib/auth.js";

/**
 * Jeu de données de développement : un appareil, un carnet et trois souvenirs
 * écrits. Le token est affiché en clair — il ne l'est qu'ici — pour pouvoir
 * enchaîner directement avec curl.
 */
const prisma = new PrismaClient();

const SOUVENIRS = [
  {
    capturedAt: new Date("2026-01-03T09:00:00Z"),
    placeLabel: "Bogotá, Colombie",
    transcript:
      "On arrive à Bogotá après un vol de nuit. La première claque, c'est l'altitude : chaque marche est un petit défi. On se perd volontairement dans les rues colorées de La Candelaria.",
  },
  {
    capturedAt: new Date("2026-01-04T09:00:00Z"),
    placeLabel: "Monserrate",
    transcript:
      "Lever tôt pour monter à Monserrate. Le funiculaire grimpe dans la brume avant de dévoiler toute la ville sous nos pieds.",
  },
  {
    capturedAt: new Date("2026-01-05T09:00:00Z"),
    placeLabel: "Guatapé",
    transcript:
      "Guatapé ressemble à une boîte de crayons de couleur renversée. La Piedra del Peñol nous essouffle mais la vue vaut chaque goutte de sueur.",
  },
];

async function main(): Promise<void> {
  const token = generateToken();

  const device = await prisma.device.create({
    data: { tokenHash: hashToken(token), platform: "ios" },
  });

  const memo = await prisma.memo.create({
    data: {
      deviceId: device.id,
      title: "Claire et Gus en Colombie",
      subtitle: "Un carnet de voyage raconté à l'oral",
      authors: "Claire et Augustin",
      theme: "voyage",
      startDate: SOUVENIRS[0]?.capturedAt,
      endDate: SOUVENIRS.at(-1)?.capturedAt,
      entries: {
        create: SOUVENIRS.map((souvenir) => ({
          kind: "text" as const,
          status: "ready" as const,
          ...souvenir,
        })),
      },
    },
  });

  process.stdout.write(
    [
      "",
      "Jeu de données de développement créé.",
      "",
      `  Carnet : ${memo.id}`,
      `  Token  : ${token}`,
      "",
      "  Essai rapide :",
      `    curl -H "Authorization: Bearer ${token}" http://localhost:3000/v1/memos`,
      `    curl -X POST -H "Authorization: Bearer ${token}" http://localhost:3000/v1/memos/${memo.id}/renders`,
      "",
    ].join("\n"),
  );
}

main()
  .catch((error: unknown) => {
    console.error(error);
    process.exit(1);
  })
  .finally(() => void prisma.$disconnect());
