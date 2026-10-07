-- La composition à la demande (T224, Hugo 06/10/2026) : l'aperçu PDF lance une
-- composition à chaque ouverture, et le serveur rend la précédente quand rien
-- n'a changé depuis — une composition coûte de l'IA et un rendu APITemplate.
--
-- `inputFingerprint` : l'empreinte de ce que le rendu a composé (souvenirs,
-- étapes, personnalisations, couvertures, titre, dates). Nulle pour les rendus
-- d'avant : ils sont considérés comme périmés, la première ouverture recompose.
--
-- `composingStartedAt` : l'instant où le PDF part chez APITemplate, après la
-- mise en page. C'est ce qui donne à l'app la phase « composing » sans lire le
-- payload entier à chaque sondage.
--
-- Additive : aucune colonne retirée.

-- AlterTable
ALTER TABLE "renders" ADD COLUMN "inputFingerprint" TEXT,
ADD COLUMN "composingStartedAt" TIMESTAMP(3);
