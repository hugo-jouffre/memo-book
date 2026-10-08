import { frenchDate } from "../lib/frenchFormat.js";
import type { DataExportMail, PasswordResetMail, SubscriptionReminderMail } from "./mailer.js";
import { formatEuros } from "./notificationCopy.js";

/**
 * Les e-mails de l'app, en HTML **et** en texte. Le texte n'est pas une
 * concession : c'est ce que lisent les clients qui n'affichent pas le HTML, et
 * ce qu'on voit dans l'aperçu d'une boîte de réception.
 *
 * Tout est en ligne — styles compris — parce qu'un e-mail ne charge ni feuille
 * de style ni police : c'est du HTML de 2005, et c'est voulu. Les couleurs
 * sont celles de `ios/…/Tokens.swift` : crème `#FCF2E9`, papier `#FFFCF8`,
 * encre `#2D231A`, vert d'action `#28654B`.
 */
export interface RenderedMail {
  subject: string;
  html: string;
  text: string;
}

const COLORS = {
  background: "#FCF2E9",
  paper: "#FFFCF8",
  ink: "#2D231A",
  inkMuted: "#8A8078",
  action: "#28654B",
  onAction: "#FFFCF8",
};

/** Le HTML d'un e-mail se construit à la main : on échappe tout ce qui vient d'ailleurs. */
function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

/**
 * L'objet, en un seul endroit — il apparaît aussi dans le `<title>`, que
 * certaines boîtes affichent à la place.
 *
 * **Il doit rester identique à celui du gabarit Resend `password-reset`**
 * (`backend/scripts/resend-templates.ts`). Les deux coexistent le temps que le
 * gabarit hébergé soit publié et que `mailer.ts` bascule dessus — voir
 * `docs/emails.md` § 9. Deux objets différents pour le même e-mail, c'est un
 * support qui ne retrouve pas le message dont on lui parle.
 */
const PASSWORD_RESET_SUBJECT = "Réinitialise ton mot de passe MemoBook";

/**
 * « Réinitialise ton mot de passe MemoBook » — les mots de la maquette
 * (Hugo, 15/09/2026), passés au tutoiement d'un bout à l'autre : le corps
 * tutoyait déjà, seul le titre vouvoyait encore.
 */
export function renderPasswordResetMail(
  message: PasswordResetMail,
  resetUrl: string,
): RenderedMail {
  const greeting = message.firstName ? `Bonjour ${message.firstName},` : "Bonjour,";
  const validity = `${Math.round(
    (message.expiresAt.getTime() - Date.now()) / 60_000,
  )} minutes`;

  const text = [
    "MemoBook",
    "",
    PASSWORD_RESET_SUBJECT,
    "",
    greeting,
    "",
    "Tu as demandé à réinitialiser ton mot de passe.",
    "",
    "Si tu es à l’origine de cette demande, ouvre ce lien pour choisir un nouveau mot de passe :",
    resetUrl,
    "",
    `Le lien est valable ${validity}.`,
    "",
    "Si tu n’es pas à l’origine de cette demande, tu peux simplement ignorer cet e-mail. Ton mot de passe restera inchangé.",
    "",
    "À bientôt,",
    "L’équipe MemoBook",
  ].join("\n");

  const html = `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(PASSWORD_RESET_SUBJECT)}</title>
</head>
<body style="margin:0;padding:0;background:${COLORS.background};">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background:${COLORS.background};">
<tr><td align="center" style="padding:32px 16px;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:480px;background:${COLORS.paper};border-radius:20px;overflow:hidden;">
<tr>
<td align="center" style="background:${COLORS.action};padding:40px 24px;">
<div style="font-family:Georgia,'Times New Roman',serif;font-size:36px;line-height:36px;font-weight:700;letter-spacing:2px;color:${COLORS.onAction};">MEMO<br>BOOK</div>
</td>
</tr>
<tr>
<td style="padding:32px 24px 8px;font-family:-apple-system,BlinkMacSystemFont,'Helvetica Neue',Helvetica,Arial,sans-serif;color:${COLORS.ink};">
<h1 style="margin:0 0 24px;font-size:22px;line-height:28px;font-weight:700;">Réinitialise ton mot de passe</h1>
<p style="margin:0 0 16px;font-size:15px;line-height:22px;">${escapeHtml(greeting)}</p>
<p style="margin:0 0 16px;font-size:15px;line-height:22px;">Tu as demandé à réinitialiser ton mot de passe.</p>
<p style="margin:0 0 24px;font-size:15px;line-height:22px;">Si tu es à l’origine de cette demande, clique sur le bouton ci-dessous pour choisir un nouveau mot de passe :</p>
</td>
</tr>
<tr>
<td align="center" style="padding:0 24px 24px;">
<a href="${escapeHtml(resetUrl)}" style="display:inline-block;background:${COLORS.action};color:${COLORS.onAction};text-decoration:none;font-family:-apple-system,BlinkMacSystemFont,'Helvetica Neue',Helvetica,Arial,sans-serif;font-size:15px;font-weight:600;line-height:20px;padding:14px 28px;border-radius:12px;">Réinitialiser mon mot de passe</a>
<p style="margin:12px 0 0;font-family:-apple-system,BlinkMacSystemFont,'Helvetica Neue',Helvetica,Arial,sans-serif;font-size:12px;line-height:16px;color:${COLORS.inkMuted};">Le lien est valable ${escapeHtml(validity)}.</p>
</td>
</tr>
<tr>
<td style="padding:0 24px 32px;font-family:-apple-system,BlinkMacSystemFont,'Helvetica Neue',Helvetica,Arial,sans-serif;color:${COLORS.ink};">
<p style="margin:0 0 16px;font-size:15px;line-height:22px;">Si tu n’es pas à l’origine de cette demande, tu peux simplement ignorer cet e-mail. Ton mot de passe restera inchangé.</p>
<p style="margin:0;font-size:15px;line-height:22px;">À bientôt,<br>L’équipe MemoBook</p>
</td>
</tr>
</table>
</td></tr>
</table>
</body>
</html>`;

  return { subject: PASSWORD_RESET_SUBJECT, html, text };
}

