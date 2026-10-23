import { generateKeyPairSync } from "node:crypto";
import { decodeJwt, decodeProtectedHeader } from "jose";
import { describe, expect, it } from "vitest";
import { DisabledPushSender, LoggingPushSender, RoutingPushSender, type PushMessage } from "./apns.js";
import { FcmPushSender, fcmMessage, readFcmCredentials, type FcmCredentials } from "./fcm.js";

/**
 * FCM sans Google : `fetch` est un double qui répond comme `oauth2.googleapis.com`
 * et `fcm.googleapis.com`, et retient ce qu'on lui envoie.
 */

const MESSAGE: PushMessage = {
  deliveryId: "d-1",
  title: "Titre",
  body: "Texte",
  link: "memobook://paywall",
  threadId: "memo-1",
};

function credentials(): FcmCredentials {
  const { privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  return {
    serviceAccount: {
      client_email: "fcm@memobook-test.iam.gserviceaccount.com",
      private_key: privateKey.export({ type: "pkcs8", format: "pem" }).toString(),
      token_uri: "https://oauth2.googleapis.com/token",
    },
    projectId: "memobook-test",
  };
}

interface Call {
  url: string;
  init: RequestInit;
  /** Le corps envoyé, en texte : un formulaire ou du JSON. */
  body: string;
}

/** Google, rejoué : un jeton d'accès, puis les réponses d'envoi données dans l'ordre. */
function fakeGoogle(...sends: { status: number; body?: unknown }[]) {
  const calls: Call[] = [];
  const fetcher = (async (url: string | URL, init?: RequestInit) => {
    calls.push({ url: String(url), init: init ?? {}, body: typeof init?.body === "string" ? init.body : "" });
    if (String(url).startsWith("https://oauth2.googleapis.com/")) {
      return Response.json({ access_token: `acces-${calls.length}`, expires_in: 3599 });
    }
    const next = sends.shift() ?? { status: 200, body: { name: "projects/memobook-test/messages/1" } };
    return new Response(JSON.stringify(next.body ?? {}), { status: next.status });
  }) as typeof fetch;
  return { calls, fetcher };
}

describe("la charge utile FCM", () => {
  it("est un message de données seulement, avec les clés de la charge APNs", () => {
    expect(fcmMessage("jeton", MESSAGE)).toEqual({
      message: {
        token: "jeton",
        data: { title: "Titre", body: "Texte", link: "memobook://paywall", deliveryId: "d-1", threadId: "memo-1" },
        android: { priority: "high", ttl: "86400s" },
      },
    });
  });

  it("n'envoie pas de lien nul : FCM ne prend que des chaînes", () => {
    const { message } = fcmMessage("jeton", { ...MESSAGE, link: null }) as { message: { data: object } };
    expect(message.data).not.toHaveProperty("link");
  });
});

describe("l'envoi à FCM", () => {
  it("échange un JWT du compte de service contre un jeton d'accès, et le garde", async () => {
    const google = fakeGoogle();
    const sender = new FcmPushSender(credentials(), { warn: () => {} }, google.fetcher);
    const destination = { token: "jeton:Casse", environment: "production" as const, provider: "fcm" as const };

    expect(await sender.send(destination, MESSAGE)).toEqual({ kind: "sent" });
    expect(await sender.send(destination, MESSAGE)).toEqual({ kind: "sent" });

    const [exchange, first, second] = google.calls;
    expect(google.calls).toHaveLength(3);
    const form = new URLSearchParams(exchange?.body);
    expect(form.get("grant_type")).toBe("urn:ietf:params:oauth:grant-type:jwt-bearer");
    const assertion = form.get("assertion") ?? "";
    expect(decodeProtectedHeader(assertion)).toMatchObject({ alg: "RS256" });
    expect(decodeJwt(assertion)).toMatchObject({
      iss: "fcm@memobook-test.iam.gserviceaccount.com",
      aud: "https://oauth2.googleapis.com/token",
      scope: "https://www.googleapis.com/auth/firebase.messaging",
    });

    expect(first?.url).toBe("https://fcm.googleapis.com/v1/projects/memobook-test/messages:send");
    expect((first?.init.headers as Record<string, string>).authorization).toBe("Bearer acces-1");
    expect((JSON.parse(first?.body ?? "{}") as { message: { token: string } }).message.token).toBe("jeton:Casse");
    expect(second?.url).toBe(first?.url);
  });

  it("oublie un jeton que Firebase ne connaît plus, et garde celui d'une panne", async () => {
    const google = fakeGoogle(
      {
        status: 404,
        body: {
          error: {
            status: "NOT_FOUND",
            details: [{ "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError", errorCode: "UNREGISTERED" }],
          },
        },
      },
      { status: 503, body: { error: { status: "UNAVAILABLE" } } },
      { status: 400, body: { error: { status: "INVALID_ARGUMENT" } } },
    );
    const sender = new FcmPushSender(credentials(), { warn: () => {} }, google.fetcher);
    const destination = { token: "jeton", environment: "production" as const, provider: "fcm" as const };

    expect(await sender.send(destination, MESSAGE)).toEqual({ kind: "invalid_token", reason: "UNREGISTERED" });
    expect(await sender.send(destination, MESSAGE)).toEqual({ kind: "failed", reason: "UNAVAILABLE" });
    expect(await sender.send(destination, MESSAGE)).toEqual({ kind: "failed", reason: "INVALID_ARGUMENT" });
  });

  it("redemande un jeton d'accès quand Google refuse le sien, et le dit", async () => {
    const warnings: string[] = [];
    const google = fakeGoogle({ status: 401, body: { error: { status: "UNAUTHENTICATED" } } });
    const sender = new FcmPushSender(credentials(), { warn: (_: unknown, text: string) => warnings.push(text) } as never, google.fetcher);
    const destination = { token: "jeton", environment: "production" as const, provider: "fcm" as const };

    expect(await sender.send(destination, MESSAGE)).toEqual({ kind: "failed", reason: "UNAUTHENTICATED" });
    expect(warnings).toHaveLength(1);
    await sender.send(destination, MESSAGE);
    expect(google.calls.filter((call) => call.url.startsWith("https://oauth2.")).length).toBe(2);
  });
});

describe("les variables de FCM", () => {
  const account = { client_email: "fcm@x.iam.gserviceaccount.com", private_key: "-----BEGIN PRIVATE KEY-----\\nAAA\\n-----END PRIVATE KEY-----\\n", project_id: "memobook-prod" };

  it("vides : FCM coupé, sans erreur", () => {
    expect(readFcmCredentials("", "")).toBeNull();
    expect(readFcmCredentials("   ", "memobook")).toBeNull();
  });

  it("prend le projet du JSON quand FCM_PROJECT_ID est vide, et rend ses retours à la clé", () => {
    const read = readFcmCredentials(JSON.stringify(account), "");
    expect(read).toMatchObject({ credentials: { projectId: "memobook-prod" } });
    expect(read && "credentials" in read && read.credentials.serviceAccount.private_key).toContain("\nAAA\n");
    expect(readFcmCredentials(JSON.stringify(account), "autre")).toMatchObject({ credentials: { projectId: "autre" } });
  });

  it("dit ce qui ne va pas dans un JSON mal collé", () => {
    const errorOf = (json: string) => {
      const read = readFcmCredentials(json, "");
      return read && "error" in read ? read.error : null;
    };
    expect(errorOf("{pas du json")).toContain("JSON");
    expect(errorOf(JSON.stringify({ project_id: "p" }))).toContain("client_email");
    expect(errorOf(JSON.stringify({ ...account, project_id: undefined }))).toContain("FCM_PROJECT_ID");
  });
});

describe("APNs et FCM derrière un seul expéditeur", () => {
  it("envoie chaque jeton à son fournisseur", async () => {
    const apns = new LoggingPushSender(null);
    const fcm = new LoggingPushSender(null);
    const router = new RoutingPushSender(apns, fcm);

    await router.send({ token: "a".repeat(64), environment: "sandbox", provider: "apns" }, MESSAGE);
    await router.send({ token: "jeton:fcm", environment: "production", provider: "fcm" }, MESSAGE);

    expect(apns.sent.map((entry) => entry.destination.token)).toEqual(["a".repeat(64)]);
    expect(fcm.sent.map((entry) => entry.destination.token)).toEqual(["jeton:fcm"]);
  });

  it("peut envoyer dès que l'un des deux le peut ; l'autre échoue sans rien marquer", async () => {
    const router = new RoutingPushSender(new LoggingPushSender(null), new DisabledPushSender("FCM n'est pas configuré."));
    expect(router.enabled).toBe(true);
    expect(await router.send({ token: "jeton", environment: "production", provider: "fcm" }, MESSAGE)).toEqual({
      kind: "failed",
      reason: "FCM n'est pas configuré.",
    });
    expect(new RoutingPushSender(new DisabledPushSender(), new DisabledPushSender()).enabled).toBe(false);
  });
});
