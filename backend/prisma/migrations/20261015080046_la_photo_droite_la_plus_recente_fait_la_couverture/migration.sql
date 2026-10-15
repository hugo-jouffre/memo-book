-- AlterTable
ALTER TABLE "entries" ADD COLUMN     "photoIsUpright" BOOLEAN;

-- CreateIndex
CREATE INDEX "entries_memoId_photoIsUpright_capturedAt_idx" ON "entries"("memoId", "photoIsUpright", "capturedAt");
