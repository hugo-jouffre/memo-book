-- Les notifications APNs — `docs/notifications.md`.
--
-- Trois tables et une colonne :
--
--  1. `push_tokens` — un téléphone qui accepte les notifications. Rattaché à
--     la **session** : se déconnecter supprime la session, donc le jeton.
--  2. `notification_deliveries` — ce qui est parti. `dedupeKey` unique tient
--     le « une seule fois » des règles, `sentAt` les plafonds, `openedAt` le
--     comportement réel qui ajuste le rythme.
--  3. `school_holidays` — le calendrier scolaire du ministère, recopié chaque
--     jour par la tâche `syncSchoolHolidays`. Vide à la migration : la première
--     passe le remplit.
--
-- `accounts.timeZone` : le fuseau du téléphone, pour envoyer à 10 h chez le
-- voyageur et savoir quel jour il est pour lui. Nul pour les comptes existants,
-- qui se rempliront au premier jeton envoyé.

-- CreateEnum
CREATE TYPE "PushEnvironment" AS ENUM ('sandbox', 'production');

-- CreateEnum
CREATE TYPE "NotificationKind" AS ENUM ('trial_end', 'trip_end', 'writing_reminder', 'unordered_book', 'school_holidays', 'learned_period', 'birthday');

-- AlterTable
ALTER TABLE "accounts" ADD COLUMN     "timeZone" TEXT;

-- CreateTable
CREATE TABLE "push_tokens" (
    "id" TEXT NOT NULL,
    "accountId" TEXT NOT NULL,
    "sessionId" TEXT NOT NULL,
    "token" TEXT NOT NULL,
    "environment" "PushEnvironment" NOT NULL,
    "appVersion" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastSeenAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "push_tokens_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "notification_deliveries" (
    "id" TEXT NOT NULL,
    "accountId" TEXT NOT NULL,
    "memoId" TEXT,
    "kind" "NotificationKind" NOT NULL,
    "dedupeKey" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "body" TEXT NOT NULL,
    "link" TEXT,
    "deliveredCount" INTEGER NOT NULL DEFAULT 0,
    "sentAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "openedAt" TIMESTAMP(3),

    CONSTRAINT "notification_deliveries_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "school_holidays" (
    "id" TEXT NOT NULL,
    "zone" TEXT NOT NULL,
    "label" TEXT NOT NULL,
    "schoolYear" TEXT NOT NULL,
    "startsOn" DATE NOT NULL,
    "endsOn" DATE NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "school_holidays_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "push_tokens_token_key" ON "push_tokens"("token");

-- CreateIndex
CREATE INDEX "push_tokens_accountId_idx" ON "push_tokens"("accountId");

-- CreateIndex
CREATE INDEX "push_tokens_sessionId_idx" ON "push_tokens"("sessionId");

-- CreateIndex
CREATE UNIQUE INDEX "notification_deliveries_dedupeKey_key" ON "notification_deliveries"("dedupeKey");

-- CreateIndex
CREATE INDEX "notification_deliveries_accountId_sentAt_idx" ON "notification_deliveries"("accountId", "sentAt");

-- CreateIndex
CREATE INDEX "school_holidays_zone_startsOn_idx" ON "school_holidays"("zone", "startsOn");

-- CreateIndex
CREATE UNIQUE INDEX "school_holidays_zone_label_schoolYear_key" ON "school_holidays"("zone", "label", "schoolYear");

-- AddForeignKey
ALTER TABLE "push_tokens" ADD CONSTRAINT "push_tokens_accountId_fkey" FOREIGN KEY ("accountId") REFERENCES "accounts"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "push_tokens" ADD CONSTRAINT "push_tokens_sessionId_fkey" FOREIGN KEY ("sessionId") REFERENCES "sessions"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notification_deliveries" ADD CONSTRAINT "notification_deliveries_accountId_fkey" FOREIGN KEY ("accountId") REFERENCES "accounts"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notification_deliveries" ADD CONSTRAINT "notification_deliveries_memoId_fkey" FOREIGN KEY ("memoId") REFERENCES "memos"("id") ON DELETE SET NULL ON UPDATE CASCADE;

