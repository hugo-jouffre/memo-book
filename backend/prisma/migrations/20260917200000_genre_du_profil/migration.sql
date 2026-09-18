-- Le genre déclaré depuis le profil — femme, homme, ou « je ne préfère pas
-- répondre » (Hugo, 17/09/2026, T76).
--
-- **Nul tant que la personne n'a rien dit.** L'app accorde alors sur ce que le
-- prénom laisse deviner (`services/genderInference.ts`), et le profil permet de
-- corriger. `undisclosed` est un choix, distinct du nul : l'un dit « je ne
-- réponds pas », l'autre « on n'a pas demandé ».
CREATE TYPE "Gender" AS ENUM ('female', 'male', 'undisclosed');

ALTER TABLE "accounts" ADD COLUMN "gender" "Gender";
