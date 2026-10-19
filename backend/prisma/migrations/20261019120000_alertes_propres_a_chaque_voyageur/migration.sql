-- D13 (Hugo, 19/10/2026) : chaque voyageur règle ses propres alertes.
--
-- 1. Les alertes d'un voyage passent de `memos` à une table par (voyage,
--    compte). Elles valaient pour tous les co-voyageurs : un seul qui coupait
--    la relance d'écriture la coupait chez tout le monde.
-- 2. Les notifications du compte (rappel de renouvellement, vacances
--    scolaires, période de l'an dernier, anniversaire) reçoivent chacune un
--    interrupteur, allumé par défaut.
--
-- **Personne ne voit son expérience changer** : les valeurs du voyage sont
-- recopiées pour le propriétaire et pour chaque co-voyageur entré ou invité
-- avec un compte. Seuls les voyages dont une alerte au moins était coupée
-- reçoivent des lignes — pas de ligne, tout est allumé, ce qui était déjà
-- leur état.
--
-- Additive : les colonnes `memos.notify*` et `memos.notificationsEnabled`
-- restent, plus personne ne les lit. L'API en place pendant le déploiement
-- les lit encore ; elles partiront dans une migration à part.

-- AlterTable
ALTER TABLE "accounts" ADD COLUMN "notifyRenewalReminder" BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE "accounts" ADD COLUMN "notifySchoolHolidays" BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE "accounts" ADD COLUMN "notifyLearnedPeriod" BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE "accounts" ADD COLUMN "notifyBirthday" BOOLEAN NOT NULL DEFAULT true;

-- CreateTable
CREATE TABLE "memo_notification_preferences" (
    "memoId" TEXT NOT NULL,
    "accountId" TEXT NOT NULL,
    "notificationsEnabled" BOOLEAN NOT NULL DEFAULT true,
    "notifyWritingReminder" BOOLEAN NOT NULL DEFAULT true,
    "notifyNewStory" BOOLEAN NOT NULL DEFAULT true,
    "notifyWeeklyDigest" BOOLEAN NOT NULL DEFAULT true,
    "notifyTripEnd" BOOLEAN NOT NULL DEFAULT true,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "memo_notification_preferences_pkey" PRIMARY KEY ("memoId","accountId")
);

-- CreateIndex
CREATE INDEX "memo_notification_preferences_accountId_idx" ON "memo_notification_preferences"("accountId");

-- AddForeignKey
ALTER TABLE "memo_notification_preferences" ADD CONSTRAINT "memo_notification_preferences_memoId_fkey" FOREIGN KEY ("memoId") REFERENCES "memos"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "memo_notification_preferences" ADD CONSTRAINT "memo_notification_preferences_accountId_fkey" FOREIGN KEY ("accountId") REFERENCES "accounts"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Les valeurs du voyage, recopiées pour chacun de ses voyageurs.
INSERT INTO "memo_notification_preferences" (
    "memoId", "accountId", "notificationsEnabled", "notifyWritingReminder",
    "notifyNewStory", "notifyWeeklyDigest", "notifyTripEnd", "updatedAt"
)
SELECT
    m."id", travellers."accountId", m."notificationsEnabled", m."notifyWritingReminder",
    m."notifyNewStory", m."notifyWeeklyDigest", m."notifyTripEnd", CURRENT_TIMESTAMP
FROM "memos" m
JOIN (
    SELECT "id" AS "memoId", "ownerAccountId" AS "accountId" FROM "memos"
    UNION
    SELECT "memoId", "accountId" FROM "memo_members"
    WHERE "accountId" IS NOT NULL AND "status" IN ('active', 'invited')
) travellers ON travellers."memoId" = m."id"
WHERE NOT (
    m."notificationsEnabled" AND m."notifyWritingReminder" AND m."notifyNewStory"
    AND m."notifyWeeklyDigest" AND m."notifyTripEnd"
)
ON CONFLICT DO NOTHING;
