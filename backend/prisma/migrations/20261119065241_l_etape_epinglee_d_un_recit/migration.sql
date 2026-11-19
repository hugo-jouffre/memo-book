-- AlterTable
ALTER TABLE "entries" ADD COLUMN     "pinnedStepId" TEXT;

-- CreateIndex
CREATE INDEX "entries_pinnedStepId_idx" ON "entries"("pinnedStepId");

-- AddForeignKey
ALTER TABLE "entries" ADD CONSTRAINT "entries_pinnedStepId_fkey" FOREIGN KEY ("pinnedStepId") REFERENCES "memo_steps"("id") ON DELETE SET NULL ON UPDATE CASCADE;
