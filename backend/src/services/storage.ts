import { randomUUID } from "node:crypto";
import {
  GetObjectCommand,
  PutObjectCommand,
  S3Client,
} from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import type { Env } from "../env.js";

export interface StoredObject {
  storageKey: string;
  bytes: number;
  mimeType: string;
}

/**
 * Stockage des médias bruts : les audios que l'app envoie et les photos avant
 * publication sur le CDN. S3-compatible — MinIO en local, n'importe quel
 * fournisseur en production.
 */
export class MediaStorage {
  constructor(
    private readonly client: S3Client,
    private readonly bucket: string,
  ) {}

  private static keyFor(prefix: string, filename: string): string {
    const extension = filename.includes(".") ? filename.split(".").pop() : "bin";
    return `${prefix}/${randomUUID()}.${extension}`;
  }

  async put(
    prefix: string,
    filename: string,
    body: Buffer,
    mimeType: string,
  ): Promise<StoredObject> {
    const storageKey = MediaStorage.keyFor(prefix, filename);

    await this.client.send(
      new PutObjectCommand({
        Bucket: this.bucket,
        Key: storageKey,
        Body: body,
        ContentType: mimeType,
      }),
    );

    return { storageKey, bytes: body.byteLength, mimeType };
  }

  async get(storageKey: string): Promise<Buffer> {
    const response = await this.client.send(
      new GetObjectCommand({ Bucket: this.bucket, Key: storageKey }),
    );

    if (!response.Body) {
      throw new Error(`Objet introuvable dans le stockage : ${storageKey}`);
    }

    return Buffer.from(await response.Body.transformToByteArray());
  }

  /** URL temporaire de lecture, pour l'app (relecture d'un vocal). */
  async signedReadUrl(storageKey: string, expiresInSeconds = 3600): Promise<string> {
    return getSignedUrl(
      this.client,
      new GetObjectCommand({ Bucket: this.bucket, Key: storageKey }),
      { expiresIn: expiresInSeconds },
    );
  }
}

/**
 * Stockage en mémoire pour les tests et le smoke : mêmes garanties d'interface,
 * aucun conteneur à lancer.
 */
export class InMemoryMediaStorage extends MediaStorage {
  private readonly objects = new Map<string, Buffer>();

  constructor() {
    super(null as unknown as S3Client, "in-memory");
  }

  override async put(
    prefix: string,
    filename: string,
    body: Buffer,
    mimeType: string,
  ): Promise<StoredObject> {
    const extension = filename.includes(".") ? filename.split(".").pop() : "bin";
    const storageKey = `${prefix}/${randomUUID()}.${extension}`;
    this.objects.set(storageKey, body);
    return { storageKey, bytes: body.byteLength, mimeType };
  }

  override async get(storageKey: string): Promise<Buffer> {
    const object = this.objects.get(storageKey);
    if (!object) throw new Error(`Objet introuvable dans le stockage : ${storageKey}`);
    return object;
  }

  override async signedReadUrl(storageKey: string): Promise<string> {
    return `memory://${storageKey}`;
  }
}

export function createMediaStorage(env: Env): MediaStorage {
  if (env.NODE_ENV === "test") return new InMemoryMediaStorage();

  const { S3_ENDPOINT, S3_BUCKET, S3_ACCESS_KEY_ID, S3_SECRET_ACCESS_KEY } = env;

  // La configuration S3 n'est exigée qu'ici, là où elle sert réellement.
  const missing = Object.entries({
    S3_ENDPOINT,
    S3_BUCKET,
    S3_ACCESS_KEY_ID,
    S3_SECRET_ACCESS_KEY,
  })
    .filter(([, value]) => !value)
    .map(([name]) => name);

  if (
    missing.length > 0 ||
    !S3_ENDPOINT ||
    !S3_BUCKET ||
    !S3_ACCESS_KEY_ID ||
    !S3_SECRET_ACCESS_KEY
  ) {
    // En production, un stockage manquant est une panne : les vocaux des
    // utilisateurs disparaîtraient au premier redémarrage. On refuse de démarrer.
    if (env.NODE_ENV === "production") {
      throw new Error(
        `Stockage des médias non configuré : ${missing.join(", ")} manquant(s).`,
      );
    }

    // Ailleurs, on retombe sur la mémoire pour que `npm run dev` et
    // `npm run smoke` fonctionnent sans rien installer. Les médias ne survivent
    // pas au redémarrage — d'où l'avertissement.
    console.warn(
      `[storage] ${missing.join(", ")} absent(s) : stockage EN MÉMOIRE, ` +
        "les médias seront perdus au redémarrage. Voir .env.example.",
    );
    return new InMemoryMediaStorage();
  }

  const client = new S3Client({
    endpoint: S3_ENDPOINT,
    region: env.S3_REGION,
    forcePathStyle: env.S3_FORCE_PATH_STYLE,
    credentials: {
      accessKeyId: S3_ACCESS_KEY_ID,
      secretAccessKey: S3_SECRET_ACCESS_KEY,
    },
  });

  return new MediaStorage(client, S3_BUCKET);
}
