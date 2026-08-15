-- Passe de rédaction (agents/agent-transcription.md) séparée de la mise en
-- page, correction manuelle par l'utilisateur, et commandes d'impression.

-- CreateEnum
CREATE TYPE "PrintOrderStatus" AS ENUM ('draft', 'submitted', 'in_production', 'shipped', 'cancelled');

-- AlterTable
ALTER TABLE "memos"
  ADD COLUMN "styleKey" TEXT,
  ADD COLUMN "coherenceSheet" JSONB;

-- AlterTable
ALTER TABLE "entries"
  ADD COLUMN "redactedText" TEXT,
  ADD COLUMN "redactionStatus" "Status" NOT NULL DEFAULT 'pending',
  ADD COLUMN "redactionError" TEXT,
  ADD COLUMN "redactionModel" TEXT,
  ADD COLUMN "redactedAt" TIMESTAMP(3),
  ADD COLUMN "editedText" TEXT,
  ADD COLUMN "editedAt" TIMESTAMP(3),
  ADD COLUMN "suggestedTitle" TEXT,
  ADD COLUMN "funFact" TEXT,
  ADD COLUMN "funFactTitle" TEXT,
  ADD COLUMN "weatherKey" TEXT;

-- Les entrées photo n'ont pas de texte à rédiger : elles sont déjà au bout du
-- pipeline. Sans ça, un carnet existant resterait bloqué « en cours ».
UPDATE "entries" SET "redactionStatus" = 'ready' WHERE "kind" = 'photo';

-- CreateTable
CREATE TABLE "print_orders" (
    "id" TEXT NOT NULL,
    "memoId" TEXT NOT NULL,
    "renderId" TEXT NOT NULL,
    "status" "PrintOrderStatus" NOT NULL DEFAULT 'draft',
    "copies" INTEGER NOT NULL DEFAULT 1,
    "shippingName" TEXT NOT NULL,
    "shippingLine1" TEXT NOT NULL,
    "shippingLine2" TEXT,
    "shippingPostalCode" TEXT NOT NULL,
    "shippingCity" TEXT NOT NULL,
    "shippingCountry" TEXT NOT NULL,
    "providerOrderId" TEXT,
    "trackingUrl" TEXT,
    "error" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "print_orders_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "print_orders_memoId_createdAt_idx" ON "print_orders"("memoId", "createdAt");

-- AddForeignKey
ALTER TABLE "print_orders" ADD CONSTRAINT "print_orders_memoId_fkey" FOREIGN KEY ("memoId") REFERENCES "memos"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Restrict, pas Cascade : supprimer un rendu déjà commandé effacerait la
-- trace de ce qui a été envoyé à l'impression.
ALTER TABLE "print_orders" ADD CONSTRAINT "print_orders_renderId_fkey" FOREIGN KEY ("renderId") REFERENCES "renders"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
