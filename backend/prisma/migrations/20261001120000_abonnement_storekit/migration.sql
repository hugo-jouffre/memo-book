-- AlterTable
ALTER TABLE "subscriptions" ADD COLUMN     "autoRenews" BOOLEAN,
ADD COLUMN     "environment" TEXT,
ADD COLUMN     "productId" TEXT,
ADD COLUMN     "providerUpdatedAt" TIMESTAMP(3);

-- CreateTable
CREATE TABLE "subscription_transactions" (
    "id" TEXT NOT NULL,
    "subscriptionId" TEXT NOT NULL,
    "memoId" TEXT,
    "transactionId" TEXT NOT NULL,
    "originalTransactionId" TEXT NOT NULL,
    "productId" TEXT NOT NULL,
    "purchasedAt" TIMESTAMP(3) NOT NULL,
    "expiresAt" TIMESTAMP(3),
    "priceCents" INTEGER,
    "currency" TEXT,
    "environment" TEXT NOT NULL,
    "revokedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "subscription_transactions_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "subscription_transactions_transactionId_key" ON "subscription_transactions"("transactionId");

-- CreateIndex
CREATE INDEX "subscription_transactions_subscriptionId_purchasedAt_idx" ON "subscription_transactions"("subscriptionId", "purchasedAt");

-- CreateIndex
CREATE INDEX "subscription_transactions_memoId_idx" ON "subscription_transactions"("memoId");

-- AddForeignKey
ALTER TABLE "subscription_transactions" ADD CONSTRAINT "subscription_transactions_subscriptionId_fkey" FOREIGN KEY ("subscriptionId") REFERENCES "subscriptions"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "subscription_transactions" ADD CONSTRAINT "subscription_transactions_memoId_fkey" FOREIGN KEY ("memoId") REFERENCES "memos"("id") ON DELETE SET NULL ON UPDATE CASCADE;

