-- AlterTable
ALTER TABLE "memos" ADD COLUMN     "gallerySummary" TEXT;

-- CreateTable
CREATE TABLE "gallery_categories" (
    "id" TEXT NOT NULL,
    "slug" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "iconKey" TEXT NOT NULL,
    "position" INTEGER NOT NULL DEFAULT 0,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "gallery_categories_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "memo_gallery_categories" (
    "memoId" TEXT NOT NULL,
    "categoryId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "memo_gallery_categories_pkey" PRIMARY KEY ("memoId","categoryId")
);

-- CreateIndex
CREATE UNIQUE INDEX "gallery_categories_slug_key" ON "gallery_categories"("slug");

-- CreateIndex
CREATE INDEX "gallery_categories_isActive_position_idx" ON "gallery_categories"("isActive", "position");

-- CreateIndex
CREATE INDEX "memo_gallery_categories_categoryId_idx" ON "memo_gallery_categories"("categoryId");

-- CreateIndex
CREATE INDEX "memos_isPublicGallery_startDate_idx" ON "memos"("isPublicGallery", "startDate");

-- AddForeignKey
ALTER TABLE "memo_gallery_categories" ADD CONSTRAINT "memo_gallery_categories_memoId_fkey" FOREIGN KEY ("memoId") REFERENCES "memos"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "memo_gallery_categories" ADD CONSTRAINT "memo_gallery_categories_categoryId_fkey" FOREIGN KEY ("categoryId") REFERENCES "gallery_categories"("id") ON DELETE CASCADE ON UPDATE CASCADE;
