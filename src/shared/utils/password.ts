import crypto from "node:crypto";

const SCRYPT_N = 16384; // CPU/memory cost
const SCRYPT_R = 8;
const SCRYPT_P = 1;
const KEYLEN = 64;

function b64(buf: Buffer) {
  return buf.toString("base64");
}
function fromB64(s: string) {
  return Buffer.from(s, "base64");
}

/**
 * Format stored in DB:
 * scrypt$N$r$p$saltB64$hashB64
 */
export async function hashPassword(password: string): Promise<string> {
  const salt = crypto.randomBytes(16);

  const derivedKey = await new Promise<Buffer>((resolve, reject) => {
    crypto.scrypt(
      password,
      salt,
      KEYLEN,
      { N: SCRYPT_N, r: SCRYPT_R, p: SCRYPT_P },
      (err, key) => (err ? reject(err) : resolve(key as Buffer))
    );
  });

  return `scrypt$${SCRYPT_N}$${SCRYPT_R}$${SCRYPT_P}$${b64(salt)}$${b64(derivedKey)}`;
}

export async function verifyPassword(password: string, stored: string): Promise<boolean> {
  try {
    const parts = stored.split("$");
    // ["scrypt", "N", "r", "p", "saltB64", "hashB64"]
    if (parts.length !== 6) return false;
    if (parts[0] !== "scrypt") return false;

    const N = Number(parts[1]);
    const r = Number(parts[2]);
    const p = Number(parts[3]);
    const salt = fromB64(parts[4]);
    const expected = fromB64(parts[5]);

    const derivedKey = await new Promise<Buffer>((resolve, reject) => {
      crypto.scrypt(password, salt, expected.length, { N, r, p }, (err, key) =>
        err ? reject(err) : resolve(key as Buffer)
      );
    });

    // constant-time compare
    return crypto.timingSafeEqual(derivedKey, expected);
  } catch {
    return false;
  }
}
