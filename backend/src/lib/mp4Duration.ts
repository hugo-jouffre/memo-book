/**
 * **La durée d'un vocal, lue dans le fichier** (Hugo, 03/10/2026).
 *
 * Le crédit du jour décompte la durée de chaque vocal (`services/dailyCredit.ts`).
 * Jusqu'ici, elle était **déclarée par l'app** (`durationSeconds` du multipart) :
 * un client modifié pouvait annoncer une seconde pour vingt minutes d'AAC, et
 * un client ancien n'annonçait rien du tout. On ne la croit plus : on la lit.
 *
 * L'app enregistre de l'AAC-LC mono à 44,1 kHz dans un conteneur MPEG-4
 * (`AudioRecorder.swift`) — un `.m4a`, c'est-à-dire des **boîtes**
 * (ISO/IEC 14496-12) emboîtées. Le chemin qui donne la durée de la piste audio :
 *
 *     moov ▸ trak ▸ mdia ▸ hdlr   (« soun » : c'est la piste audio)
 *                        ▸ mdhd   (l'échelle de temps)
 *                        ▸ minf ▸ stbl ▸ stsd   (le codec et sa fréquence)
 *                                      ▸ stts   (la durée de chaque paquet)
 *                                      ▸ stsz   (le nombre de paquets, leur taille)
 *
 * **Les en-têtes se recoupent, ou le fichier est refusé** (03/10/2026). Les
 * horodatages sont écrits par le client ; le transcripteur, lui, décode
 * **tous les paquets** que `stsz` liste, quels que soient les horodatages.
 * Mesurer `stts` seul laissait facturer 7 ms un vocal de 7 s en multipliant
 * l'échelle de `mdhd` par mille, ou en mettant les durées de `stts` à 1 — et
 * un MP4 fragmenté (l'audio dans des `moof`, `stts` vide) passait pour la
 * seconde que `mdhd.duration` voulait bien annoncer. D'où, dans l'ordre :
 *
 * 1. **Pas de MP4 fragmenté** (`moof` au premier niveau, `mvex` dans `moov`),
 *    **une seule piste, et audio** : l'enregistreur n'écrit rien d'autre.
 * 2. **`stts` non vide**, et plus de repli sur `mdhd.duration` — un en-tête
 *    recopié, que rien ne relie aux paquets.
 * 3. **Autant de paquets dans `stts` que dans `stsz`** : la liste des
 *    horodatages et celle des paquets décrivent le même fichier.
 * 4. **La fréquence est celle du décodeur** : l'`AudioSpecificConfig` de
 *    `esds` (ce que lit le décodeur, et non le champ indicatif de `mp4a`),
 *    en AAC-LC seulement, et l'échelle de `mdhd` doit lui être égale. La durée
 *    retenue est alors la plus longue de Σ`stts` et de `paquets × trames par
 *    paquet` (1 024 en AAC-LC) : des horodatages raccourcis ne raccourcissent
 *    plus rien.
 * 5. **Un débit vraisemblable** : au-delà de 40 Ko/s rapportés à la durée
 *    retenue (Σ`stsz`, ce que le décodeur lira), ce n'est pas de l'AAC de
 *    cette durée — des paquets bourrés de plusieurs trames, sans doute. L'AAC-LC
 *    mono plafonne à ~33 Ko/s ; l'app enregistre autour de 8.
 *
 * Ce qui échappe encore — quelques trames tassées par paquet à très bas
 * débit —, le filet du job de transcription le rattrape : un texte bien plus
 * long que la durée mesurée se décompte quand même (`jobs/transcribe.ts`).
 *
 * La somme compte aussi l'amorce de l'encodeur AAC, une quarantaine de
 * millisecondes : c'est le fichier qu'on mesure, pas la voix.
 *
 * **Pur TypeScript, sans dépendance** : l'image Docker n'a ni ffmpeg ni ffprobe,
 * et lire quelques en-têtes ne justifie ni l'un ni l'autre. Gère les tailles de
 * boîte sur 64 bits (`size == 1`), la boîte qui court jusqu'à la fin
 * (`size == 0`) et `mdhd` en version 1 (dates et durée sur 64 bits).
 *
 * Tout ce qui ne se lit pas, ou ne concorde pas, rend `null` — jamais une
 * exception, jamais une durée inventée : c'est à l'appelant de refuser le vocal
 * (`400 unreadable_audio`).
 */

/** Une boîte : son type, et où son contenu commence et finit dans le fichier. */
interface Box {
  type: string;
  start: number;
  end: number;
}

/** Au-delà, ce n'est pas un vocal mais un fichier abîmé (ou forgé). */
const MAX_DURATION_MS = 24 * 60 * 60 * 1000;

