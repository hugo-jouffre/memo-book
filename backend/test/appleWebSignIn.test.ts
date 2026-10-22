import { createHash } from "node:crypto";
import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT, type JWK } from "jose";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { appleReturnPath, readApplePost } from "../src/routes/appleWebSignIn.js";
import { createSocialVerifier } from "../src/services/socialIdentity.js";
import { createHarness, testEnv, type TestHarness } from "./helpers.js";

/**
 * « Continuer avec Apple » sur Android, par la page web d'Apple (lot B2).
 *
 * Deux moitiés : la vérification du jeton, qui accepte désormais le Services ID
 * comme audience — testée ici avec une vraie signature, par une clé locale
 * à la place de celles d'Apple —, et le retour `form_post`, qui relaie le jeton
 * à l'app sans rien vérifier lui-même.
 */

const BUNDLE_ID = "com.memobook.app";
const SERVICES_ID = "com.memobook.app.web";

let privateKey: CryptoKey;
let jwks: ReturnType<typeof createLocalJWKSet>;

beforeAll(async () => {
  const pair = await generateKeyPair("RS256");
  privateKey = pair.privateKey;
  const jwk: JWK = { ...(await exportJWK(pair.publicKey)), kid: "test", alg: "RS256" };
  jwks = createLocalJWKSet({ keys: [jwk] });
});

