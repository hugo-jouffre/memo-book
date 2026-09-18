-- La photo de profil envoyée depuis l'app (Clara, 17/09/2026, T165).
--
-- Une clé de stockage et non une URL : le stockage ne sait produire que des
-- liens signés, qui expirent, et l'adresse se calcule à la lecture par
-- `GET /v1/avatars/:file` — voir `services/avatars.ts`. `avatarUrl` reste pour
-- la photo qu'un fournisseur a donnée.
ALTER TABLE "accounts" ADD COLUMN "avatarStorageKey" TEXT;