/**
 * Le débit au-delà duquel un fichier ne peut pas être de l'AAC de la durée
 * qu'il annonce : 40 Ko/s. L'AAC-LC plafonne à 6 144 bits par trame et par
 * canal, soit ~33 Ko/s en mono à 44,1 kHz ; l'app enregistre autour de 8 Ko/s.
 */
export const MAX_BYTES_PER_SECOND = 40_000;

/** L'AAC-LC, le seul codec que l'enregistreur de l'app écrit (`AudioSpecificConfig`). */
const AAC_LC = 2;

/** Les fréquences de l'`AudioSpecificConfig`, par index (ISO/IEC 14496-3, 1.6.3.4). */
const SAMPLING_FREQUENCIES = [
  96_000, 88_200, 64_000, 48_000, 44_100, 32_000, 24_000, 22_050, 16_000, 12_000, 11_025, 8_000, 7_350,
];

/** Les boîtes filles d'un intervalle, dans l'ordre. S'arrête à la première qui ne tient pas. */
function childrenOf(buffer: Buffer, start: number, end: number): Box[] {
  const boxes: Box[] = [];
  let offset = start;

  while (offset + 8 <= end) {
    let size = buffer.readUInt32BE(offset);
    const type = buffer.toString("latin1", offset + 4, offset + 8);
    let header = 8;

    if (size === 1) {
      // La taille réelle suit, sur 64 bits — une boîte de plus de 4 Go en
      // théorie, un `mdat` d'enregistreur prudent en pratique.
      if (offset + 16 > end) break;
      const large = buffer.readBigUInt64BE(offset + 8);
      if (large > BigInt(end - offset)) break;
      size = Number(large);
      header = 16;
    } else if (size === 0) {
      // « Jusqu'à la fin de ce qui la contient. »
      size = end - offset;
    }

    if (size < header || offset + size > end) break;
    boxes.push({ type, start: offset + header, end: offset + size });
    offset += size;
  }

  return boxes;
}

function child(buffer: Buffer, parent: Box, type: string): Box | undefined {
  return childrenOf(buffer, parent.start, parent.end).find((box) => box.type === type);
}

/** Le type de piste que `hdlr` déclare (`soun`, `vide`…), ou `null`. */
function handlerOf(buffer: Buffer, hdlr: Box): string | null {
  // version + drapeaux (4), pre_defined (4), puis le type (4).
  if (hdlr.end - hdlr.start < 12) return null;
  return buffer.toString("latin1", hdlr.start + 8, hdlr.start + 12);
}

/** L'échelle de temps de `mdhd`, versions 0 et 1, ou `null`. */
function timescaleOf(buffer: Buffer, mdhd: Box): number | null {
  const length = mdhd.end - mdhd.start;
  if (length < 1) return null;
  const version = buffer.readUInt8(mdhd.start);

  // version + drapeaux (4), création et modification (4 + 4, ou 8 + 8 en
  // version 1), puis l'échelle (4). La durée qui suit n'est plus lue : c'est
  // un en-tête recopié, que rien ne relie aux paquets.
  const offset = version === 1 ? 20 : 12;
  if (length < offset + 4) return null;
  return buffer.readUInt32BE(mdhd.start + offset);
}

// ---------------------------------------------------------------------------
// Le codec : `stsd ▸ mp4a ▸ esds ▸ AudioSpecificConfig`
// ---------------------------------------------------------------------------

/** Un descripteur MPEG-4 (`esds`) : son étiquette, et où son contenu tient. */
function descriptorAt(buffer: Buffer, offset: number, end: number): { tag: number; start: number; end: number } | null {
  if (offset + 2 > end) return null;
  const tag = buffer.readUInt8(offset);
  let length = 0;
  let cursor = offset + 1;
  // La longueur s'écrit sur 1 à 4 octets, sept bits chacun ; le huitième dit
  // qu'un octet suit.
  for (let index = 0; index < 4; index += 1) {
    if (cursor >= end) return null;
    const byte = buffer.readUInt8(cursor);
    cursor += 1;
    length = length * 128 + (byte & 0x7f);
    if ((byte & 0x80) === 0) break;
  }
  if (cursor + length > end) return null;
  return { tag, start: cursor, end: cursor + length };
}

