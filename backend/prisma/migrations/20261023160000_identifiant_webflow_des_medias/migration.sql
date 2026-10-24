-- L'identifiant Webflow d'une photo publiée sur le CDN (23/10/2026).
--
-- `cdnUrl` suffit à APITemplate, pas à la suppression : l'API de Webflow
-- efface un fichier par son identifiant (`DELETE /v2/assets/{id}`), et rien ne
-- le gardait. Sans lui, la copie publique d'une photo survivait au compte.
--
-- Additive : une colonne nullable. Aucune photo de la production n'est passée
-- par Webflow à ce jour (toutes les `cdnUrl` sont simulées) : rien à reprendre.

-- AlterTable
ALTER TABLE "media_assets" ADD COLUMN "cdnAssetId" TEXT;
