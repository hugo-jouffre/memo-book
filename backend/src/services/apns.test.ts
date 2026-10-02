import { generateKeyPairSync } from "node:crypto";
import { decodeProtectedHeader, decodeJwt } from "jose";
import { describe, expect, it } from "vitest";
import { apnsPayload, normalizePrivateKey } from "./apns.js";

describe("la charge utile APNs", () => {
  it("porte le texte dans `aps`, et à côté ce que l'app lit au toucher", () => {
    expect(
      apnsPayload({ deliveryId: "d-1", title: "Titre", body: "Texte", link: "memobook://paywall", threadId: "memobook" }),
    ).toEqual({
      aps: { alert: { title: "Titre", body: "Texte" }, sound: "default", "thread-id": "memobook" },
      link: "memobook://paywall",
      deliveryId: "d-1",
    });
  });
});

describe("la clé .p8 lue dans une variable d'environnement", () => {
  it("rend leurs retours à la ligne aux clés écrites sur une seule ligne", async () => {
    const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
    const pem = privateKey.export({ type: "pkcs8", format: "pem" }).toString();
    const oneLine = pem.trim().replace(/\n/g, "\\n");

    expect(normalizePrivateKey(oneLine)).toBe(pem.trim());

    // Et elle signe le jeton qu'APNs attend : ES256, `kid`, `iss`, `iat`.
    const { ApnsPushSender } = await import("./apns.js");
    const sender = new ApnsPushSender(
      { keyId: "ABC123DEFG", teamId: "HP2A94889S", privateKey: normalizePrivateKey(oneLine), topic: "com.memobook.app" },
      { warn: () => {} },
    );
    const token = await (sender as unknown as { currentProviderToken(): Promise<string> }).currentProviderToken();
    expect(decodeProtectedHeader(token)).toEqual({ alg: "ES256", kid: "ABC123DEFG" });
    expect(decodeJwt(token)).toMatchObject({ iss: "HP2A94889S" });
  });

  it("rend son armure PEM à une clé collée sans ses lignes d'en-tête", () => {
    const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
    const pem = privateKey.export({ type: "pkcs8", format: "pem" }).toString().trim();
    const bodyOnly = pem.split("\n").slice(1, -1).join("\n");

    expect(normalizePrivateKey(bodyOnly)).toBe(pem);
    expect(normalizePrivateKey(bodyOnly.replace(/\n/g, "\\n"))).toBe(pem);
    expect(normalizePrivateKey("")).toBe("");
  });
});
