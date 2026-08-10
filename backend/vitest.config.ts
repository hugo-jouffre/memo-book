import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "node",
    include: ["src/**/*.test.ts", "test/**/*.test.ts"],
    // Le pipeline partage une base : les suites tournent en série pour éviter
    // que deux tests se marchent dessus sur les mêmes tables.
    fileParallelism: false,
  },
});
