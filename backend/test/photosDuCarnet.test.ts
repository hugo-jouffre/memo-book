import { createServer, type Server } from "node:http";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import type { AddressInfo } from "node:net";
import { Jimp } from "jimp";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { renderBookPdf } from "../src/services/bookPdf.js";
import { toRenderablePhoto } from "../src/services/photoFormat.js";

/**
 * **Les photos arrivent dans le carnet** (Hugo, 11/11/2026 — « lors de la
 * confection des PDF, les photos n'apparaissent pas »).
 *
 * Ce fichier tient le diagnostic, pas seulement le correctif : il compose un
 * vrai carnet avec le Chromium du rendu, et montre que du HEIC servi sous un
 * nom en `.jpg` — ce que l'app envoyait, la photothèque d'un iPhone n'ayant
 * rien d'autre — **ne se peint pas**, quand la même photo convertie se peint.
 *
 * C'est la panne la plus discrète du pipeline : l'`<img>` se déclare
 * `complete`, n'émet aucune erreur, et reste à `naturalWidth: 0`. Rien ne
 * distingue alors un carnet sans photos d'un carnet sans photo à mettre.
 */

const HEIC = readFileSync(
  resolve(new URL("./fixtures/photos/heic-iphone.heic", import.meta.url).pathname),
);

/**
 * Le test demande le navigateur, que le job de tests de la CI n'installe pas.
 * Sans lui il se saute, comme `pdfVector.test.ts` et la suite visuelle : mieux
 * vaut une vérification absente qu'une vérification qui ment.
 *
 * ⚠️ On **lance** le navigateur pour le savoir, au lieu de regarder
 * `chromium.executablePath()` comme le font les deux autres : ce chemin est
 * celui du Chromium complet, que `npx playwright install` ne pose pas quand
 * seul le *headless shell* est demandé — celui-là même que `launch()` emploie.
 * Le test se sautait donc aussi sur une machine parfaitement équipée.
 */
async function chromiumAvailable(): Promise<boolean> {
  try {
    const { chromium } = await import("playwright-core");
    const browser = await chromium.launch();
    await browser.close();
    return true;
  } catch {
    return false;
  }
}

let server: Server;
let base: string;

/** Un carnet d'une page, dont la seule page est une planche de photos. */
function payloadWith(urls: readonly string[]): Record<string, unknown> {
  return {
    book_title: "Les photos du carnet",
    authors: "Test",
    date_range: "2026",
    days: [
      {
        title: "Une page de photos",
        layout_photo_page: true,
        body_html: "",
        photos: urls.map((url) => ({ url, tape_corner: "top-left", focus: "50% 50%" })),
      },
    ],
  };
}

describe.runIf(await chromiumAvailable())("les photos du carnet", () => {
  beforeAll(async () => {
    const jpeg = Buffer.from(
      await new Jimp({ width: 1200, height: 900, color: 0x3fa7d6ff }).getBuffer("image/jpeg"),
    );
    const converted = await toRenderablePhoto(HEIC, "photo.heic", "image/heic");

    const files: Record<string, Buffer> = {
      // Un vrai JPEG, et le HEIC tel que le stockage le servait : sous une
      // extension `.jpg` et un `content-type: image/jpeg`, parce que c'est ce
      // que l'app déclarait.
      "/vrai.jpg": jpeg,
      "/heic-deguise.jpg": HEIC,
      "/heic-converti.jpg": converted.buffer,
    };

    server = createServer((request, response) => {
      const body = files[(request.url ?? "/").split("?")[0] ?? "/"];
      if (!body) {
        response.writeHead(404).end();
        return;
      }
      response.writeHead(200, { "content-type": "image/jpeg", "cache-control": "no-store" }).end(body);
    });

    await new Promise<void>((ready) => server.listen(0, "127.0.0.1", ready));
    base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  });

  afterAll(async () => {
    await new Promise<void>((closed) => server.close(() => closed()));
  });

  it("peint un JPEG, et ne peint pas un HEIC déguisé en JPEG", async () => {
    const { unpaintedImages } = await renderBookPdf({
      payload: payloadWith([`${base}/vrai.jpg`, `${base}/heic-deguise.jpg`]),
      profile: "print",
    });

    expect(unpaintedImages).toContain(`${base}/heic-deguise.jpg`);
    expect(unpaintedImages).not.toContain(`${base}/vrai.jpg`);
  });

  it("peint la même photo HEIC une fois convertie", async () => {
    const { unpaintedImages } = await renderBookPdf({
      payload: payloadWith([`${base}/heic-converti.jpg`]),
      profile: "print",
    });

    expect(unpaintedImages).toEqual([]);
  });
}, 120_000);
