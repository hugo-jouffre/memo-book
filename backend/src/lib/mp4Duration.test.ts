import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { MAX_BYTES_PER_SECOND, mp4AudioDurationMs } from "./mp4Duration.js";

const fixtures = resolve(dirname(fileURLToPath(import.meta.url)), "../../test/fixtures/audio");

/**
 * Trois vrais `.m4a`, encodés en AAC-LC par `afconvert` (macOS) à partir d'un
 * WAV de synthèse — le même encodeur et le même conteneur que ceux
 * d'`AVAudioRecorder`. Les deux premiers à 22 050 Hz ; le troisième au format
 * exact de l'app, mono à 44,1 kHz (`AudioRecorder.swift`). La mesure compte
 * l'amorce de l'encodeur (2 112 échantillons) et le dernier paquet entamé :
 * d'où la fourchette.
 */
const twoSeconds = readFileSync(resolve(fixtures, "vocal-2s.m4a"));
const sevenSeconds = readFileSync(resolve(fixtures, "vocal-7s.m4a"));
const threeSecondsAt44k = readFileSync(resolve(fixtures, "vocal-3s-44khz.m4a"));

// ---------------------------------------------------------------------------
// Falsifier un vrai fichier
// ---------------------------------------------------------------------------

/** Où commence une boîte du vrai fichier (son en-tête), et où son contenu tient. */
function locate(buffer: Buffer, path: string[]): { offset: number; start: number; end: number } {
  let start = 0;
  let end = buffer.byteLength;
  let found: { offset: number; start: number; end: number } | undefined;
  for (const type of path) {
    found = undefined;
    for (let offset = start; offset + 8 <= end; offset += buffer.readUInt32BE(offset)) {
      if (buffer.toString("latin1", offset + 4, offset + 8) === type) {
        found = { offset, start: offset + 8, end: offset + buffer.readUInt32BE(offset) };
        break;
      }
    }
    if (!found) throw new Error(`Boîte ${path.join("/")} introuvable dans la fixture.`);
    ({ start, end } = found);
  }
  return found!;
}

const STBL = ["moov", "trak", "mdia", "minf", "stbl"];

/** Une copie du vocal de 7 s, retouchée comme un client modifié le ferait. */
function forged(edit: (copy: Buffer) => Buffer | void): Buffer {
  const copy = Buffer.from(sevenSeconds);
  return edit(copy) ?? copy;
}

// ---------------------------------------------------------------------------
// Fabriquer un fichier de toutes pièces
// ---------------------------------------------------------------------------

/** Une boîte : taille sur 32 bits, ou sur 64 (`size == 1`) quand on le demande. */
function box(type: string, payload: Buffer, options: { large?: boolean } = {}): Buffer {
  if (options.large) {
    const header = Buffer.alloc(16);
    header.writeUInt32BE(1, 0);
    header.write(type, 4, "latin1");
    header.writeBigUInt64BE(BigInt(16 + payload.byteLength), 8);
    return Buffer.concat([header, payload]);
  }
  const header = Buffer.alloc(8);
  header.writeUInt32BE(8 + payload.byteLength, 0);
  header.write(type, 4, "latin1");
  return Buffer.concat([header, payload]);
}

const FREQUENCY_INDEX: Record<number, number> = { 44_100: 4, 22_050: 7, 8_000: 11 };

/** L'`AudioSpecificConfig` d'un AAC mono : type d'objet, fréquence, trames de 1 024. */
function audioSpecificConfig(frequency: number, objectType = 2): Buffer {
  const bits = (objectType << 11) | (FREQUENCY_INDEX[frequency]! << 7) | (1 << 3);
  return Buffer.from([bits >> 8, bits & 0xff]);
}

