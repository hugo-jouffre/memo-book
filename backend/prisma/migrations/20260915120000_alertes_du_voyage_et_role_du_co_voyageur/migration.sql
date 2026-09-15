-- Le détail des alertes d'un voyage, et le rôle déduit d'un co-voyageur.
--
-- Les quatre drapeaux d'alerte viennent de la feuille « Notifications » : la
-- ligne des réglages coupait déjà tout d'un coup (`notificationsEnabled`), il
-- manquait de quoi dire *quoi* recevoir quand elle est levée. Tous à `true`,
-- comme l'interrupteur maître : un voyage existant ne doit pas devenir muet.
ALTER TABLE "memos"
  ADD COLUMN "notifyWritingReminder" BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN "notifyNewStory"        BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN "notifyWeeklyDigest"    BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN "notifyTripEnd"         BOOLEAN NOT NULL DEFAULT true;

-- Le rôle est **déduit** par l'agent de rédaction, jamais saisi : nul par
-- défaut, et nul pour tous les co-voyageurs déjà en base.
ALTER TABLE "memo_members" ADD COLUMN "role" TEXT;