/**
 * L'objet de « Exporter mes données ». **Identique à celui du gabarit Resend
 * `data-export`** (`templates/emails/data-export.njk`), pour la même raison
 * que le mot de passe oublié — voir `PASSWORD_RESET_SUBJECT`.
 */
const DATA_EXPORT_SUBJECT = "Tes données MemoBook sont prêtes";

/** Ce que l'archive contient, en une phrase — l'e-mail, la page et l'app disent la même. */
export const DATA_EXPORT_CONTENTS =
  "ton compte, tes voyages et leurs récits, chaque souvenir tel que tu l’as raconté et tel que MEMO l’a écrit, tes photos et tes vocaux d’origine, tes carnets en PDF, tes commandes et ton abonnement";

/**
 * « Tes données MemoBook sont prêtes » — `account.data_export`, niveau 1 de
 * `docs/emails.md` : le lien porte un secret, le texte vit dans le dépôt.
 *
 * L'e-mail ne joint **rien** : une archive pèse des centaines de mégaoctets,
 * et un e-mail se transfère. Il porte un lien vers la page de
 * téléchargement, et dit en clair ce que le lien ouvre — c'est la phrase qui
 * fait réfléchir avant de transférer.
 */
export function renderDataExportMail(message: DataExportMail, downloadUrl: string): RenderedMail {
  const greeting = message.firstName ? `Bonjour ${message.firstName},` : "Bonjour,";
  const until = frenchDate(message.expiresAt, { weekday: true });

  const text = [
    "MemoBook",
    "",
    DATA_EXPORT_SUBJECT,
    "",
    greeting,
    "",
    "Tu as demandé une copie de tes données MemoBook. Ouvre ce lien pour la télécharger :",
    downloadUrl,
    "",
    `Le lien est valable jusqu’au ${until}. Il sert plusieurs fois : si un téléchargement s’interrompt, relance-le.`,
    "",
    `Dans l’archive : ${DATA_EXPORT_CONTENTS}. Des fichiers JSON, lisibles par n’importe quel logiciel, et un récit en texte simple pour chaque voyage.`,
    "",
    "Ce lien ouvre toutes tes données : ne le transfère à personne.",
    "",
    "Tu n’as rien demandé ? N’ouvre pas le lien, et réponds à cet e-mail : on regardera ce qui se passe sur ton compte.",
    "",
    "À bientôt,",
    "L’équipe MemoBook",
  ].join("\n");

  const font = "-apple-system,BlinkMacSystemFont,'Helvetica Neue',Helvetica,Arial,sans-serif";
  const html = `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(DATA_EXPORT_SUBJECT)}</title>
</head>
<body style="margin:0;padding:0;background:${COLORS.background};">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background:${COLORS.background};">
<tr><td align="center" style="padding:32px 16px;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:480px;background:${COLORS.paper};border-radius:20px;overflow:hidden;">
<tr>
<td align="center" style="background:${COLORS.action};padding:40px 24px;">
<div style="font-family:Georgia,'Times New Roman',serif;font-size:36px;line-height:36px;font-weight:700;letter-spacing:2px;color:${COLORS.onAction};">MEMO<br>BOOK</div>
</td>
</tr>
<tr>
<td style="padding:32px 24px 8px;font-family:${font};color:${COLORS.ink};">
<h1 style="margin:0 0 24px;font-size:22px;line-height:28px;font-weight:700;">Tes données sont prêtes</h1>
<p style="margin:0 0 16px;font-size:15px;line-height:22px;">${escapeHtml(greeting)}</p>
<p style="margin:0 0 24px;font-size:15px;line-height:22px;">Tu as demandé une copie de tes données MemoBook. Le bouton ci-dessous ouvre la page où la télécharger.</p>
</td>
</tr>
<tr>
<td align="center" style="padding:0 24px 24px;">
<a href="${escapeHtml(downloadUrl)}" style="display:inline-block;background:${COLORS.action};color:${COLORS.onAction};text-decoration:none;font-family:${font};font-size:15px;font-weight:600;line-height:20px;padding:14px 28px;border-radius:12px;">Télécharger mes données</a>
<p style="margin:12px 0 0;font-family:${font};font-size:12px;line-height:16px;color:${COLORS.inkMuted};">Le lien est valable jusqu’au ${escapeHtml(until)}.</p>
</td>
</tr>
<tr>
<td style="padding:0 24px 24px;font-family:${font};color:${COLORS.ink};">
<p style="margin:0 0 16px;font-size:15px;line-height:22px;">Dans l’archive : ${escapeHtml(DATA_EXPORT_CONTENTS)}. Des fichiers JSON, lisibles par n’importe quel logiciel, et un récit en texte simple pour chaque voyage.</p>
<p style="margin:0;font-size:15px;line-height:22px;">Le lien sert plusieurs fois : si un téléchargement s’interrompt, relance-le.</p>
</td>
</tr>
<tr>
<td style="padding:0 24px 24px;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background:${COLORS.background};border-radius:14px;">
<tr><td style="padding:16px 20px;font-family:${font};font-size:13px;line-height:20px;color:${COLORS.inkMuted};">Le bouton ne s’ouvre pas ? Copie cette adresse dans ton navigateur :<br><span style="color:${COLORS.ink};word-break:break-all;">${escapeHtml(downloadUrl)}</span></td></tr>
</table>
</td>
</tr>
<tr>
<td style="padding:0 24px 32px;font-family:${font};color:${COLORS.ink};">
<p style="margin:0 0 16px;font-size:15px;line-height:22px;"><strong style="font-weight:600;">Ce lien ouvre toutes tes données</strong> : ne le transfère à personne.</p>
<p style="margin:0 0 16px;font-size:15px;line-height:22px;">Tu n’as rien demandé ? N’ouvre pas le lien, et réponds à cet e-mail : on regardera ce qui se passe sur ton compte.</p>
<p style="margin:0;font-size:15px;line-height:22px;">À bientôt,<br>L’équipe MemoBook</p>
</td>
</tr>
</table>
</td></tr>
</table>
</body>
</html>`;

  return { subject: DATA_EXPORT_SUBJECT, html, text };
}