/** `stsd ▸ mp4a ▸ esds`, comme l'écrit l'encodeur d'Apple. */
function stsd(frequency: number, objectType = 2): Buffer {
  const asc = audioSpecificConfig(frequency, objectType);
  const specific = Buffer.concat([Buffer.from([0x05, asc.length]), asc]);
  const config = Buffer.concat([Buffer.from([0x04, 13 + specific.length, 0x40, 0x15]), Buffer.alloc(11), specific]);
  const es = Buffer.concat([Buffer.from([0x03, 3 + config.length, 0, 0, 0]), config]);
  const esds = box("esds", Buffer.concat([Buffer.alloc(4), es]));

  const entry = Buffer.alloc(28);
  entry.writeUInt16BE(1, 6); // data_reference_index
  entry.writeUInt16BE(1, 16); // channelcount
  entry.writeUInt16BE(16, 18); // samplesize
  entry.writeUInt32BE(frequency * 65_536, 24); // samplerate, 16.16
  const mp4a = box("mp4a", Buffer.concat([entry, esds]));

  const header = Buffer.alloc(8);
  header.writeUInt32BE(1, 4);
  return box("stsd", Buffer.concat([header, mp4a]));
}

function mdhdV0(timescale: number, duration: number): Buffer {
  const payload = Buffer.alloc(24);
  payload.writeUInt32BE(timescale, 12);
  payload.writeUInt32BE(duration, 16);
  return box("mdhd", payload);
}

function mdhdV1(timescale: number, duration: bigint): Buffer {
  const payload = Buffer.alloc(36);
  payload.writeUInt8(1, 0);
  payload.writeUInt32BE(timescale, 20);
  payload.writeBigUInt64BE(duration, 24);
  return box("mdhd", payload);
}

function hdlr(handler: string): Buffer {
  const payload = Buffer.alloc(24);
  payload.write(handler, 8, "latin1");
  return box("hdlr", payload);
}

function stts(entries: [count: number, delta: number][]): Buffer {
  const payload = Buffer.alloc(8 + entries.length * 8);
  payload.writeUInt32BE(entries.length, 4);
  entries.forEach(([count, delta], index) => {
    payload.writeUInt32BE(count, 8 + index * 8);
    payload.writeUInt32BE(delta, 12 + index * 8);
  });
  return box("stts", payload);
}

/** `stsz` à taille commune : `count` paquets de `size` octets. */
function stsz(count: number, size: number): Buffer {
  const payload = Buffer.alloc(12);
  payload.writeUInt32BE(size, 4);
  payload.writeUInt32BE(count, 8);
  return box("stsz", payload);
}

function track(parts: {
  timescale?: number;
  mdhd?: Buffer;
  frequency?: number;
  objectType?: number;
  handler?: string;
  stts: Buffer;
  packets: number;
  packetBytes?: number;
  large?: boolean;
}): Buffer {
  const frequency = parts.frequency ?? 44_100;
  const stbl = box(
    "stbl",
    Buffer.concat([stsd(frequency, parts.objectType), parts.stts, stsz(parts.packets, parts.packetBytes ?? 200)]),
  );
  const mdhd = parts.mdhd ?? mdhdV0(parts.timescale ?? frequency, 0);
  const mdia = box("mdia", Buffer.concat([mdhd, hdlr(parts.handler ?? "soun"), box("minf", stbl)]), {
    large: parts.large ?? false,
  });
  return box("trak", mdia);
}

function file(...tracks: Buffer[]): Buffer {
  const ftyp = box("ftyp", Buffer.from("M4A \0\0\0\0", "latin1"));
  return Buffer.concat([ftyp, box("moov", Buffer.concat(tracks)), box("mdat", Buffer.alloc(32))]);
}

// ---------------------------------------------------------------------------

