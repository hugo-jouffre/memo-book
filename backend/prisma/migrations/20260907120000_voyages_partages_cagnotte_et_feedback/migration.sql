-- Voyages partagés, cagnotte, personnalisations et demandes d'avis.
--
-- Quatre choses, dans cette migration :
--
--  1. Un carnet appartient à un **compte** (`memos.ownerAccountId`) et non plus
--     seulement à un appareil, et `memo_members` dit qui d'autre y participe.
--     Un compte peut être propriétaire du sien et invité dans plusieurs autres.
--  2. La cagnotte devient un **registre en ajout seul** (`wallet_entries`),
--     en centimes entiers, dont `accounts.walletBalanceCents` n'est que le
--     cache. `stripeEventId` est unique : un webhook rejoué ne crédite pas
--     deux fois.
--  3. Les personnalisations du carnet rejoignent `memos` — un jeu par voyage,
--     toujours lu avec lui.
--  4. Les demandes d'avis (`feedback_*`) et les mises en avant (`showcases`)
--     se pilotent depuis la base, sans livrer de version de l'app.

-- CreateEnum
CREATE TYPE "MemoRole" AS ENUM ('owner', 'guest');

-- CreateEnum
CREATE TYPE "MemoMemberStatus" AS ENUM ('invited', 'active', 'removed');

-- CreateEnum
CREATE TYPE "TripStage" AS ENUM ('upcoming', 'ongoing', 'past');

-- CreateEnum
CREATE TYPE "TripTransport" AS ENUM ('walk', 'bike', 'car', 'bus', 'train', 'boat', 'plane');

-- CreateEnum
CREATE TYPE "PhotoVerdict" AS ENUM ('ok', 'upscale', 'downgrade', 'reject');

-- CreateEnum
CREATE TYPE "TapeCorner" AS ENUM ('top_left', 'top_right', 'bottom_left', 'bottom_right');

-- CreateEnum
CREATE TYPE "WalletEntryKind" AS ENUM ('topup', 'refund', 'order_payment', 'gift', 'adjustment');

-- CreateEnum
CREATE TYPE "SubscriptionProvider" AS ENUM ('storekit', 'stripe');

-- CreateEnum
CREATE TYPE "SubscriptionStatus" AS ENUM ('trialing', 'active', 'past_due', 'cancelled', 'expired');

-- CreateEnum
CREATE TYPE "ExpenseSource" AS ENUM ('manual', 'tricount');

-- CreateEnum
CREATE TYPE "FeedbackQuestionKind" AS ENUM ('text', 'choice', 'slider', 'rating');

-- AlterTable
ALTER TABLE "accounts" ADD COLUMN     "addressCity" TEXT,
ADD COLUMN     "addressCountry" TEXT,
ADD COLUMN     "addressLine1" TEXT,
ADD COLUMN     "addressLine2" TEXT,
ADD COLUMN     "addressPostalCode" TEXT,
ADD COLUMN     "avatarUrl" TEXT,
ADD COLUMN     "offeredSteps" INTEGER,
ADD COLUMN     "phoneNumber" TEXT,
ADD COLUMN     "remainingSteps" INTEGER,
ADD COLUMN     "stripeCustomerId" TEXT,
ADD COLUMN     "walletBalanceCents" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "wantsNewsletter" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "welcomeScreenSeenAt" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "memos" ADD COLUMN     "coverBack" JSONB,
ADD COLUMN     "coverFront" JSONB,
ADD COLUMN     "crosswordEnabled" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "dayCount" INTEGER,
ADD COLUMN     "decorationQuota" INTEGER NOT NULL DEFAULT 2,
ADD COLUMN     "destinationCountryCode" TEXT,
ADD COLUMN     "destinationName" TEXT,
ADD COLUMN     "distanceKilometres" DOUBLE PRECISION,
ADD COLUMN     "fontDisplay" TEXT NOT NULL DEFAULT 'Playfair Display',
ADD COLUMN     "fontFacts" TEXT NOT NULL DEFAULT 'Playfair Display',
ADD COLUMN     "fontHand" TEXT NOT NULL DEFAULT 'Gloria Hallelujah',
ADD COLUMN     "fontTitle" TEXT NOT NULL DEFAULT 'Hansley',
ADD COLUMN     "freeZonesEnabled" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "funFactsEnabled" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "isPrintable" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "isPublicGallery" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "memoryCount" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "narrationPace" TEXT,
ADD COLUMN     "ownerAccountId" TEXT,
ADD COLUMN     "pageCount" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "photoCount" INTEGER,
ADD COLUMN     "photoTextRatio" INTEGER NOT NULL DEFAULT 50,
ADD COLUMN     "prompt" TEXT,
ADD COLUMN     "quizEnabled" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "rulesEnabled" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "stage" "TripStage" NOT NULL DEFAULT 'ongoing',
ADD COLUMN     "targetPageCount" INTEGER NOT NULL DEFAULT 60;

