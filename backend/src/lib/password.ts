import {
  randomBytes,
  scrypt,
  timingSafeEqual,
  type ScryptOptions,
} from "node:crypto";
import { promisify } from "node:util";

// `promisify` ne retient que la première surcharge de `scrypt`, celle sans
// options — d'où le typage explicite, sans lequel `maxmem` serait rejeté.
const scryptAsync = promisify(scrypt) as (
  password: string,
  salt: Buffer,
  keylen: number,
  options: ScryptOptions,
) => Promise<Buffer>;

/**
 * Hachage des mots de passe par `scrypt`, celui de Node.
 *
 * Pas de dépendance : `bcrypt` et `argon2` demandent une compilation native,
 * qui casse au premier changement de version de Node ou d'image Docker. `scrypt`
 * est dans la bibliothèque standard, et fait partie des trois fonctions
 * recommandées par l'OWASP pour cet usage.
 *
 * Format stocké : `scrypt$N$r$p$sel$empreinte`, tout en base64url. Les
 * paramètres voyagent avec l'empreinte — c'est ce qui permettra de les durcir
 * plus tard sans invalider les mots de passe déjà enregistrés.
 */

/** Paramètres de coût. `N` est le seul qu'on augmentera avec le temps. */
const PARAMS = { N: 2 ** 15, r: 8, p: 1 } as const;
const KEY_LENGTH = 32;
const SALT_LENGTH = 16;

/**
 * `scrypt` a besoin d'environ `128 × N × r` octets. À N = 32768 et r = 8, cela
 * fait 32 Mio, au-dessus de la limite par défaut de Node — qui refuserait
 * autrement avec une erreur peu parlante.
 */
const MAX_MEMORY = 64 * 1024 * 1024;

export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(SALT_LENGTH);
  const derived = await scryptAsync(password.normalize("NFKC"), salt, KEY_LENGTH, {
    ...PARAMS,
    maxmem: MAX_MEMORY,
  });

  return [
    "scrypt",
    PARAMS.N,
    PARAMS.r,
    PARAMS.p,
    salt.toString("base64url"),
    derived.toString("base64url"),
  ].join("$");
}

/**
 * Comparaison à temps constant. Rend `false` plutôt que de lever sur une
 * empreinte illisible : une ligne corrompue en base ne doit pas se transformer
 * en 500 sur la route de connexion.
 */
export async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const parts = stored.split("$");
  if (parts.length !== 6 || parts[0] !== "scrypt") return false;

  const N = Number(parts[1]);
  const r = Number(parts[2]);
  const p = Number(parts[3]);
  if (!Number.isInteger(N) || !Number.isInteger(r) || !Number.isInteger(p)) return false;

  const salt = Buffer.from(parts[4] ?? "", "base64url");
  const expected = Buffer.from(parts[5] ?? "", "base64url");
  if (salt.length === 0 || expected.length === 0) return false;

  const derived = await scryptAsync(password.normalize("NFKC"), salt, expected.length, {
    N,
    r,
    p,
    maxmem: MAX_MEMORY,
  });

  return timingSafeEqual(derived, expected);
}
