-- Les réglages d'un voyage, et le lien public de son aperçu.
--
-- Trois colonnes, pour trois écrans dessinés dans « 🤖 Claude Import » :
-- *Paramètres du voyage*, *Aperçu PDF* et *Partager ton MemoBook*.
--
--  1. `bookTitle` — le titre que le **récit** se donne (« Rome et la Dolce
--     Vita »), distinct du nom du voyage (« Rome 2026 »). Les deux s'affichent
--     à deux endroits différents de l'app, et les confondre obligerait à
--     renommer son voyage pour changer la couverture de son carnet.
--  2. `notificationsEnabled` — les relances de **ce voyage-ci**. Distinct de
--     l'autorisation système, qui est globale : couper ici n'enlève rien à
--     iOS, ça arrête les relances de ce carnet.
--  3. `shareSlug` — le lien de prévisualisation, celui qu'on envoie à ses
--     proches pour qu'ils suivent le carnet en direct. Unique, court, et
--     **nul par défaut** : c'est un lien public, il ne se crée pas tout seul à
--     la création d'un voyage. Il n'apparaît qu'une fois demandé depuis la
--     feuille de partage.
--
-- Rien pour la cagnotte : `wallet_entries` porte déjà tout ce que l'historique
-- affiche (le montant, la nature, le motif lisible, la date), et le solde est
-- déjà en cache sur `accounts.walletBalanceCents`. L'écran se sert, il n'a
-- rien demandé de neuf — c'est le registre en ajout seul de M4 qui avait vu
-- juste.

-- Le thème de l'aventure, lui, existe déjà (`memos.theme`, M1) : il servait à
-- la rédaction, il devient une ligne réglable. Rien à ajouter pour lui.
ALTER TABLE "memos" ADD COLUMN     "bookTitle" TEXT,
ADD COLUMN     "notificationsEnabled" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "shareSlug" TEXT;

-- CreateIndex
CREATE UNIQUE INDEX "memos_shareSlug_key" ON "memos"("shareSlug");
