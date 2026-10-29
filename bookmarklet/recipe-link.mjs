// The reference decoder for an r1 recipe link. Every build ports this --
// LIFT web and Coach web in JavaScript, the iPhones in Swift, the Androids in
// Kotlin -- and checks its port against fixtures/recipe-link.txt.
//
// It only unwraps. What comes out is exactly what Safari's share extension
// hands the iPhone apps, {url, jsonld}, so each build passes the blocks to the
// JSON-LD reader it already has and opens the review it already has.
//
// Refuses, returning null, rather than guessing: a missing or unknown prefix,
// bad base64url, bad deflate, more than MAX_BYTES once inflated, JSON that is
// not {v: 1, url: http(s) string, jsonld: [string, ...]}, or no blocks.
// A non-string entry in jsonld is dropped, not fatal, as on the iPhone.
import { inflateRawSync } from 'node:zlib';

export const PREFIX = 'r1';
export const MAX_BYTES = 512 * 1024;

export function decodeRecipeLink(text) {
  if (typeof text !== 'string') return null;
  const hash = text.indexOf('#');
  const fragment = hash >= 0 ? text.slice(hash + 1) : text;
  if (!fragment.startsWith(PREFIX)) return null;
  const data = fragment.slice(PREFIX.length);
  if (!/^[A-Za-z0-9_-]+$/.test(data)) return null;

  let json;
  try {
    const bytes = Buffer.from(data.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
    json = inflateRawSync(bytes, { maxOutputLength: MAX_BYTES }).toString('utf8');
  } catch {
    return null;
  }

  let doc;
  try {
    doc = JSON.parse(json);
  } catch {
    return null;
  }
  if (!doc || doc.v !== 1 || typeof doc.url !== 'string' || !Array.isArray(doc.jsonld)) return null;
  if (!/^https?:\/\//i.test(doc.url)) return null;
  const jsonld = doc.jsonld.filter((b) => typeof b === 'string');
  if (!jsonld.length) return null;
  return { url: doc.url, jsonld };
}