describe("mp4AudioDurationMs", () => {
  it("mesure un vrai vocal AAC de 2 s", () => {
    const duration = mp4AudioDurationMs(twoSeconds);
    expect(duration).toBeGreaterThanOrEqual(2_000);
    expect(duration).toBeLessThan(2_200);
  });

  it("mesure un vrai vocal AAC de 7 s", () => {
    const duration = mp4AudioDurationMs(sevenSeconds);
    expect(duration).toBeGreaterThanOrEqual(7_000);
    expect(duration).toBeLessThan(7_200);
  });

  it("mesure un vrai vocal au format de l'app : AAC-LC mono à 44,1 kHz", () => {
    const duration = mp4AudioDurationMs(threeSecondsAt44k);
    expect(duration).toBeGreaterThanOrEqual(3_000);
    expect(duration).toBeLessThan(3_200);
  });

  it("somme les paquets de `stts`, sur l'échelle de `mdhd`, quand ils durent plus que les trames", () => {
    // 100 paquets de 2 048 à 44 100 Hz : 204 800 / 44 100 = 4 643,9 ms. Les
    // horodatages disent plus long que les trames : c'est eux qu'on retient.
    const audio = file(track({ stts: stts([[100, 2_048]]), packets: 100 }));
    expect(mp4AudioDurationMs(audio)).toBe(4_644);
  });

  it("compte au moins une trame de 1 024 par paquet, quoi que disent les horodatages", () => {
    // 100 paquets de 1 024 + 1 de 512 : Σ`stts` = 2 333,6 ms, mais le décodeur
    // rend 101 trames entières — 103 424 / 44 100 = 2 345,2 ms.
    const audio = file(track({ stts: stts([[100, 1_024], [1, 512]]), packets: 101 }));
    expect(mp4AudioDurationMs(audio)).toBe(2_345);
  });

  it("lit `mdhd` en version 1, et une boîte dont la taille est sur 64 bits", () => {
    const audio = file(
      track({ mdhd: mdhdV1(48_000, 480_000n), frequency: 44_100, stts: stts([[10, 1_024]]), packets: 10 }),
    );
    // L'échelle (48 000) ne colle pas à la fréquence (44 100) : refusé…
    expect(mp4AudioDurationMs(audio)).toBeNull();
    // … et lue juste quand elle colle.
    const fine = file(
      track({ mdhd: mdhdV1(44_100, 1n), stts: stts([[441, 1_000]]), packets: 441, large: true }),
    );
    expect(mp4AudioDurationMs(fine)).toBe(10_240);
  });

  it("refuse ce qui ne se lit pas", () => {
    expect(mp4AudioDurationMs(Buffer.from("audio"))).toBeNull();
    expect(mp4AudioDurationMs(Buffer.alloc(0))).toBeNull();
    // Échelle nulle.
    expect(mp4AudioDurationMs(file(track({ timescale: 0, stts: stts([[10, 1_024]]), packets: 10 })))).toBeNull();
    // Un vrai fichier coupé avant la fin de `moov`.
    const moovEnd = sevenSeconds.indexOf("udta", 0, "latin1");
    expect(mp4AudioDurationMs(sevenSeconds.subarray(0, moovEnd - 300))).toBeNull();
  });

  it("ne croit pas un fichier qui annonce plus d'une journée", () => {
    const audio = file(track({ frequency: 8_000, stts: stts([[1, 0xffff_ffff]]), packets: 1 }));
    expect(mp4AudioDurationMs(audio)).toBeNull();
  });

  it("refuse un autre codec que l'AAC-LC", () => {
    // Type d'objet 5 : du HE-AAC signalé explicitement — trames de 2 048.
    expect(mp4AudioDurationMs(file(track({ objectType: 5, stts: stts([[10, 1_024]]), packets: 10 })))).toBeNull();
  });
});

/**
 * **Les fichiers falsifiés** (03/10/2026) : le vocal de 7 s du dépôt, retouché
 * octet par octet comme un client modifié le ferait pour payer une poignée de
 * millisecondes. Chacun est refusé, ou mesuré à ses vraies 7 s.
 */
