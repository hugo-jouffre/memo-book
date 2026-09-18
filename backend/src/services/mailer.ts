import { mkdirSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import type { Logger } from "pino";
import type { Env } from "../env.js";
import { publicApiBaseUrl } from "./avatars.js";
import { renderPasswordResetMail, type RenderedMail } from "./mailTemplates.js";

/**
 * Ce que le back-end sait envoyer par e-mail. Un message par cas d'usage, et
 * non un `send(to, subject, html)` générique : c'est ici que vivent les mots,
 * pas dans les routes.
 */
export interface Mailer {
  /**
   * « Mot de passe oublié » : le secret qui permet d'en choisir un nouveau.
   *
   * Le secret part **en clair** et une seule fois — la base n'en garde que
   * l'empreinte. Tout ce qui le reçoit doit le traiter comme un mot de passe.
   */
  sendPasswordReset(message: PasswordResetMail): Promise<void>;
}

export interface PasswordResetMail {
  to: string;
  /** Le prénom, pour ouvrir le message — `null` quand le compte n'en a pas. */
  firstName: string | null;
  token: string;
  expiresAt: Date;
}

/**
 * Le lien du bouton « Réinitialiser mon mot de passe ». En production, il mène
 * à la page `GET /password/reset` de l'API, qui **ouvre l'app** sur la feuille
 * du nouveau mot de passe — voir `APP_LINK_BASE_URL` dans `env.ts`,
 * `routes/passwordResetPage.ts`, et `PasswordResetLink` côté iOS, qui lit
 * exactement ce chemin, quel que soit le schéma devant.
 */
export function passwordResetUrl(env: Env, token: string): string {
  // **Sur Railway, l'adresse publique de l'API sans rien configurer** : la
  // variable n'y avait jamais été posée (18/09/2026), et l'e-mail partait
  // avec un lien `memobook://` que Gmail ne rend pas cliquable. Le schéma
  // d'app reste le repli du développement, où Railway n'est pas là.
  const link = env.APP_LINK_BASE_URL === "memobook://" && env.RAILWAY_PUBLIC_DOMAIN.trim()
    ? publicApiBaseUrl(env)
    : env.APP_LINK_BASE_URL;
  // `memobook://` garde ses deux barres ; `https://memo-book.com/app/` perd la
  // sienne. Le chemin est le même derrière : `password/reset`.
  const base = link.endsWith("://") ? link : link.replace(/\/+$/, "") + "/";
  return `${base}password/reset?token=${encodeURIComponent(token)}`;
}

interface Transport {
  send(to: string, mail: RenderedMail): Promise<void>;
}

function mailerOver(env: Env, transport: Transport): Mailer {
  return {
    async sendPasswordReset(message) {
      const mail = renderPasswordResetMail(message, passwordResetUrl(env, message.token));
      await transport.send(message.to, mail);
    },
  };
}

/**
 * Sans fournisseur : chaque message est **journalisé** — avec le lien, pour
 * l'ouvrir dans le simulateur (`xcrun simctl openurl booted '<lien>'`) — et
 * écrit en HTML dans `MAIL_OUTPUT_DIR`, pour le relire dans un navigateur.
 *
 * ⚠️ En production, ce serait écrire un secret dans les logs. Le serveur
 * refuse donc de démarrer avec ce mailer hors développement et test : voir
 * `createMailer`.
 */
export function createLoggingMailer(env: Env, logger: Logger): Mailer {
  return mailerOver(env, {
    async send(to, mail) {
      const link = /href="([^"]+)"/.exec(mail.html)?.[1] ?? "";
      let file: string | undefined;
      if (env.NODE_ENV !== "test") {
        const directory = resolve(env.MAIL_OUTPUT_DIR);
        mkdirSync(directory, { recursive: true });
        file = resolve(directory, `${Date.now()}-${to.replace(/[^\w.@-]/g, "_")}.html`);
        writeFileSync(file, mail.html);
      }
      logger.info(
        { mail: mail.subject, to, link, file },
        `✉️  ${mail.subject} → ${to}\n    ${link}${file ? `\n    ${file}` : ""}`,
      );
    },
  });
}

/**
 * Resend, par son API HTTP. Un `fetch` et rien d'autre : le SDK n'apporterait
 * qu'une dépendance pour un seul appel.
 */
export function createResendMailer(env: Env): Mailer {
  return mailerOver(env, {
    async send(to, mail) {
      const response = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${env.RESEND_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: env.MAIL_FROM,
          to: [to],
          subject: mail.subject,
          html: mail.html,
          text: mail.text,
        }),
      });
      if (!response.ok) {
        // Le corps de Resend dit pourquoi (domaine non vérifié, clé
        // révoquée) : il va dans l'erreur, donc dans les logs, jamais au client.
        const detail = await response.text().catch(() => "");
        throw new Error(`Resend a refusé l'envoi (${response.status}) : ${detail}`);
      }
    },
  });
}

export function createMailer(env: Env, logger: Logger): Mailer {
  if (env.RESEND_API_KEY !== "") return createResendMailer(env);

  if (env.NODE_ENV === "production") {
    // Pas de repli silencieux : un « mot de passe oublié » qui finit dans les
    // logs de production est à la fois une fuite et un e-mail jamais reçu.
    throw new Error(
      "RESEND_API_KEY est vide : impossible d'envoyer des e-mails en production.",
    );
  }
  return createLoggingMailer(env, logger);
}
