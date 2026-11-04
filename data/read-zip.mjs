// Reads one member of a zip file as a stream, without unpacking anything to
// disk and with nothing but Node's own standard library. The Road Food check
// uses it on USDA's Branded Foods CSV zip, which is about 430 MB zipped and
// about 3 GB unzipped: the member is inflated chunk by chunk as it is read.
//
// Covers what that file needs and no more: stored (0) and deflated (8)
// members, ZIP64 sizes and offsets, and a data descriptor (sizes are taken
// from the central directory, never from the local header). Encrypted members
// and any other compression method are refused with a message, never guessed
// at. Every member's CRC-32 and length are checked as it is read, so a
// damaged download fails loudly rather than giving short or wrong rows.

import { open } from "node:fs/promises";
import { createReadStream } from "node:fs";
import { pipeline } from "node:stream";
import * as zlib from "node:zlib";

const EOCD = 0x06054b50;
const ZIP64_LOCATOR = 0x07064b50;
const ZIP64_EOCD = 0x06064b50;
const CENTRAL = 0x02014b50;
const LOCAL = 0x04034b50;
const MAX32 = 0xffffffff;

async function readAt(fh, length, position) {
  const buf = Buffer.alloc(length);
  let got = 0;
  while (got < length) {
    const { bytesRead } = await fh.read(buf, got, length - got, position + got);
    if (!bytesRead) throw new Error(`the file ends ${length - got} bytes early`);
    got += bytesRead;
  }
  return buf;
}

// Every member: { name, method, flags, crc32, compressedSize, size, localHeaderOffset }.
export async function listZip(path) {
  const fh = await open(path, "r");
  try {
    const { size } = await fh.stat();
    // The end record is 22 bytes plus a comment of up to 65,535; a ZIP64
    // locator, when there is one, sits immediately before it.
    const tailLength = Math.min(size, 22 + 65535 + 20);
    const tail = await readAt(fh, tailLength, size - tailLength);
    let end = -1;
    for (let i = tailLength - 22; i >= 0; i--) {
      if (tail.readUInt32LE(i) === EOCD) { end = i; break; }
    }
    if (end < 0) throw new Error("not a zip file (no end-of-central-directory record)");
    let count = tail.readUInt16LE(end + 10);
    let cdSize = tail.readUInt32LE(end + 12);
    let cdOffset = tail.readUInt32LE(end + 16);
    if (end >= 20 && tail.readUInt32LE(end - 20) === ZIP64_LOCATOR) {
      const z = await readAt(fh, 56, Number(tail.readBigUInt64LE(end - 20 + 8)));
      if (z.readUInt32LE(0) !== ZIP64_EOCD) throw new Error("the ZIP64 end record is not where its locator says");
      count = Number(z.readBigUInt64LE(32));
      cdSize = Number(z.readBigUInt64LE(40));
      cdOffset = Number(z.readBigUInt64LE(48));
    }
    const cd = await readAt(fh, cdSize, cdOffset);
    const entries = [];
    let p = 0;
    for (let n = 0; n < count; n++) {
      if (cd.readUInt32LE(p) !== CENTRAL) throw new Error(`central directory entry ${n + 1} is damaged`);
      const flags = cd.readUInt16LE(p + 8);
      const nameLength = cd.readUInt16LE(p + 28);
      const extraLength = cd.readUInt16LE(p + 30);
      const commentLength = cd.readUInt16LE(p + 32);
      const e = {
        name: cd.toString(flags & 0x800 ? "utf8" : "latin1", p + 46, p + 46 + nameLength),
        method: cd.readUInt16LE(p + 10),
        flags,
        crc32: cd.readUInt32LE(p + 16),
        compressedSize: cd.readUInt32LE(p + 20),
        size: cd.readUInt32LE(p + 24),
        localHeaderOffset: cd.readUInt32LE(p + 42),
      };
      // ZIP64 extra field (0x0001): the 64-bit values, in this order, of
      // whichever 32-bit fields were saturated.
      let x = p + 46 + nameLength;
      const xEnd = x + extraLength;
      while (x + 4 <= xEnd) {
        const id = cd.readUInt16LE(x), len = cd.readUInt16LE(x + 2);
        if (id === 0x0001) {
          let q = x + 4;
          for (const k of ["size", "compressedSize", "localHeaderOffset"]) {
            if (e[k] === MAX32 && q + 8 <= x + 4 + len) { e[k] = Number(cd.readBigUInt64LE(q)); q += 8; }
          }
        }
        x += 4 + len;
      }
      entries.push(e);
      p += 46 + nameLength + extraLength + commentLength;
    }
    return entries;
  } finally {
    await fh.close();
  }
}

// The member's bytes, uncompressed, as an async iterable of Buffers.
export async function* zipEntryChunks(path, entry) {
  if (entry.flags & 0x1) throw new Error(`${entry.name} is encrypted`);
  if (entry.method !== 0 && entry.method !== 8) {
    throw new Error(`${entry.name} uses compression method ${entry.method}; only stored (0) and deflate (8) are read`);
  }
  const fh = await open(path, "r");
  let start;
  try {
    const local = await readAt(fh, 30, entry.localHeaderOffset);
    if (local.readUInt32LE(0) !== LOCAL) throw new Error(`${entry.name}: local header is not where the directory says`);
    start = entry.localHeaderOffset + 30 + local.readUInt16LE(26) + local.readUInt16LE(28);
  } finally {
    await fh.close();
  }
  let crc = 0, length = 0;
  if (entry.compressedSize > 0) {
    const raw = createReadStream(path, { start, end: start + entry.compressedSize - 1, highWaterMark: 1 << 20 });
    const stream = entry.method === 8 ? pipeline(raw, zlib.createInflateRaw({ chunkSize: 1 << 20 }), () => {}) : raw;
    for await (const chunk of stream) {
      if (zlib.crc32) crc = zlib.crc32(chunk, crc);
      length += chunk.length;
      yield chunk;
    }
  }
  if (length !== entry.size) throw new Error(`${entry.name}: read ${length} bytes, the zip says ${entry.size}`);
  if (zlib.crc32 && crc >>> 0 !== entry.crc32) throw new Error(`${entry.name}: CRC-32 does not match; the download is damaged`);
}