describe("mp4AudioDurationMs, face à un fichier falsifié", () => {
  const sevenSecondsMs = mp4AudioDurationMs(sevenSeconds)!;

  it("refuse une échelle de `mdhd` multipliée par mille", () => {
    const audio = forged((copy) => {
      const mdhd = locate(copy, ["moov", "trak", "mdia", "mdhd"]);
      copy.writeUInt32BE(copy.readUInt32BE(mdhd.start + 12) * 1_000, mdhd.start + 12);
    });
    expect(mp4AudioDurationMs(audio)).toBeNull();
  });

  it("mesure 7 s quand les durées de `stts` tombent à 1", () => {
    const audio = forged((copy) => {
      const table = locate(copy, [...STBL, "stts"]);
      const entries = copy.readUInt32BE(table.start + 4);
      for (let index = 0; index < entries; index += 1) copy.writeUInt32BE(1, table.start + 12 + index * 8);
    });
    expect(mp4AudioDurationMs(audio)).toBe(sevenSecondsMs);
  });

  it("refuse un `stsz` qui annonce moins de paquets que `stts`", () => {
    const audio = forged((copy) => {
      const table = locate(copy, [...STBL, "stsz"]);
      copy.writeUInt32BE(10, table.start + 8);
    });
    expect(mp4AudioDurationMs(audio)).toBeNull();
  });

  it("refuse un MP4 fragmenté : `stts` vide et l'audio dans des `moof`", () => {
    const emptied = forged((copy) => {
      const table = locate(copy, [...STBL, "stts"]);
      copy.writeUInt32BE(0, table.start + 4);
    });
    // `stts` vide suffit à refuser : plus de repli sur `mdhd.duration`.
    expect(mp4AudioDurationMs(emptied)).toBeNull();

    const mfhd = box("mfhd", Buffer.alloc(8));
    const fragmented = Buffer.concat([sevenSeconds, box("moof", mfhd), box("mdat", Buffer.alloc(64))]);
    expect(mp4AudioDurationMs(fragmented)).toBeNull();

    // `mvex` dans `moov` annonce des fragments, même sans `moof` encore.
    const announced = forged((copy) => {
      const udta = locate(copy, ["moov", "udta"]);
      copy.write("mvex", udta.offset + 4, "latin1");
    });
    expect(mp4AudioDurationMs(announced)).toBeNull();
  });

  it("refuse une seconde piste, ou une piste qui n'est pas audio", () => {
    const twoTracks = forged((copy) => {
      const udta = locate(copy, ["moov", "udta"]);
      copy.write("trak", udta.offset + 4, "latin1");
    });
    expect(mp4AudioDurationMs(twoTracks)).toBeNull();

    const video = forged((copy) => {
      const handler = locate(copy, ["moov", "trak", "mdia", "hdlr"]);
      copy.write("vide", handler.start + 8, "latin1");
    });
    expect(mp4AudioDurationMs(video)).toBeNull();
  });

  it("refuse une fréquence réécrite dans `esds` sans l'échelle de `mdhd`", () => {
    const audio = forged((copy) => {
      // L'`AudioSpecificConfig` du vocal : 0x13 0x88 (AAC-LC, 22 050 Hz, mono).
      const config = copy.indexOf(Buffer.from([0x05, 0x80, 0x80, 0x80, 0x02, 0x13, 0x88]));
      expect(config).toBeGreaterThan(0);
      copy.writeUInt8(0x12, config + 5); // index 4 : 44 100 Hz
      copy.writeUInt8(0x08, config + 6);
    });
    expect(mp4AudioDurationMs(audio)).toBeNull();
  });

  it(`refuse un débit impossible pour la durée retenue (plus de ${MAX_BYTES_PER_SECOND / 1_000} Ko/s)`, () => {
    // 153 paquets de 5 000 octets en 7,1 s : ~108 Ko/s — plusieurs trames
    // tassées par paquet, pas de l'AAC.
    const audio = forged((copy) => {
      const table = locate(copy, [...STBL, "stsz"]);
      copy.writeUInt32BE(5_000, table.start + 4);
    });
    expect(mp4AudioDurationMs(audio)).toBeNull();
  });
});
