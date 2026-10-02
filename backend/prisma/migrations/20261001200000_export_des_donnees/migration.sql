-- « Exporter mes données » (RGPD, articles 15 et 20) : le lien qu'on envoie par
-- e-mail pour télécharger tout ce que MemoBook garde d'un compte.
--
-- Une table à part, comme `password_resets`, parce qu'une demande a une vie
-- propre : elle expire au bout de sept jours, une demande plus récente la
-- remplace, et on veut savoir combien de fois le lien a servi. Le secret est
-- haché comme un token de session — la base n'en connaît que l'empreinte,
-- l'e-mail seul porte le clair.
--
-- Aucune archive n'est stockée : le ZIP se compose à l'ouverture du lien.
CREATE TABLE "data_exports" (
    "id" TEXT NOT NULL,
    "accountId" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "revokedAt" TIMESTAMP(3),
    "downloadCount" INTEGER NOT NULL DEFAULT 0,
    "lastDownloadedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "data_exports_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "data_exports_tokenHash_key" ON "data_exports"("tokenHash");

CREATE INDEX "data_exports_accountId_createdAt_idx" ON "data_exports"("accountId", "createdAt");

ALTER TABLE "data_exports" ADD CONSTRAINT "data_exports_accountId_fkey" FOREIGN KEY ("accountId") REFERENCES "accounts"("id") ON DELETE CASCADE ON UPDATE CASCADE;