/** Les octets de l'`AudioSpecificConfig` que porte `esds`, ou `null`. */
function audioSpecificConfigOf(buffer: Buffer, esds: Box): Buffer | null {
  // version + drapeaux (4), puis l'ES_Descriptor (étiquette 3).
  const es = descriptorAt(buffer, esds.start + 4, esds.end);
  if (!es || es.tag !== 0x03 || es.end - es.start < 3) return null;

  // ES_ID (2), puis un octet de drapeaux qui annonce des champs facultatifs.
  const flags = buffer.readUInt8(es.start + 2);
  let offset = es.start + 3;
  if (flags & 0x80) offset += 2; // streamDependenceFlag : dependsOn_ES_ID
  if (flags & 0x40) {
    // URL_Flag : une longueur, puis l'adresse.
    if (offset >= es.end) return null;
    offset += 1 + buffer.readUInt8(offset);
  }
  if (flags & 0x20) offset += 2; // OCRstreamFlag : OCR_ES_Id

  // Le DecoderConfigDescriptor (étiquette 4) : type d'objet 0x40 = audio
  // MPEG-4, puis 12 octets de flux et de débits, puis l'information propre au
  // décodeur (étiquette 5) — l'`AudioSpecificConfig`.
  const config = descriptorAt(buffer, offset, es.end);
  if (!config || config.tag !== 0x04 || config.end - config.start < 13) return null;
  if (buffer.readUInt8(config.start) !== 0x40) return null;
  const specific = descriptorAt(buffer, config.start + 13, config.end);
  if (!specific || specific.tag !== 0x05) return null;
  return buffer.subarray(specific.start, specific.end);
}

/**
 * La fréquence et les trames par paquet d'un AAC-LC, lues bit à bit dans son
 * `AudioSpecificConfig` — ou `null` pour tout autre codec. C'est ce que le
 * décodeur lit : une fréquence réécrite ici change ce qu'on entend, pas
 * seulement ce qu'on annonce.
 */
function aacFormatOf(config: Buffer): { frequency: number; framesPerPacket: number } | null {
  let position = 0;
  const read = (bits: number): number | null => {
    if (position + bits > config.length * 8) return null;
    let value = 0;
    for (let index = 0; index < bits; index += 1) {
      const byte = config[(position + index) >> 3]!;
      value = value * 2 + ((byte >> (7 - ((position + index) & 7))) & 1);
    }
    position += bits;
    return value;
  };

  let objectType = read(5);
  if (objectType === 31) {
    const extended = read(6);
    objectType = extended === null ? null : 32 + extended;
  }
  if (objectType !== AAC_LC) return null;

  const index = read(4);
  if (index === null) return null;
  const frequency = index === 0x0f ? read(24) : SAMPLING_FREQUENCIES[index];
  if (!frequency) return null;

  // channelConfiguration (4), puis GASpecificConfig : frameLengthFlag.
  if (read(4) === null) return null;
  const shortFrames = read(1);
  if (shortFrames === null) return null;
  return { frequency, framesPerPacket: shortFrames === 1 ? 960 : 1_024 };
}

/** Le format de l'unique entrée de `stsd`, si c'est de l'AAC-LC dans `mp4a`. */
function sampleFormatOf(buffer: Buffer, stsd: Box): { frequency: number; framesPerPacket: number } | null {
  // version + drapeaux (4), nombre d'entrées (4), puis les entrées — des boîtes.
  if (stsd.end - stsd.start < 8) return null;
  if (buffer.readUInt32BE(stsd.start + 4) !== 1) return null;
  const entries = childrenOf(buffer, stsd.start + 8, stsd.end);
  const entry = entries[0];
  if (entries.length !== 1 || entry?.type !== "mp4a") return null;

  // SampleEntry (8), puis AudioSampleEntry (20) ; les versions QuickTime 1 et
  // 2 y ajoutent 16 et 36 octets avant les boîtes filles, dont `esds`.
  if (entry.end - entry.start < 28) return null;
  const version = buffer.readUInt16BE(entry.start + 8);
  const extra = version === 1 ? 16 : version === 2 ? 36 : 0;
  if (entry.end - entry.start < 28 + extra) return null;
  const esds = childrenOf(buffer, entry.start + 28 + extra, entry.end).find((box) => box.type === "esds");
  const config = esds ? audioSpecificConfigOf(buffer, esds) : null;
  return config ? aacFormatOf(config) : null;
}

// ---------------------------------------------------------------------------
// Les paquets : `stts` et `stsz`
// ---------------------------------------------------------------------------

/** `stts` : le nombre de paquets, et Σ(nombre × durée) sur l'échelle de la piste. */
function timeToSampleOf(buffer: Buffer, stts: Box): { samples: bigint; units: bigint } | null {
  const length = stts.end - stts.start;
  if (length < 8) return null;
  const count = buffer.readUInt32BE(stts.start + 4);
  if (8 + count * 8 > length) return null;

  let samples = 0n;
  let units = 0n;
  for (let index = 0; index < count; index += 1) {
    const entry = stts.start + 8 + index * 8;
    const entrySamples = BigInt(buffer.readUInt32BE(entry));
    samples += entrySamples;
    units += entrySamples * BigInt(buffer.readUInt32BE(entry + 4));
  }
  return { samples, units };
}