-- AlterTable
ALTER TABLE "entries" ADD COLUMN     "enhancedAt" TIMESTAMP(3),
ADD COLUMN     "focusX" DOUBLE PRECISION,
ADD COLUMN     "focusY" DOUBLE PRECISION,
ADD COLUMN     "photoExposure" DOUBLE PRECISION,
ADD COLUMN     "photoHeightPx" INTEGER,
ADD COLUMN     "photoSharpness" DOUBLE PRECISION,
ADD COLUMN     "photoVerdict" "PhotoVerdict",
ADD COLUMN     "photoWidthPx" INTEGER,
ADD COLUMN     "quizAnswerIndex" INTEGER,
ADD COLUMN     "quizAnswers" JSONB,
ADD COLUMN     "quizQuestion" TEXT,
ADD COLUMN     "stepId" TEXT,
ADD COLUMN     "tapeCorner" "TapeCorner";

-- AlterTable
ALTER TABLE "media_assets" ADD COLUMN     "originalStorageKey" TEXT;

-- AlterTable
ALTER TABLE "print_orders" ADD COLUMN     "amountCents" INTEGER,
ADD COLUMN     "carrier" TEXT,
ADD COLUMN     "coverImageUrl" TEXT,
ADD COLUMN     "deliveredAt" TIMESTAMP(3),
ADD COLUMN     "estimatedMaxDays" INTEGER,
ADD COLUMN     "estimatedMinDays" INTEGER,
ADD COLUMN     "pageCount" INTEGER,
ADD COLUMN     "shippedAt" TIMESTAMP(3),
ADD COLUMN     "stripePaymentIntentId" TEXT,
ADD COLUMN     "submittedAt" TIMESTAMP(3);

