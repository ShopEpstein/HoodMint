// Vercel serverless function: POST /api/pin
// Pins collection art + auto-generated metadata to IPFS (Pinata) and returns a
// ready-to-use baseURI. The Pinata key stays server-side (never shipped to the browser).
//
// Env required: PINATA_JWT   (https://app.pinata.cloud -> API Keys -> new key -> copy JWT)
//
// Request body (JSON):
//   {
//     name: "Hood Ducks",
//     description: "A free Hoodstreet drop.",
//     tokenCount: 2222,
//     sameArt: true,                       // one image shared by all tokens
//     images: [ { filename: "1.png", mime: "image/png", base64: "..." }, ... ]
//   }
// Response: { baseURI, imagesCID, metaCID, count }

const PINATA_PIN_FILE = "https://api.pinata.cloud/pinning/pinFileToIPFS";

async function pinDirectory(files, rootFolder, jwt) {
  // files: [{ path: "1.png", buffer: <Buffer>, mime }]
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

module.exports = async function handler(req, res) {
  if (req.method !== "POST") {
    res.status(405).json({ error: "POST only" });
    return;
  }
  const jwt = process.env.PINATA_JWT;
  if (!jwt) {
    res.status(503).json({ error: "PINATA_JWT not set — paste a CID manually instead." });
    return;
  }

  try {
    const body = typeof req.body === "string" ? JSON.parse(req.body) : req.body;
    const { name, description = "", tokenCount, sameArt, images } = body;

    if (!name || !tokenCount || !Array.isArray(images) || images.length === 0) {
      res.status(400).json({ error: "Missing name, tokenCount, or images." });
      return;
    }
    if (!sameArt && images.length < tokenCount) {
      res.status(400).json({ error: `Numbered set needs ${tokenCount} images, got ${images.length}.` });
      return;
    }

    // 1) pin images as a directory
    const imageFiles = images.map((im, i) => ({
      path: sameArt ? "art" + extOf(im.filename) : `${i + 1}${extOf(im.filename)}`,
      buffer: Buffer.from(im.base64, "base64"),
      mime: im.mime,
    }));
    const imagesCID = await pinDirectory(imageFiles, "assets", jwt);

    // 2) build metadata files referencing ipfs://imagesCID/<file>
    const metaFiles = [];
    for (let id = 1; id <= tokenCount; id++) {
      const imgPath = sameArt ? "art" + extOf(images[0].filename) : `${id}${extOf(images[id - 1].filename)}`;
      const json = {
        name: `${name} #${id}`,
        description,
        image: `ipfs://${imagesCID}/${imgPath}`,
      };
      metaFiles.push({
        path: `${id}.json`,
        buffer: Buffer.from(JSON.stringify(json, null, 2)),
        mime: "application/json",
      });
    }
    const metaCID = await pinDirectory(metaFiles, "meta", jwt);

    res.status(200).json({
      baseURI: `ipfs://${metaCID}/`,
      imagesCID,
      metaCID,
      count: tokenCount,
    });
  } catch (e) {
    res.status(500).json({ error: e.message || "pin failed" });
  }
};

function extOf(filename) {
  const m = /\.[a-z0-9]+$/i.exec(filename || "");
  return m ? m[0].toLowerCase() : ".png";
}