/**
 * L'objet du rappel de fin de voyage. **Identique à celui du gabarit Resend
 * `subscription-reminder`** (`templates/emails/subscription-reminder.njk`),
 * pour la même raison que le mot de passe oublié — voir
 * `PASSWORD_RESET_SUBJECT`. Le journal des envois le retient aussi
 * (`notification_deliveries.title`).
 */
export const SUBSCRIPTION_REMINDER_SUBJECT = "Ton voyage est fini : pense à ton abonnement";

/** « à Rome » — mais « « Notre tour du monde » » quand on n'a qu'un titre. */
function tripPlaceOf(trip: { title: string; city: string | null }): string {
  return trip.city?.trim() ? `à ${trip.city.trim()}` : `« ${trip.title.trim()} »`;
}

/**
 * « jusqu’au 12 novembre 2026 » — la fin de la période payée. Sans la date,
 * on la nomme sans la chiffrer : c'est juste aussi pour un ancien abonné à la
 * semaine.
 */
export function subscriptionReminderUntil(unlimitedUntil: Date | null): string {
  return unlimitedUntil ? `jusqu’au ${frenchDate(unlimitedUntil)}` : "jusqu’à la fin de la période déjà payée";
}

/**
 * La dernière phrase : le carnet qui attend sa commande, ou — vide ou déjà
 * commandé — ce qu'il garde quoi qu'il décide. **Composée ici**, en une
 * chaîne : le gabarit Resend ne sait pas écrire de condition.
 */
export function subscriptionReminderBookLine(message: Pick<SubscriptionReminderMail, "trip" | "bookEstimateCents">): string {
  if (message.bookEstimateCents === null) {
    return "Quoi que tu décides, tes carnets et tes souvenirs restent à toi.";
  }
  return (
    `Et ton carnet ${tripPlaceOf(message.trip)} n’attend plus que ta commande : il est estimé à ` +
    `${formatEuros(message.bookEstimateCents)}. Ouvre l’app pour le feuilleter une dernière fois avant de le commander.`
  );
}

