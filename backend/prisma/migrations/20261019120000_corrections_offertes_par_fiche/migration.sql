-- Une fiche offre 200 caractères de correction au clavier, cumulés (Hugo,
-- 19/10/2026, QA D8) : pot vide, on corrige encore un nom propre ou une
-- phrase ; au-delà, la correction paie comme un texte, ou attend l'illimité.
-- Le compteur dit ce qui a déjà été offert à la fiche.
--
-- Additive : une colonne avec une valeur par défaut, rien de retiré.

-- AlterTable
ALTER TABLE "entries" ADD COLUMN "correctionFreeCharacters" INTEGER NOT NULL DEFAULT 0;
