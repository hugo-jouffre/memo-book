-- Le moment où le voyageur a posé sa bulle, et c'est lui qui range le fil
-- (T309). Rempli avec `createdAt` pour tout ce qui existe : l'ordre d'avant,
-- intact, et rien ne bouge sous les yeux de personne.

-- AlterTable
ALTER TABLE "chat_messages" ADD COLUMN     "postedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

UPDATE "chat_messages" SET "postedAt" = "createdAt";

-- CreateIndex
CREATE INDEX "chat_messages_memoId_postedAt_seq_idx" ON "chat_messages"("memoId", "postedAt", "seq");