-- CreateTable
CREATE TABLE "memo_members" (
    "id" TEXT NOT NULL,
    "memoId" TEXT NOT NULL,
    "accountId" TEXT,
    "invitedEmail" TEXT,
    "role" "MemoRole" NOT NULL DEFAULT 'guest',
    "status" "MemoMemberStatus" NOT NULL DEFAULT 'invited',
    "displayName" TEXT,
    "handle" TEXT,
    "invitedByAccountId" TEXT,
    "invitedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "acceptedAt" TIMESTAMP(3),

    CONSTRAINT "memo_members_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "memo_steps" (
    "id" TEXT NOT NULL,
    "memoId" TEXT NOT NULL,
    "number" INTEGER NOT NULL,
    "placeName" TEXT,
    "destinationName" TEXT,
    "destinationCountryCode" TEXT,
    "startDate" TIMESTAMP(3),
    "endDate" TIMESTAMP(3),
    "photoUrl" TEXT,
    "transport" "TripTransport",
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "memo_steps_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "expenses" (
    "id" TEXT NOT NULL,
    "memoId" TEXT NOT NULL,
    "amountCents" INTEGER NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'EUR',
    "label" TEXT,
    "occurredAt" TIMESTAMP(3) NOT NULL,
    "placeLabel" TEXT,
    "source" "ExpenseSource" NOT NULL DEFAULT 'manual',
    "externalId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "expenses_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "wallet_entries" (
    "id" TEXT NOT NULL,
    "accountId" TEXT NOT NULL,
    "amountCents" INTEGER NOT NULL,
    "balanceAfterCents" INTEGER NOT NULL,
    "kind" "WalletEntryKind" NOT NULL,
    "label" TEXT,
    "stripeEventId" TEXT,
    "printOrderId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "wallet_entries_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "payment_cards" (
    "id" TEXT NOT NULL,
    "accountId" TEXT NOT NULL,
    "label" TEXT,
    "last4" TEXT NOT NULL,
    "brand" TEXT,
    "expMonth" INTEGER,
    "expYear" INTEGER,
    "stripePaymentMethodId" TEXT NOT NULL,
    "isDefault" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "payment_cards_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "subscriptions" (
    "id" TEXT NOT NULL,
    "accountId" TEXT NOT NULL,
    "provider" "SubscriptionProvider" NOT NULL,
    "status" "SubscriptionStatus" NOT NULL DEFAULT 'active',
    "priceCents" INTEGER NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'EUR',
    "interval" TEXT NOT NULL DEFAULT 'week',
    "providerSubscriptionId" TEXT,
    "startedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "renewsAt" TIMESTAMP(3),
    "cancelledAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "subscriptions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "account_connectors" (
    "id" TEXT NOT NULL,
    "accountId" TEXT NOT NULL,
    "connectorKey" TEXT NOT NULL,
    "isEnabled" BOOLEAN NOT NULL DEFAULT false,
    "accessToken" TEXT,
    "refreshToken" TEXT,
    "tokenExpiresAt" TIMESTAMP(3),
    "externalAccountLabel" TEXT,
    "connectedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "account_connectors_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "showcases" (
    "id" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "subtitle" TEXT,
    "imageUrl" TEXT,
    "destinationUrl" TEXT,
    "memoId" TEXT,
    "isActive" BOOLEAN NOT NULL DEFAULT false,
    "showOnWelcomeScreen" BOOLEAN NOT NULL DEFAULT false,
    "position" INTEGER NOT NULL DEFAULT 0,
    "startsAt" TIMESTAMP(3),
    "endsAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "showcases_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "feedback_campaigns" (
    "id" TEXT NOT NULL,
    "key" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "subtitle" TEXT,
    "submitLabel" TEXT NOT NULL DEFAULT 'Envoyer',
    "isActive" BOOLEAN NOT NULL DEFAULT false,
    "startsAt" TIMESTAMP(3),
    "endsAt" TIMESTAMP(3),
    "maxDisplays" INTEGER NOT NULL DEFAULT 1,
    "audience" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "feedback_campaigns_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "feedback_questions" (
    "id" TEXT NOT NULL,
    "campaignId" TEXT NOT NULL,
    "position" INTEGER NOT NULL,
    "kind" "FeedbackQuestionKind" NOT NULL,
    "prompt" TEXT,
    "placeholder" TEXT,
    "isRequired" BOOLEAN NOT NULL DEFAULT false,
    "config" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "feedback_questions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "feedback_responses" (
    "id" TEXT NOT NULL,
    "campaignId" TEXT NOT NULL,
    "accountId" TEXT,
    "displayCount" INTEGER NOT NULL DEFAULT 1,
    "shownAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "submittedAt" TIMESTAMP(3),
    "dismissedAt" TIMESTAMP(3),
    "appVersion" TEXT,

    CONSTRAINT "feedback_responses_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "feedback_answers" (
    "id" TEXT NOT NULL,
    "responseId" TEXT NOT NULL,
    "questionId" TEXT NOT NULL,
    "textValue" TEXT,
    "numberValue" DOUBLE PRECISION,
    "choiceKey" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "feedback_answers_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "memo_members_accountId_invitedAt_idx" ON "memo_members"("accountId", "invitedAt");

-- CreateIndex
CREATE UNIQUE INDEX "memo_members_memoId_accountId_key" ON "memo_members"("memoId", "accountId");

-- CreateIndex
CREATE UNIQUE INDEX "memo_members_memoId_invitedEmail_key" ON "memo_members"("memoId", "invitedEmail");

-- CreateIndex
CREATE INDEX "memo_steps_memoId_startDate_idx" ON "memo_steps"("memoId", "startDate");

-- CreateIndex
CREATE UNIQUE INDEX "memo_steps_memoId_number_key" ON "memo_steps"("memoId", "number");

-- CreateIndex
CREATE INDEX "expenses_memoId_occurredAt_idx" ON "expenses"("memoId", "occurredAt");

-- CreateIndex
CREATE UNIQUE INDEX "expenses_source_externalId_key" ON "expenses"("source", "externalId");

-- CreateIndex
CREATE UNIQUE INDEX "wallet_entries_stripeEventId_key" ON "wallet_entries"("stripeEventId");

-- CreateIndex
CREATE INDEX "wallet_entries_accountId_createdAt_idx" ON "wallet_entries"("accountId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "payment_cards_stripePaymentMethodId_key" ON "payment_cards"("stripePaymentMethodId");

-- CreateIndex
CREATE INDEX "payment_cards_accountId_idx" ON "payment_cards"("accountId");

-- CreateIndex
CREATE UNIQUE INDEX "subscriptions_providerSubscriptionId_key" ON "subscriptions"("providerSubscriptionId");

-- CreateIndex
CREATE INDEX "subscriptions_accountId_status_idx" ON "subscriptions"("accountId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "account_connectors_accountId_connectorKey_key" ON "account_connectors"("accountId", "connectorKey");

-- CreateIndex
CREATE INDEX "showcases_isActive_position_idx" ON "showcases"("isActive", "position");

-- CreateIndex
CREATE INDEX "showcases_showOnWelcomeScreen_position_idx" ON "showcases"("showOnWelcomeScreen", "position");

-- CreateIndex
CREATE UNIQUE INDEX "feedback_campaigns_key_key" ON "feedback_campaigns"("key");

-- CreateIndex
CREATE INDEX "feedback_campaigns_isActive_startsAt_idx" ON "feedback_campaigns"("isActive", "startsAt");

-- CreateIndex
CREATE UNIQUE INDEX "feedback_questions_campaignId_position_key" ON "feedback_questions"("campaignId", "position");

-- CreateIndex
CREATE INDEX "feedback_responses_campaignId_submittedAt_idx" ON "feedback_responses"("campaignId", "submittedAt");

-- CreateIndex
CREATE UNIQUE INDEX "feedback_responses_campaignId_accountId_key" ON "feedback_responses"("campaignId", "accountId");

-- CreateIndex
CREATE INDEX "feedback_answers_questionId_idx" ON "feedback_answers"("questionId");

-- CreateIndex
CREATE UNIQUE INDEX "feedback_answers_responseId_questionId_key" ON "feedback_answers"("responseId", "questionId");

-- CreateIndex
CREATE UNIQUE INDEX "accounts_stripeCustomerId_key" ON "accounts"("stripeCustomerId");

-- CreateIndex
CREATE INDEX "memos_ownerAccountId_createdAt_idx" ON "memos"("ownerAccountId", "createdAt");

-- CreateIndex
CREATE INDEX "entries_stepId_idx" ON "entries"("stepId");

-- CreateIndex
CREATE UNIQUE INDEX "print_orders_stripePaymentIntentId_key" ON "print_orders"("stripePaymentIntentId");

-- AddForeignKey
ALTER TABLE "memos" ADD CONSTRAINT "memos_ownerAccountId_fkey" FOREIGN KEY ("ownerAccountId") REFERENCES "accounts"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "memo_members" ADD CONSTRAINT "memo_members_memoId_fkey" FOREIGN KEY ("memoId") REFERENCES "memos"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "memo_members" ADD CONSTRAINT "memo_members_accountId_fkey" FOREIGN KEY ("accountId") REFERENCES "accounts"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "memo_steps" ADD CONSTRAINT "memo_steps_memoId_fkey" FOREIGN KEY ("memoId") REFERENCES "memos"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "expenses" ADD CONSTRAINT "expenses_memoId_fkey" FOREIGN KEY ("memoId") REFERENCES "memos"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "entries" ADD CONSTRAINT "entries_stepId_fkey" FOREIGN KEY ("stepId") REFERENCES "memo_steps"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "wallet_entries" ADD CONSTRAINT "wallet_entries_accountId_fkey" FOREIGN KEY ("accountId") REFERENCES "accounts"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "wallet_entries" ADD CONSTRAINT "wallet_entries_printOrderId_fkey" FOREIGN KEY ("printOrderId") REFERENCES "print_orders"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payment_cards" ADD CONSTRAINT "payment_cards_accountId_fkey" FOREIGN KEY ("accountId") REFERENCES "accounts"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "subscriptions" ADD CONSTRAINT "subscriptions_accountId_fkey" FOREIGN KEY ("accountId") REFERENCES "accounts"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "account_connectors" ADD CONSTRAINT "account_connectors_accountId_fkey" FOREIGN KEY ("accountId") REFERENCES "accounts"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "feedback_questions" ADD CONSTRAINT "feedback_questions_campaignId_fkey" FOREIGN KEY ("campaignId") REFERENCES "feedback_campaigns"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "feedback_responses" ADD CONSTRAINT "feedback_responses_campaignId_fkey" FOREIGN KEY ("campaignId") REFERENCES "feedback_campaigns"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "feedback_responses" ADD CONSTRAINT "feedback_responses_accountId_fkey" FOREIGN KEY ("accountId") REFERENCES "accounts"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "feedback_answers" ADD CONSTRAINT "feedback_answers_responseId_fkey" FOREIGN KEY ("responseId") REFERENCES "feedback_responses"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "feedback_answers" ADD CONSTRAINT "feedback_answers_questionId_fkey" FOREIGN KEY ("questionId") REFERENCES "feedback_questions"("id") ON DELETE CASCADE ON UPDATE CASCADE;


-- ---------------------------------------------------------------------------
-- Reprise de données
--
-- Sans elle, les carnets déjà en base resteraient sans propriétaire, sans
-- participant et rangés « en cours » quelle que soit leur date. Les valeurs par
-- défaut suffisent pour un carnet créé demain, pas pour ceux qui existent.
-- ---------------------------------------------------------------------------

-- Un carnet appartient au compte de son appareil, quand cet appareil en a un.
-- Les autres restent sans propriétaire : c'est exactement l'état qu'il faudra
-- résorber avant de rendre `ownerAccountId` obligatoire.
UPDATE "memos" AS m
SET "ownerAccountId" = d."accountId"
FROM "devices" AS d
WHERE d."id" = m."deviceId"
  AND d."accountId" IS NOT NULL;

-- Le propriétaire a sa ligne de participant comme les autres : « qui est sur ce
-- voyage » doit rester une seule requête.
INSERT INTO "memo_members" ("id", "memoId", "accountId", "role", "status", "invitedAt", "acceptedAt")
SELECT gen_random_uuid()::text, m."id", m."ownerAccountId", 'owner', 'active', m."createdAt", m."createdAt"
FROM "memos" AS m
WHERE m."ownerAccountId" IS NOT NULL;

-- Les compteurs de l'accueil, à partir de ce qui a déjà été raconté.
UPDATE "memos" AS m
SET "memoryCount" = counted."total",
    "photoCount"  = counted."photos"
FROM (
  SELECT "memoId",
         COUNT(*)::int AS "total",
         COUNT(*) FILTER (WHERE "kind" = 'photo')::int AS "photos"
  FROM "entries"
  GROUP BY "memoId"
) AS counted
WHERE counted."memoId" = m."id";

-- Le rangement de l'accueil se déduit des dates. Un carnet sans date reste
-- « en cours » : c'est le défaut, et il vaut mieux un voyage visible en haut de
-- l'écran qu'un voyage rangé à tort parmi les carnets terminés.
UPDATE "memos" SET "stage" = 'past'
WHERE "endDate" IS NOT NULL AND "endDate" < NOW();

UPDATE "memos" SET "stage" = 'upcoming'
WHERE "startDate" IS NOT NULL AND "startDate" > NOW();

-- Un carnet déjà généré peut partir à l'impression.
UPDATE "memos" AS m
SET "isPrintable" = true
WHERE EXISTS (
  SELECT 1 FROM "renders" AS r
  WHERE r."memoId" = m."id" AND r."status" = 'ready'
);
