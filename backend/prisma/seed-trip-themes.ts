import { PrismaClient } from "@prisma/client";
import { seedTripThemes } from "./tripThemes.js";

/**
 * Pose **uniquement** les thèmes de voyage — `npm run db:seed:themes`.
 *
 * Le seed complet (`npm run db:seed`) refait à neuf les carnets des comptes de
 * test ; ce n'est pas ce qu'on veut quand on ajoute une ligne à une table de
 * référence sur une base où quelqu'un travaille. Ce script ne touche qu'à
 * `trip_themes`.
 */
const prisma = new PrismaClient();

seedTripThemes(prisma)
  .then((count) => {
    console.log(`✓ ${count} thèmes de voyage en place.`);
  })
  .catch((error: unknown) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
