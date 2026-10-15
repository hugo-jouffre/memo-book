-- Le nombre de pages cible se change deux fois au plus par voyage (Hugo,
-- 15/10/2026) : chaque changement ouvre la réécriture des étapes déjà écrites,
-- donc un passage de tout le carnet par l'IA. Le compteur ne bouge qu'une fois
-- une étape écrite ; le drapeau dit qu'une réécriture reste à prendre.
--
-- Additive : deux colonnes avec une valeur par défaut, rien de retiré.

-- AlterTable
ALTER TABLE "memos" ADD COLUMN "pageTargetChanges" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "memos" ADD COLUMN "pageTargetRewriteAvailable" BOOLEAN NOT NULL DEFAULT false;
