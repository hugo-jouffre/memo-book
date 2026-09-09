-- Le code d'accès d'un voyage : six caractères, obligatoires et uniques.
--
-- En trois temps, parce que la colonne est obligatoire et que la table n'est
-- pas vide : on l'ajoute nullable, on donne un code à ce qui existe, puis on
-- ferme. Les codes de rattrapage sont dérivés du **rang** du carnet et non du
-- hasard : uniques par construction, la création de l'index ne peut donc pas
-- échouer sur une collision au milieu d'une migration.

-- AlterTable
ALTER TABLE "memos" ADD COLUMN "accessCode" TEXT;

WITH ranked AS (
    SELECT "id", row_number() OVER (ORDER BY "createdAt", "id") AS n FROM "memos"
)
UPDATE "memos" m
SET "accessCode" = 'MB' || lpad(upper(to_hex(r.n)), 4, '0')
FROM ranked r
WHERE m."id" = r."id";

ALTER TABLE "memos" ALTER COLUMN "accessCode" SET NOT NULL;

-- CreateIndex
CREATE UNIQUE INDEX "memos_accessCode_key" ON "memos"("accessCode");
