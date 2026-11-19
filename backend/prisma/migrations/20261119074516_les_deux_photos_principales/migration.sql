-- AlterTable
ALTER TABLE "memo_steps" ADD COLUMN     "coverEntryId" TEXT;

-- AlterTable
ALTER TABLE "memos" ADD COLUMN     "coverEntryId" TEXT;

-- AddForeignKey
ALTER TABLE "memos" ADD CONSTRAINT "memos_coverEntryId_fkey" FOREIGN KEY ("coverEntryId") REFERENCES "entries"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "memo_steps" ADD CONSTRAINT "memo_steps_coverEntryId_fkey" FOREIGN KEY ("coverEntryId") REFERENCES "entries"("id") ON DELETE SET NULL ON UPDATE CASCADE;
