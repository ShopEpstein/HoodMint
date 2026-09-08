// Cloudflare Pages Function: POST /api/pin
// Same job as api/pin.js (the Vercel version), rewritten for the handler
// shape Cloudflare Pages Functions require: named onRequest* exports using
// the Fetch API (Request/Response, context.env) instead of Node's (req, res).
// Pins collection art + auto-generated metadata to IPFS (Pinata) and returns
// a ready-to-use baseURI. The Pinata key stays server-side (never shipped to
// the browser).
//
// Env required: PINATA_JWT — set in Cloudflare Pages -> Settings ->
// Environment variables (Production AND Preview), from app.pinata.cloud ->
// API Keys -> new key -> copy JWT.
//
// Request body (JSON): same shape as api/pin.js. Response: same shape too.

const PINATA_PIN_FILE = "https://api.pinata.cloud/pinning/pinFileToIPFS";

async function pinDirectory(files, rootFolder, jwt) {
  const form = new FormData();
  for (const f of files) {
    const blob = new Blob([f.buffer], { type: f.mime || "application/octet-stream" });
    // filename carries a folder prefix so Pinata pins a directory; CID = that folder
    form.append("file", blob, `${rootFolder}/${f.path}`);
  }
  form.append("pinataOptions", JSON.stringify({ cidVersion: 1 }));
  form.append("pinataMetadata", JSON.stringify({ name: rootFolder }));

  const res = await fetch(PINATA_PIN_FILE, {
    method: "POST",
    headers: { Authorization: `Bearer ${jwt}` },
    body: form,
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Pinata ${res.status}: ${text.slice(0, 160)}`);
  }
  const data = await res.json();
  return data.IpfsHash; // directory CID
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function extOf(filename) {
  const m = /\.[a-z0-9]+$/i.exec(filename || "");
  return m ? m[0].toLowerCase() : ".png";
}

function base64ToBytes(base64) {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

export async function onRequestPost({ request, env }) {
  const jwt = env.PINATA_JWT;
  if (!jwt) {
    return json({ error: "PINATA_JWT not set — paste a CID manually instead." }, 503);
  }

  try {
    const body = await request.json();
    const { name, description = "", tokenCount, sameArt, images } = body;

    if (!name || !tokenCount || !Array.isArray(images) || images.length === 0) {
      return json({ error: "Missing name, tokenCount, or images." }, 400);
    }
    if (!sameArt && images.length < tokenCount) {
      return json({ error: `Numbered set needs ${tokenCount} images, got ${images.length}.` }, 400);
    }

    // 1) pin images as a directory
    const imageFiles = images.map((im, i) => ({
      path: sameArt ? "art" + extOf(im.filename) : `${i + 1}${extOf(im.filename)}`,
      buffer: base64ToBytes(im.base64),
      mime: im.mime,
    }));
    const imagesCID = await pinDirectory(imageFiles, "assets", jwt);

    // 2) build metadata files referencing ipfs://imagesCID/<file>
    const metaFiles = [];
    for (let id = 1; id <= tokenCount; id++) {
      const imgPath = sameArt ? "art" + extOf(images[0].filename) : `${id}${extOf(images[id - 1].filename)}`;
      const metaJson = {
        name: `${name} #${id}`,
        description,
        image: `ipfs://${imagesCID}/${imgPath}`,
      };
      metaFiles.push({
        path: `${id}.json`,
        buffer: new TextEncoder().encode(JSON.stringify(metaJson, null, 2)),
        mime: "application/json",
      });
    }
    const metaCID = await pinDirectory(metaFiles, "meta", jwt);

    return json({
      baseURI: `ipfs://${metaCID}/`,
      imagesCID,
      metaCID,
      count: tokenCount,
    });
  } catch (e) {
    return json({ error: e.message || "pin failed" }, 500);
  }
}

export async function onRequestGet() {
  return json({ error: "POST only" }, 405);
}
