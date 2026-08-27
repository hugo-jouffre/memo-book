import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { hashToken } from "../src/lib/auth.js";
import { InMemoryMailer } from "../src/services/mailer.js";
import { createHarness, registerDevice, resetDatabase, type TestHarness } from "./helpers.js";

const account = {
  firstName: "Cla",
  lastName: "Thioll",
  email: "cla.thioll@gmail.com",
  password: "carnet2026",
};

/** Corps d'une session ouverte, tel que l'app le reçoit. */
interface SessionBody {
  userId: string;
  sessionToken: string;
  hasSeenOnboarding: boolean;
}

function post(app: FastifyInstance, url: string, payload: Record<string, unknown>) {
  return app.inject({ method: "POST", url, payload });
}

describe("comptes et authentification", () => {
  let harness: TestHarness;
  let mailer: InMemoryMailer;

  beforeAll(async () => {
    mailer = new InMemoryMailer();
    harness = await createHarness({ mailer });
  });

  afterAll(async () => {
    await harness.close();
  });

  beforeEach(async () => {
    await resetDatabase(harness.prisma);
    mailer.sent.length = 0;
  });

  describe("inscription", () => {
    it("crée le compte, ouvre une session et ne stocke jamais le mot de passe en clair", async () => {
      const response = await post(harness.app, "/v1/auth/signup", account);
      expect(response.statusCode).toBe(201);

      const body = response.json<SessionBody>();
      expect(body.sessionToken).toBeTruthy();
      expect(body.hasSeenOnboarding).toBe(false);

      const user = await harness.prisma.user.findUniqueOrThrow({
        where: { id: body.userId },
      });
      expect(user.email).toBe(account.email);
      expect(user.passwordHash).not.toBeNull();
      expect(user.passwordHash).not.toContain(account.password);
      expect(user.passwordHash?.startsWith("$argon2id$")).toBe(true);
    });

    it("range l'email en minuscules et refuse un doublon quelle que soit la casse", async () => {
      await post(harness.app, "/v1/auth/signup", account);

      const response = await post(harness.app, "/v1/auth/signup", {
        ...account,
        email: "Cla.Thioll@GMAIL.com",
      });

      expect(response.statusCode).toBe(409);
      expect(response.json<{ error: string }>().error).toBe("conflict");
    });

    it("refuse un mot de passe qui ne tient pas la politique", async () => {
      const response = await post(harness.app, "/v1/auth/signup", {
        ...account,
        password: "court1",
      });

      expect(response.statusCode).toBe(400);
      expect(response.json<{ error: string }>().error).toBe("too_short");
    });

    it("emporte les carnets de l'appareil anonyme dans le nouveau compte", async () => {
      const device = await registerDevice(harness.app);
      await harness.app.inject({
        method: "POST",
        url: "/v1/memos",
        headers: { authorization: device.authorization },
        payload: { title: "Colombie" },
      });

      const signup = await post(harness.app, "/v1/auth/signup", {
        ...account,
        deviceToken: device.authorization.replace("Bearer ", ""),
      });
      const { sessionToken } = signup.json<SessionBody>();

      const memos = await harness.app.inject({
        method: "GET",
        url: "/v1/memos",
        headers: { authorization: `Bearer ${sessionToken}` },
      });

      expect(memos.json<{ memos: { title: string }[] }>().memos).toHaveLength(1);
      expect(memos.json<{ memos: { title: string }[] }>().memos[0]?.title).toBe("Colombie");
    });
  });

  describe("connexion", () => {
    beforeEach(async () => {
      await post(harness.app, "/v1/auth/signup", account);
    });

    it("ouvre une session avec les bons identifiants", async () => {
      const response = await post(harness.app, "/v1/auth/login", {
        email: account.email,
        password: account.password,
      });

      expect(response.statusCode).toBe(200);
      expect(response.json<SessionBody>().sessionToken).toBeTruthy();
    });

    it("renvoie le même message générique que l'email existe ou non", async () => {
      const wrongPassword = await post(harness.app, "/v1/auth/login", {
        email: account.email,
        password: "carnet2027",
      });
      const unknownEmail = await post(harness.app, "/v1/auth/login", {
        email: "personne@exemple.fr",
        password: account.password,
      });

      expect(wrongPassword.statusCode).toBe(401);
      expect(unknownEmail.statusCode).toBe(401);
      expect(wrongPassword.json()).toEqual(unknownEmail.json());
    });

    it("remonte le flag d'onboarding vu localement, et ne le redescend jamais", async () => {
      const seen = await post(harness.app, "/v1/auth/login", {
        email: account.email,
        password: account.password,
        hasSeenOnboarding: true,
      });
      expect(seen.json<SessionBody>().hasSeenOnboarding).toBe(true);

      const later = await post(harness.app, "/v1/auth/login", {
        email: account.email,
        password: account.password,
        hasSeenOnboarding: false,
      });
      expect(later.json<SessionBody>().hasSeenOnboarding).toBe(true);
    });

    it("rattache un deuxième appareil au compte et lui rend les carnets du premier", async () => {
      const first = await registerDevice(harness.app);
      const login = await post(harness.app, "/v1/auth/login", {
        email: account.email,
        password: account.password,
        deviceToken: first.authorization.replace("Bearer ", ""),
      });
      const session = login.json<SessionBody>();

      await harness.app.inject({
        method: "POST",
        url: "/v1/memos",
        headers: { authorization: `Bearer ${session.sessionToken}` },
        payload: { title: "Colombie" },
      });

      const second = await registerDevice(harness.app);
      const onSecondPhone = await post(harness.app, "/v1/auth/login", {
        email: account.email,
        password: account.password,
        deviceToken: second.authorization.replace("Bearer ", ""),
      });

      const memos = await harness.app.inject({
        method: "GET",
        url: "/v1/memos",
        headers: {
          authorization: `Bearer ${onSecondPhone.json<SessionBody>().sessionToken}`,
        },
      });

      expect(memos.json<{ memos: unknown[] }>().memos).toHaveLength(1);
    });
  });

  describe("session", () => {
    it("laisse GET /v1/auth/me répondre tant que la session est valide", async () => {
      const signup = await post(harness.app, "/v1/auth/signup", account);
      const { sessionToken } = signup.json<SessionBody>();

      const me = await harness.app.inject({
        method: "GET",
        url: "/v1/auth/me",
        headers: { authorization: `Bearer ${sessionToken}` },
      });

      expect(me.statusCode).toBe(200);
      expect(me.json<{ user: { email: string } }>().user.email).toBe(account.email);
    });

    it("refuse une session expirée", async () => {
      const signup = await post(harness.app, "/v1/auth/signup", account);
      const { sessionToken } = signup.json<SessionBody>();

      await harness.prisma.session.update({
        where: { tokenHash: hashToken(sessionToken) },
        data: { expiresAt: new Date(Date.now() - 1000) },
      });

      const me = await harness.app.inject({
        method: "GET",
        url: "/v1/auth/me",
        headers: { authorization: `Bearer ${sessionToken}` },
      });

      expect(me.statusCode).toBe(401);
    });

    it("ferme la session sur déconnexion", async () => {
      const signup = await post(harness.app, "/v1/auth/signup", account);
      const { sessionToken } = signup.json<SessionBody>();
      const authorization = `Bearer ${sessionToken}`;

      const logout = await harness.app.inject({
        method: "POST",
        url: "/v1/auth/logout",
        headers: { authorization },
      });
      expect(logout.statusCode).toBe(204);

      const me = await harness.app.inject({
        method: "GET",
        url: "/v1/auth/me",
        headers: { authorization },
      });
      expect(me.statusCode).toBe(401);
    });
  });

  describe("mot de passe oublié", () => {
    beforeEach(async () => {
      await post(harness.app, "/v1/auth/signup", account);
    });

    it("envoie un lien de deep link et répond sans attendre l'envoi", async () => {
      const response = await post(harness.app, "/v1/auth/forgot-password", {
        email: account.email,
      });

      expect(response.statusCode).toBe(200);
      expect(response.json()).toEqual({ message: "email_sent" });

      // L'envoi part sans être attendu : on laisse la microtâche se dérouler.
      await new Promise((resolve) => setImmediate(resolve));
      expect(mailer.sent).toHaveLength(1);
      expect(mailer.sent[0]?.text).toContain("memobook://reset-password?token=");
    });

    it("distingue l'adresse sans compte, pour l'écran qui propose d'en créer un", async () => {
      const response = await post(harness.app, "/v1/auth/forgot-password", {
        email: "personne@exemple.fr",
      });

      expect(response.statusCode).toBe(404);
      expect(response.json<{ error: string }>().error).toBe("not_found");
    });

    it("change le mot de passe, invalide le lien et ferme les sessions ouvertes", async () => {
      const login = await post(harness.app, "/v1/auth/login", {
        email: account.email,
        password: account.password,
      });
      const openSessionToken = login.json<SessionBody>().sessionToken;

      await post(harness.app, "/v1/auth/forgot-password", { email: account.email });
      await new Promise((resolve) => setImmediate(resolve));
      const token = /token=([\w-]+)/.exec(mailer.sent[0]?.text ?? "")?.[1];
      expect(token).toBeTruthy();

      const reset = await post(harness.app, "/v1/auth/reset-password", {
        token,
        newPassword: "nouveaucarnet2026",
      });
      expect(reset.json()).toEqual({ message: "password_updated" });

      const withNewPassword = await post(harness.app, "/v1/auth/login", {
        email: account.email,
        password: "nouveaucarnet2026",
      });
      expect(withNewPassword.statusCode).toBe(200);

      const reused = await post(harness.app, "/v1/auth/reset-password", {
        token,
        newPassword: "encoreautre2026",
      });
      expect(reused.statusCode).toBe(400);
      expect(reused.json<{ error: string }>().error).toBe("invalid_or_expired_token");

      const staleSession = await harness.app.inject({
        method: "GET",
        url: "/v1/auth/me",
        headers: { authorization: `Bearer ${openSessionToken}` },
      });
      expect(staleSession.statusCode).toBe(401);
    });

    it("refuse un lien périmé", async () => {
      await post(harness.app, "/v1/auth/forgot-password", { email: account.email });
      await new Promise((resolve) => setImmediate(resolve));
      const token = /token=([\w-]+)/.exec(mailer.sent[0]?.text ?? "")?.[1] ?? "";

      await harness.prisma.passwordReset.update({
        where: { tokenHash: hashToken(token) },
        data: { expiresAt: new Date(Date.now() - 1000) },
      });

      const response = await post(harness.app, "/v1/auth/reset-password", {
        token,
        newPassword: "nouveaucarnet2026",
      });

      expect(response.statusCode).toBe(400);
      expect(response.json<{ error: string }>().error).toBe("invalid_or_expired_token");
    });
  });

  describe("connexion par un fournisseur tiers", () => {
    it("demande de compléter le profil quand l'identité est inconnue", async () => {
      const response = await post(harness.app, "/v1/auth/social/apple", {
        credential: "apple:001.abcdef",
      });

      expect(response.statusCode).toBe(200);
      const body = response.json<{ status: string; socialToken: string; email: null }>();
      expect(body.status).toBe("profile_required");
      expect(body.socialToken).toBe("apple:001.abcdef");
      expect(body.email).toBeNull();
    });

    it("pré-remplit ce que le fournisseur a transmis", async () => {
      const response = await post(harness.app, "/v1/auth/social/google", {
        credential: "google:g-42|cla@exemple.fr|Cla|Thioll",
      });

      const body = response.json<{ firstName: string; email: string }>();
      expect(body.firstName).toBe("Cla");
      expect(body.email).toBe("cla@exemple.fr");
    });

    it("accepte un email relais Apple tel quel", async () => {
      const response = await post(harness.app, "/v1/auth/social/complete", {
        socialToken: "apple:001.abcdef",
        firstName: "Cla",
        lastName: "Thioll",
        email: "xk29fj@privaterelay.appleid.com",
      });

      expect(response.statusCode).toBe(201);
      const user = await harness.prisma.user.findUniqueOrThrow({
        where: { id: response.json<SessionBody>().userId },
      });
      expect(user.email).toBe("xk29fj@privaterelay.appleid.com");
      expect(user.passwordHash).toBeNull();
    });

    it("connecte directement une identité déjà connue", async () => {
      await post(harness.app, "/v1/auth/social/complete", {
        socialToken: "apple:001.abcdef",
        firstName: "Cla",
        lastName: "Thioll",
        email: account.email,
      });

      const response = await post(harness.app, "/v1/auth/social/apple", {
        credential: "apple:001.abcdef",
      });

      expect(response.json<{ status: string }>().status).toBe("signed_in");
      expect(response.json<SessionBody>().sessionToken).toBeTruthy();
    });

    it("refuse une adresse déjà prise par un autre compte", async () => {
      await post(harness.app, "/v1/auth/signup", account);

      const response = await post(harness.app, "/v1/auth/social/complete", {
        socialToken: "facebook:fb-7",
        firstName: "Cla",
        lastName: "Thioll",
        email: account.email,
      });

      expect(response.statusCode).toBe(409);
    });
  });
});
