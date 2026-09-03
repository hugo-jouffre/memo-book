import { existsSync } from "node:fs";
import { defineConfig } from "vitest/config";

// Les tests reçoivent une configuration explicite (`testEnv`), mais elle va
// chercher `DATABASE_URL` dans l'environnement : sans ça, la suite viserait la
// base locale par défaut plutôt que celle qui est réellement configurée.
if (existsSync(".env")) process.loadEnvFile(".env");

export default defineConfig({
  test: {
    environment: "node",
    include: ["src/**/*.test.ts", "test/**/*.test.ts"],
    // Le pipeline partage une base : les suites tournent en série pour éviter
    // que deux tests se marchent dessus sur les mêmes tables.
    fileParallelism: false,
    // La base est distante (Supabase) : chaque aller-retour coûte des dizaines
    // de millisecondes au lieu d'une fraction, et un test du pipeline en fait
    // des centaines. Les 5 s par défaut de Vitest étaient calibrées pour un
    // Postgres local.
    testTimeout: 30_000,
    hookTimeout: 30_000,
  },
});
