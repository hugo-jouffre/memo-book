-- Les couvertures du carnet (T88) et le voyage d'un abonnement (T71),
-- 29/09/2026.
--
-- `cover_photos` : les photos importées pour la couverture, à côté des photos
-- du voyage et non dedans — elles ne sont pas des souvenirs. Stockées comme
-- les photos de profil (la clé seule, l'adresse se calcule à la lecture).
--
-- `subscriptions.memoId` : le carnet que l'abonnement finance. Nullable —
-- aucune route ne crée encore d'abonnement — et en SetNull : un voyage
-- supprimé n'emporte pas l'historique de facturation.

-- AlterTable
ALTER TABLE "subscriptions" ADD COLUMN     "memoId" TEXT;

-- CreateTable
CREATE TABLE "cover_photos" (
    "id" TEXT NOT NULL,
    "memoId" TEXT NOT NULL,
    "storageKey" TEXT NOT NULL,
    "mimeType" TEXT NOT NULL,
    "bytes" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "cover_photos_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "cover_photos_storageKey_key" ON "cover_photos"("storageKey");

-- CreateIndex
CREATE INDEX "cover_photos_memoId_createdAt_idx" ON "cover_photos"("memoId", "createdAt");

-- CreateIndex
CREATE INDEX "subscriptions_memoId_idx" ON "subscriptions"("memoId");

-- AddForeignKey
ALTER TABLE "subscriptions" ADD CONSTRAINT "subscriptions_memoId_fkey" FOREIGN KEY ("memoId") REFERENCES "memos"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "cover_photos" ADD CONSTRAINT "cover_photos_memoId_fkey" FOREIGN KEY ("memoId") REFERENCES "memos"("id") ON DELETE CASCADE ON UPDATE CASCADE;
