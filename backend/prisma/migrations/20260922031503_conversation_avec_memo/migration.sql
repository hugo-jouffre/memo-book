-- CreateEnum
CREATE TYPE "ChatAuthor" AS ENUM ('memo', 'traveller');

-- CreateEnum
CREATE TYPE "ChatMessageKind" AS ENUM ('text', 'voice', 'transcript', 'photos');

-- CreateEnum
CREATE TYPE "ChatDisposition" AS ENUM ('memory', 'context', 'command');

-- AlterTable
ALTER TABLE "entries" ADD COLUMN     "validatedAt" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "memos" ADD COLUMN     "chatClearedAt" TIMESTAMP(3),
ADD COLUMN     "conversationState" JSONB;

-- CreateTable
CREATE TABLE "chat_messages" (
    "id" TEXT NOT NULL,
    "memoId" TEXT NOT NULL,
    "seq" SERIAL NOT NULL,
    "author" "ChatAuthor" NOT NULL,
    "kind" "ChatMessageKind" NOT NULL,
    "accountId" TEXT,
    "text" TEXT,
    "entryId" TEXT,
    "disposition" "ChatDisposition",
    "suggestionId" TEXT,
    "stepId" TEXT,
    "replyToId" TEXT,
    "pauseMilliseconds" INTEGER,
    "model" TEXT,
    "repliedAt" TIMESTAMP(3),
    "payload" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "chat_messages_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "chat_messages_seq_key" ON "chat_messages"("seq");

-- CreateIndex
CREATE INDEX "chat_messages_memoId_seq_idx" ON "chat_messages"("memoId", "seq");

-- CreateIndex
CREATE INDEX "chat_messages_memoId_author_createdAt_idx" ON "chat_messages"("memoId", "author", "createdAt");

-- CreateIndex
CREATE INDEX "chat_messages_entryId_idx" ON "chat_messages"("entryId");

-- AddForeignKey
ALTER TABLE "chat_messages" ADD CONSTRAINT "chat_messages_memoId_fkey" FOREIGN KEY ("memoId") REFERENCES "memos"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "chat_messages" ADD CONSTRAINT "chat_messages_accountId_fkey" FOREIGN KEY ("accountId") REFERENCES "accounts"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "chat_messages" ADD CONSTRAINT "chat_messages_entryId_fkey" FOREIGN KEY ("entryId") REFERENCES "entries"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "chat_messages" ADD CONSTRAINT "chat_messages_stepId_fkey" FOREIGN KEY ("stepId") REFERENCES "memo_steps"("id") ON DELETE SET NULL ON UPDATE CASCADE;
