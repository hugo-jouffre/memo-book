-- AlterTable
ALTER TABLE "print_orders" ADD COLUMN     "refundedCents" INTEGER NOT NULL DEFAULT 0;

-- AlterTable
ALTER TABLE "wallet_entries" ADD COLUMN     "idempotencyKey" TEXT,
ADD COLUMN     "stripePaymentIntentId" TEXT;

-- CreateIndex
CREATE UNIQUE INDEX "wallet_entries_idempotencyKey_key" ON "wallet_entries"("idempotencyKey");

-- CreateIndex
CREATE INDEX "wallet_entries_stripePaymentIntentId_idx" ON "wallet_entries"("stripePaymentIntentId");

