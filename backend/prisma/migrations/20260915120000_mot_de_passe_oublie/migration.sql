-- « Mot de passe oublié » : le secret qu'on envoie par e-mail pour choisir un
-- nouveau mot de passe.
--
-- Une table à part, et non une colonne sur `accounts`, parce qu'une demande a
-- une vie propre : elle expire, elle se consomme, et on veut garder trace de
-- celle qui a servi. Le secret est haché comme un token de session — la base
-- n'en connaît que l'empreinte, l'e-mail seul porte le clair.
CREATE TABLE "password_resets" (
    "id" TEXT NOT NULL,
    "accountId" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "usedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "password_resets_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "password_resets_tokenHash_key" ON "password_resets"("tokenHash");

CREATE INDEX "password_resets_accountId_idx" ON "password_resets"("accountId");

ALTER TABLE "password_resets" ADD CONSTRAINT "password_resets_accountId_fkey" FOREIGN KEY ("accountId") REFERENCES "accounts"("id") ON DELETE CASCADE ON UPDATE CASCADE;
