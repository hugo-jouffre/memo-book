import type { Logger } from "pino";
import type { Env } from "../env.js";

export interface Mail {
  to: string;
  subject: string;
  /** Corps en texte brut. Le HTML viendra avec le gabarit d'email. */
  text: string;
}

export interface Mailer {
  send(mail: Mail): Promise<void>;
}

/**
 * Le courrier transactionnel n'a pas encore de fournisseur : la décision
 * (Postmark, Resend, SES…) n'est pas prise. En attendant, l'email part dans les
 * logs — le lien de réinitialisation reste lisible en développement, et le flow
 * complet est testable de bout en bout sans clé.
 *
 * ⚠️ Ce n'est pas utilisable en production : personne ne reçoit rien.
 */
export class LoggingMailer implements Mailer {
  constructor(private readonly logger: Logger) {}

  async send(mail: Mail): Promise<void> {
    this.logger.info({ to: mail.to, subject: mail.subject }, mail.text);
  }
}

/** Mailer des tests : garde ce qui a été envoyé, n'envoie rien. */
export class InMemoryMailer implements Mailer {
  readonly sent: Mail[] = [];

  async send(mail: Mail): Promise<void> {
    this.sent.push(mail);
  }
}

export function createMailer(_env: Env, logger: Logger): Mailer {
  return new LoggingMailer(logger);
}
