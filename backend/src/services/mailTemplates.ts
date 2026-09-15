import type { PasswordResetMail } from "./mailer.js";

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
 * « Réinitialisation de votre mot de passe » — les mots de la maquette
 * (Hugo, 15/09/2026), au tutoiement près dans le corps, qu'elle tutoie déjà.
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
    "Réinitialisation de votre mot de passe",
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
<title>Réinitialisation de votre mot de passe</title>
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
<h1 style="margin:0 0 24px;font-size:22px;line-height:28px;font-weight:700;">Réinitialisation de votre mot de passe</h1>
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

  return { subject: "Réinitialisation de votre mot de passe", html, text };
}