function sha256Hex(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

async function appleToken(audience: string, nonce: string, subject = "000123.apple"): Promise<string> {
  return new SignJWT({ nonce, email: "hugo@privaterelay.appleid.com", email_verified: "true" })
    .setProtectedHeader({ alg: "RS256", kid: "test" })
    .setIssuer("https://appleid.apple.com")
    .setAudience(audience)
    .setSubject(subject)
    .setIssuedAt()
    .setExpirationTime("5m")
    .sign(privateKey);
}

function verifier(servicesId: string) {
  return createSocialVerifier(
    {
      APPLE_BUNDLE_ID: BUNDLE_ID,
      APPLE_SERVICES_ID: servicesId,
      GOOGLE_IOS_CLIENT_ID: "",
      GOOGLE_WEB_CLIENT_ID: "",
    },
    { apple: jwks },
  );
}

describe("jeton Apple : audiences", () => {
  it("accepte le bundle ID et le Services ID, avec le même sujet", async () => {
    const raw = "nonce-en-clair";
    const fromIphone = await verifier(SERVICES_ID).verifyApple(await appleToken(BUNDLE_ID, sha256Hex(raw)), raw);
    const fromAndroid = await verifier(SERVICES_ID).verifyApple(await appleToken(SERVICES_ID, sha256Hex(raw)), raw);

    // Le même `sub` des deux côtés : c'est ce qui retrouve le même compte —
    // à condition que le Services ID soit groupé sous l'App ID chez Apple.
    expect(fromIphone.subject).toBe("000123.apple");
    expect(fromAndroid.subject).toBe(fromIphone.subject);
    expect(fromAndroid.emailVerified).toBe(true);
  });

  it("refuse le Services ID tant qu'il n'est pas configuré", async () => {
    const raw = "n";
    await expect(
      verifier("").verifyApple(await appleToken(SERVICES_ID, sha256Hex(raw)), raw),
    ).rejects.toMatchObject({ statusCode: 401 });
  });

  it("refuse un jeton émis pour une autre app", async () => {
    const raw = "n";
    await expect(
      verifier(SERVICES_ID).verifyApple(await appleToken("com.autre.app", sha256Hex(raw)), raw),
    ).rejects.toMatchObject({ statusCode: 401 });
  });

  it("refuse un nonce qui n'est pas celui de la tentative", async () => {
    await expect(
      verifier(SERVICES_ID).verifyApple(await appleToken(SERVICES_ID, sha256Hex("le bon")), "un autre"),
    ).rejects.toMatchObject({ statusCode: 401 });
  });
});

describe("retour form_post d'Apple : lecture", () => {
  it("garde le nom et l'adresse du premier consentement", () => {
    const result = readApplePost({
      id_token: "jwt",
      code: "ignoré",
      state: "s-1",
      user: JSON.stringify({ name: { firstName: "Hugo", lastName: "Jouffre" }, email: "hugo@example.com" }),
    });
    expect(result).toEqual({
      idToken: "jwt",
      state: "s-1",
      firstName: "Hugo",
      lastName: "Jouffre",
      email: "hugo@example.com",
    });
    expect(appleReturnPath(result)).toBe(
      "auth/apple?id_token=jwt&state=s-1&first_name=Hugo&last_name=Jouffre&email=hugo%40example.com",
    );
  });

  it("se passe du `user` aux connexions suivantes", () => {
    expect(appleReturnPath(readApplePost({ id_token: "jwt", state: "s" }))).toBe("auth/apple?id_token=jwt&state=s");
  });

  it("survit à un `user` illisible", () => {
    const result = readApplePost({ id_token: "jwt", state: "s", user: "{pas du json" });
    expect(result).toMatchObject({ idToken: "jwt", firstName: null, lastName: null, email: null });
  });

  it("encode les espaces en %20, que `java.net.URI` décode", () => {
    const path = appleReturnPath(
      readApplePost({ id_token: "jwt", state: "s", user: JSON.stringify({ name: { firstName: "Marie Claire" } }) }),
    );
    expect(path).toContain("first_name=Marie%20Claire");
  });

  it("relaie l'abandon et l'absence de jeton comme des erreurs", () => {
    expect(appleReturnPath(readApplePost({ error: "user_cancelled_authorize", state: "s" }))).toBe(
      "auth/apple?error=user_cancelled_authorize&state=s",
    );
    expect(appleReturnPath(readApplePost({ id_token: "jwt" }))).toBe("auth/apple?error=invalid_request");
    expect(appleReturnPath(readApplePost({ state: "s" }))).toBe("auth/apple?error=invalid_request&state=s");
  });
});

describe("retour form_post d'Apple : la route", () => {
  let harness: TestHarness;

  afterAll(async () => {
    await harness?.close();
  });

  async function boot(servicesId: string) {
    if (harness) await harness.close();
    harness = await createHarness({ env: { ...testEnv(), APPLE_SERVICES_ID: servicesId } });
  }

  function post(body: Record<string, string>) {
    return harness.app.inject({
      method: "POST",
      url: "/v1/auth/apple/callback",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      payload: new URLSearchParams(body).toString(),
    });
  }

  it("rend une page qui ouvre l'app avec le jeton et le nom", async () => {
    await boot(SERVICES_ID);
    const response = await post({
      id_token: "eyJ.jeton.signé",
      state: "s-42",
      code: "c",
      user: JSON.stringify({ name: { firstName: "Hugo", lastName: "Jouffre" } }),
    });

    expect(response.statusCode).toBe(200);
    expect(response.headers["content-type"]).toContain("text/html");
    expect(response.headers["cache-control"]).toBe("no-store");
    expect(response.headers["referrer-policy"]).toBe("no-referrer");
    const path = "auth/apple?id_token=eyJ.jeton.sign%C3%A9&state=s-42&first_name=Hugo&last_name=Jouffre";
    expect(response.body).toContain(`memobook://${path}`);
    // L'`intent://` de Chrome, la seule forme qu'il ouvre sur Android.
    expect(response.body).toContain(`intent://${path}#Intent;scheme=memobook;package=com.memobook.app;end`);
  });

  it("garde le formulaire hors des autres routes", async () => {
    await boot(SERVICES_ID);
    const json = await harness.app.inject({
      method: "POST",
      url: "/v1/auth/google",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      payload: "identityToken=x",
    });
    // Le parseur du formulaire ne vaut que pour le retour d'Apple.
    expect(json.statusCode).toBe(415);
  });

  it("est coupée tant que le Services ID n'est pas posé", async () => {
    await boot("");
    const response = await post({ id_token: "jwt", state: "s" });
    expect(response.statusCode).toBe(404);
  });
});
