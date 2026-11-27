import { describe, expect, it } from "vitest";
import { serializeChatMessage } from "./chatSerializers.js";

/**
 * **Le format de chaque photo part avec le fil** (T305) : sans lui, la bulle
 * range tout en carrés, et c'est précisément ce qu'on vient de corriger.
 */
const bubble = {
  id: "bulle",
  memoId: "memo",
  author: "traveller",
  kind: "photos",
  text: null,
  payload: { entryIds: ["photo-1", "photo-2"] },
  entryId: "photo-1",
  stepId: null,
  seq: 1,
  createdAt: new Date("2026-11-27T10:00:00Z"),
  postedAt: new Date("2026-11-27T10:00:00Z"),
  entry: null,
  account: null,
} as unknown as Parameters<typeof serializeChatMessage>[0];

describe("les photos d'une bulle", () => {
  it("portent le format que le serveur a mesuré", () => {
    const message = serializeChatMessage(bubble, {
      viewerAccountId: "moi",
      showsAuthors: false,
      publicBaseUrl: "https://exemple.test",
      viewerIsUnlimited: true,
      photoSizes: new Map([
        ["photo-1", { widthPx: 2400, heightPx: 1602 }],
        ["photo-2", { widthPx: 1602, heightPx: 2400 }],
      ]),
    });

    const body = message?.body as { kind: string; photos: { id: string; widthPx?: number }[] };
    expect(body.kind).toBe("photos");
    expect(body.photos.map((photo) => photo.widthPx)).toEqual([2400, 1602]);
  });

  /** Une photo que le serveur n'a pas su mesurer n'en porte pas, et la bulle la range carrée. */
  it("se taisent quand la mesure manque", () => {
    const message = serializeChatMessage(bubble, {
      viewerAccountId: "moi",
      showsAuthors: false,
      publicBaseUrl: "https://exemple.test",
      viewerIsUnlimited: true,
    });
    const body = message?.body as { photos: Record<string, unknown>[] };
    expect(body.photos[0]).not.toHaveProperty("widthPx");
  });
});
