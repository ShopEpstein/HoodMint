// Cloudflare Worker entry point for the "hoodmint" Workers Builds project
// (Git-connected, deploy command `npx wrangler deploy` — see wrangler.jsonc).
// Serves web/ as static assets and handles POST /api/pin itself; everything
// else falls through to the ASSETS binding.
//
// Env required: PINATA_JWT — set in the Cloudflare dashboard for this Worker
// under Settings -> Variables and Secrets (add as a Secret), for both
// Production and Preview, then Retry build so the new deploy picks it up.
// Without it, /api/pin returns 503 and creators paste an IPFS CID manually
// instead — the console still works.

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

async function handlePin(request, env) {
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

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/api/pin") {
      if (request.method !== "POST") return json({ error: "POST only" }, 405);
      return handlePin(request, env);
    }
    return env.ASSETS.fetch(request);
  },
};
