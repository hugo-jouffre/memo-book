import { describe, expect, it } from "vitest";
import { isNewPurchase, storeKitState } from "./appStoreSubscriptions.js";

const transaction = (purchasedAt: Date) => ({
  transactionId: "t2",
  originalTransactionId: "o1",
  productId: "com.memobook.app.unlimited.monthly",
  appAccountToken: null,
  purchasedAt,
  expiresAt: new Date("2026-11-18T10:00:00Z"),
  revokedAt: null,
  priceCents: 499,
  currency: "EUR",
  environment: "Sandbox",
  signedAt: purchasedAt,
});

describe("se réabonner après une résiliation", () => {
  const resiliation = new Date("2026-10-10T10:00:00Z");

  it("un achat postérieur au dernier état connu réarme le renouvellement", () => {
    const achat = transaction(new Date("2026-10-18T10:00:00Z"));
    expect(isNewPurchase(achat, { providerUpdatedAt: resiliation })).toBe(true);
    const state = storeKitState({
      transaction: achat,
      renewal: null,
      status: null,
      previousAutoRenews: null,
      now: new Date("2026-10-18T10:05:00Z"),
    });
    expect(state.status).toBe("active");
  });

  it("un vieux renouvellement rejoué garde ce qu'on savait", () => {
    expect(isNewPurchase(transaction(new Date("2026-10-01T10:00:00Z")), { providerUpdatedAt: resiliation })).toBe(false);
    expect(isNewPurchase(transaction(new Date("2026-10-01T10:00:00Z")), null)).toBe(false);
  });
});
