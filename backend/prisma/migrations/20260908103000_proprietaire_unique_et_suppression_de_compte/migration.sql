-- Un carnet a **un** propriétaire, obligatoire, et supprimer un compte emporte
-- tout ce qui est à lui.
--
-- Avant cette migration, « à qui est ce carnet » se lisait à trois endroits :
-- `memos.deviceId` (hérité de l'époque sans comptes), `memos.ownerAccountId`
-- (nullable), et une ligne `memo_members` de rôle `owner`. Trois vérités pour
-- un même fait, dont deux pouvaient diverger sans que rien ne le signale.
-- Il n'en reste qu'une : `memos.ownerAccountId`, NOT NULL, en cascade.

-- 1. Les carnets sans propriétaire prennent celui de leur appareil, quand cet
--    appareil s'est rattaché à un compte. C'est exactement ce que faisait
--    `linkDeviceToAccount` à la connexion.
UPDATE "memos" AS m
SET "ownerAccountId" = d."accountId"
FROM "devices" AS d
WHERE m."deviceId" = d."id"
  AND m."ownerAccountId" IS NULL
  AND d."accountId" IS NOT NULL;

-- 2. Ceux qui restent appartiennent à un appareil qui ne s'est jamais connecté.
--    Personne ne peut plus les revendiquer — l'app exige désormais un compte
--    pour créer un carnet — et les garder ferait échouer le NOT NULL ci-dessous.
--
--    Les commandes partent d'abord : `print_orders.renderId` est en RESTRICT,
--    et la cascade depuis `memos` n'a pas d'ordre garanti entre les deux tables.
DELETE FROM "print_orders"
WHERE "memoId" IN (SELECT "id" FROM "memos" WHERE "ownerAccountId" IS NULL);

DELETE FROM "memos" WHERE "ownerAccountId" IS NULL;

-- 3. La propriété par l'appareil disparaît.
DROP INDEX "memos_deviceId_createdAt_idx";
ALTER TABLE "memos" DROP CONSTRAINT "memos_deviceId_fkey";
ALTER TABLE "memos" DROP COLUMN "deviceId";

-- 4. La propriété par le compte devient obligatoire, et cascade.
ALTER TABLE "memos" ALTER COLUMN "ownerAccountId" SET NOT NULL;
ALTER TABLE "memos" DROP CONSTRAINT "memos_ownerAccountId_fkey";
ALTER TABLE "memos" ADD CONSTRAINT "memos_ownerAccountId_fkey"
  FOREIGN KEY ("ownerAccountId") REFERENCES "accounts"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

-- 5. `memo_members` ne porte plus que des invités.
DELETE FROM "memo_members" WHERE "role" = 'owner';
ALTER TABLE "memo_members" DROP COLUMN "role";
DROP TYPE "MemoRole";

-- 6. Ce qui reste d'un compte supprimé : rien.
--    Un appareil est une trace d'installation, pas un bien à conserver ; un
--    avis est la donnée de la personne qui l'a écrit, pas une statistique
--    qu'on garde en l'anonymisant.
ALTER TABLE "devices" DROP CONSTRAINT "devices_accountId_fkey";
ALTER TABLE "devices" ADD CONSTRAINT "devices_accountId_fkey"
  FOREIGN KEY ("accountId") REFERENCES "accounts"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "feedback_responses" DROP CONSTRAINT "feedback_responses_accountId_fkey";
ALTER TABLE "feedback_responses" ADD CONSTRAINT "feedback_responses_accountId_fkey"
  FOREIGN KEY ("accountId") REFERENCES "accounts"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
