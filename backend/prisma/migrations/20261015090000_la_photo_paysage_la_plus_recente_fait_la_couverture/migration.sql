-- La couverture dont il s'agit est **la carte du voyage**, qui est large : on
-- y veut donc des photos paysage, et non droites comme la migration
-- précédente le supposait (Hugo, 15/10/2026). La couverture *imprimée* du
-- carnet, elle, est verticale — mais elle ne suit pas cette règle.

ALTER INDEX "entries_memoId_photoIsUpright_capturedAt_idx"
  RENAME TO "entries_memoId_photoIsLandscape_capturedAt_idx";

ALTER TABLE "entries" RENAME COLUMN "photoIsUpright" TO "photoIsLandscape";

-- ⚠️ Pas un `NOT` : « droite » valait hauteur ≥ largeur et « paysage » vaut
-- largeur ≥ hauteur, donc un carré est vrai des deux côtés. La valeur se
-- recalcule depuis les dimensions, qui sont la mesure, pas la conclusion.
UPDATE "entries"
  SET "photoIsLandscape" = ("photoWidthPx" >= "photoHeightPx")
  WHERE "photoWidthPx" IS NOT NULL AND "photoHeightPx" IS NOT NULL;

-- Une photo sans dimensions n'a jamais été mesurée : elle ne doit rien affirmer.
UPDATE "entries"
  SET "photoIsLandscape" = NULL
  WHERE "photoWidthPx" IS NULL OR "photoHeightPx" IS NULL;
