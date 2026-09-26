-- La date de naissance, demandée à la fin de l'onboarding (« Ta Date de
-- Naissance »). Un jour et non un instant : `DATE`, sans heure ni fuseau.
--
-- Nullable : les comptes déjà ouverts ne l'ont jamais donnée, et l'écran qui
-- la demande se passe. Rien à remplir, rien à deviner.

-- AlterTable
ALTER TABLE "accounts" ADD COLUMN     "birthDate" DATE;