/**
 * « Ton voyage est fini : pense à ton abonnement » — `subscription.reminder`,
 * le lendemain de la fin d'un voyage (Hugo, 03/10/2026). Le jumeau de la
 * notification de fin de voyage et de l'alerte de l'accueil, pour qui ne les
 * voit pas.
 *
 * **Doux, et utile** : le voyage est fini, l'abonnement ne sert plus d'ici le
 * prochain, voici comment le couper sur l'iPhone, et ce qu'il garde — l'illimité
 * jusqu'au bout de ce qu'il a payé, ses carnets pour toujours. Pas d'urgence,
 * pas de reproche : on lui rend un service, on ne le relance pas.
 */
export function renderSubscriptionReminderMail(
  message: SubscriptionReminderMail,
  manageUrl: string,
): RenderedMail {
  const greeting = message.firstName ? `Bonjour ${message.firstName},` : "Bonjour,";
  const place = tripPlaceOf(message.trip);
  const until = subscriptionReminderUntil(message.unlimitedUntil);
  const bookLine = subscriptionReminderBookLine(message);
  const ended = `Ton voyage ${place} est terminé : on espère que tu en rapportes plein de souvenirs.`;
  const renewal =
    `Ton abonnement MemoBook, lui, se renouvelle tout seul. Si tu n’en as plus besoin d’ici ton prochain ` +
    `voyage, pense à le couper : tu gardes l’illimité ${until}.`;
  const path = "Réglages ▸ ton nom ▸ Abonnements ▸ MemoBook, puis « Annuler l’abonnement »";

  const text = [
    "MemoBook",
    "",
    SUBSCRIPTION_REMINDER_SUBJECT,
    "",
    greeting,
    "",
    ended,
    "",
    renewal,
    "",
    `Sur ton iPhone : ${path}. Ou directement ici :`,
    manageUrl,
    "",
    "Tu peux aussi le faire en un geste depuis l’accueil de l’app.",
    "",
    bookLine,
    "",
    "À bientôt,",
    "L’équipe MemoBook",
  ].join("\n");

  const font = "-apple-system,BlinkMacSystemFont,'Helvetica Neue',Helvetica,Arial,sans-serif";
  const html = `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(SUBSCRIPTION_REMINDER_SUBJECT)}</title>
</head>
<body style="margin:0;padding:0;background:${COLORS.background};">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background:${COLORS.background};">
<tr><td align="center" style="padding:32px 16px;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:480px;background:${COLORS.paper};border-radius:20px;overflow:hidden;">
<tr>
<td align="center" style="background:${COLORS.action};padding:40px 24px;">
<div style="font-family:Georgia,'Times New Roman',serif;font-size:36px;line-height:36px;font-weight:700;letter-spacing:2px;color:${COLORS.onAction};">MEMO<br>BOOK</div>
</td>
</tr>
<tr>
<td style="padding:32px 24px 8px;font-family:${font};color:${COLORS.ink};">
<h1 style="margin:0 0 24px;font-size:22px;line-height:28px;font-weight:700;">Ton voyage est fini</h1>
<p style="margin:0 0 16px;font-size:15px;line-height:22px;">${escapeHtml(greeting)}</p>
<p style="margin:0 0 16px;font-size:15px;line-height:22px;">${escapeHtml(ended)}</p>
<p style="margin:0 0 24px;font-size:15px;line-height:22px;">${escapeHtml(renewal)}</p>
</td>
</tr>
<tr>
<td style="padding:0 24px 24px;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background:${COLORS.background};border-radius:14px;">
<tr><td style="padding:16px 20px;font-family:${font};font-size:14px;line-height:21px;color:${COLORS.ink};"><strong style="font-weight:600;">Sur ton iPhone</strong><br>${escapeHtml(path)}.</td></tr>
</table>
</td>
</tr>
<tr>
<td align="center" style="padding:0 24px 24px;">
<a href="${escapeHtml(manageUrl)}" style="display:inline-block;background:${COLORS.action};color:${COLORS.onAction};text-decoration:none;font-family:${font};font-size:15px;font-weight:600;line-height:20px;padding:14px 28px;border-radius:12px;">Gérer mon abonnement</a>
<p style="margin:12px 0 0;font-family:${font};font-size:12px;line-height:16px;color:${COLORS.inkMuted};">Tu peux aussi le faire en un geste depuis l’accueil de l’app.</p>
</td>
</tr>
<tr>
<td style="padding:0 24px 32px;font-family:${font};color:${COLORS.ink};">
<p style="margin:0 0 16px;font-size:15px;line-height:22px;">${escapeHtml(bookLine)}</p>
<p style="margin:0;font-size:15px;line-height:22px;">À bientôt,<br>L’équipe MemoBook</p>
</td>
</tr>
</table>
</td></tr>
</table>
</body>
</html>`;

  return { subject: SUBSCRIPTION_REMINDER_SUBJECT, html, text };
}
