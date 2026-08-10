// @ts-check
import eslint from "@eslint/js";
import tseslint from "typescript-eslint";

export default tseslint.config(
  { ignores: ["dist/**", "node_modules/**", "prisma/migrations/**"] },
  eslint.configs.recommended,
  ...tseslint.configs.recommendedTypeChecked,
  {
    languageOptions: {
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      "@typescript-eslint/no-unused-vars": [
        "error",
        { argsIgnorePattern: "^_", varsIgnorePattern: "^_" },
      ],
      // Les implémentations simulées (`FakeTranscriber`, `InlineQueue`,
      // `FakeBookRenderer`…) sont `async` parce que leur interface l'exige, pas
      // parce qu'elles attendent quelque chose. Retirer le mot-clé casserait la
      // conformité ; la règle est donc inadaptée à ce code.
      "@typescript-eslint/require-await": "off",
    },
  },
);