/** `stsz` : le nombre de paquets, et ce qu'ils pèsent ensemble — ce que le décodeur lira. */
function sampleSizesOf(buffer: Buffer, stsz: Box): { samples: bigint; bytes: bigint } | null {
  // version + drapeaux (4), taille commune (4), nombre de paquets (4), puis
  // une taille par paquet quand la taille commune vaut zéro.
  const length = stsz.end - stsz.start;
  if (length < 12) return null;
  const common = buffer.readUInt32BE(stsz.start + 4);
  const count = buffer.readUInt32BE(stsz.start + 8);
  if (common !== 0) return { samples: BigInt(count), bytes: BigInt(common) * BigInt(count) };
  if (12 + count * 4 > length) return null;

  let bytes = 0n;
  for (let index = 0; index < count; index += 1) {
    bytes += BigInt(buffer.readUInt32BE(stsz.start + 12 + index * 4));
  }
  return { samples: BigInt(count), bytes };
}

/** La durée de la piste audio d'une `trak`, en millisecondes, ou `null`. */
function audioTrackDurationMs(buffer: Buffer, trak: Box): number | null {
  const mdia = child(buffer, trak, "mdia");
  if (!mdia) return null;

  const boxes = childrenOf(buffer, mdia.start, mdia.end);
  const hdlr = boxes.find((box) => box.type === "hdlr");
  if (!hdlr || handlerOf(buffer, hdlr) !== "soun") return null;

  const mdhd = boxes.find((box) => box.type === "mdhd");
  const timescale = mdhd ? timescaleOf(buffer, mdhd) : null;
  if (!timescale) return null;

  const minf = boxes.find((box) => box.type === "minf");
  const stbl = minf ? child(buffer, minf, "stbl") : undefined;
  if (!stbl) return null;
  const tables = childrenOf(buffer, stbl.start, stbl.end);
  const stsd = tables.find((box) => box.type === "stsd");
  const stts = tables.find((box) => box.type === "stts");
  const stsz = tables.find((box) => box.type === "stsz");
  if (!stsd || !stts || !stsz) return null;

  // 4. La fréquence du décodeur, et une échelle qui lui est égale.
  const format = sampleFormatOf(buffer, stsd);
  if (!format || format.frequency !== timescale) return null;

  // 2. et 3. Des horodatages, autant que de paquets.
  const times = timeToSampleOf(buffer, stts);
  const sizes = sampleSizesOf(buffer, stsz);
  if (!times || !sizes || times.samples === 0n || times.samples !== sizes.samples) return null;

  // La plus longue des deux lectures : des horodatages raccourcis ne
  // raccourcissent pas ce que le décodeur rendra, paquet par paquet.
  const decoded = sizes.samples * BigInt(format.framesPerPacket);
  const units = times.units > decoded ? times.units : decoded;

  // Arrondi au plus proche, en entiers : pas de flottant sur 64 bits.
  const scale = BigInt(timescale);
  const milliseconds = (units * 1000n + scale / 2n) / scale;
  if (milliseconds <= 0n || milliseconds > BigInt(MAX_DURATION_MS)) return null;

  // 5. Un débit vraisemblable pour cette durée.
  if (sizes.bytes * 1000n > BigInt(MAX_BYTES_PER_SECOND) * milliseconds) return null;

  return Number(milliseconds);
}

/**
 * La durée de la piste audio d'un fichier MPEG-4 (`.m4a`, `.mp4`), en
 * millisecondes — ou `null` si le fichier ne se lit pas ou que ses en-têtes ne
 * concordent pas : pas de `moov`, MP4 fragmenté, plus d'une piste, piste non
 * audio, codec autre que l'AAC-LC, en-têtes tronqués ou contradictoires,
 * débit impossible.
 */
export function mp4AudioDurationMs(buffer: Buffer): number | null {
  const top = childrenOf(buffer, 0, buffer.byteLength);
  // 1. Des fragments (`moof`) : l'audio est ailleurs que dans les tables de
  // `moov`, et les tables ne disent plus rien de sa durée.
  if (top.some((box) => box.type === "moof")) return null;
  const moovs = top.filter((box) => box.type === "moov");
  const moov = moovs[0];
  if (moovs.length !== 1 || !moov) return null;

  const inMoov = childrenOf(buffer, moov.start, moov.end);
  if (inMoov.some((box) => box.type === "mvex")) return null;
  const traks = inMoov.filter((box) => box.type === "trak");
  const trak = traks[0];
  if (traks.length !== 1 || !trak) return null;

  return audioTrackDurationMs(buffer, trak);
}
