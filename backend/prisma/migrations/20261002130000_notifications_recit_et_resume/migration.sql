-- « Nouveau récit » et « Résumé hebdomadaire » : les deux alertes de la
-- feuille du voyage qui n'envoyaient rien (`docs/notifications.md`). Leurs
-- drapeaux existent déjà (`memos.notifyNewStory`, `memos.notifyWeeklyDigest`) ;
-- il ne manquait que leur nature dans le journal des envois.
ALTER TYPE "NotificationKind" ADD VALUE 'new_story';
ALTER TYPE "NotificationKind" ADD VALUE 'weekly_digest';
