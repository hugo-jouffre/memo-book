-- Les messages à l'équipe et les votes de la foire aux questions (T226, Hugo
-- 06/10/2026) : « Écris à notre équipe », « Partager mes retours » du mot des
-- fondateurs et « Est-ce utile ? » ne se perdent plus — ils s'enregistrent.
--
-- Additive : deux tables et une énumération, rien de retiré. Les deux tables
-- pendent du compte en cascade (comme `feedback_responses`) : ce sont les
-- données de la personne, elles partent avec elle et dans son export.

-- CreateEnum
CREATE TYPE "SupportMessageSource" AS ENUM ('support', 'founders_note');

-- CreateTable
CREATE TABLE "support_messages" (
    "id" TEXT NOT NULL,
    "accountId" TEXT NOT NULL,
    "source" "SupportMessageSource" NOT NULL,
    "topicId" TEXT,
    "message" TEXT NOT NULL,
    "memoId" TEXT,
    "appVersion" TEXT,
    "diagnostics" JSONB,
    "handledAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "support_messages_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "faq_votes" (
    "accountId" TEXT NOT NULL,
    "questionId" TEXT NOT NULL,
    "isHelpful" BOOLEAN NOT NULL,
    "appVersion" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "faq_votes_pkey" PRIMARY KEY ("accountId","questionId")
);

-- CreateIndex
CREATE INDEX "support_messages_accountId_createdAt_idx" ON "support_messages"("accountId", "createdAt");

-- CreateIndex
CREATE INDEX "support_messages_handledAt_createdAt_idx" ON "support_messages"("handledAt", "createdAt");

-- CreateIndex
CREATE INDEX "faq_votes_questionId_idx" ON "faq_votes"("questionId");

-- AddForeignKey
ALTER TABLE "support_messages" ADD CONSTRAINT "support_messages_accountId_fkey" FOREIGN KEY ("accountId") REFERENCES "accounts"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "support_messages" ADD CONSTRAINT "support_messages_memoId_fkey" FOREIGN KEY ("memoId") REFERENCES "memos"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "faq_votes" ADD CONSTRAINT "faq_votes_accountId_fkey" FOREIGN KEY ("accountId") REFERENCES "accounts"("id") ON DELETE CASCADE ON UPDATE CASCADE;

