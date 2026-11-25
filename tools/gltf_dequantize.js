// Tira o KHR_mesh_quantization de um GLB (o importador do Godot não lê essa extensão): os atributos
// inteiros normalizados (POSITION, NORMAL, TEXCOORD) viram float32 num buffer view novo, com o mesmo valor
// que o leitor glTF calcularia; a transformação dos nós continua a mesma. Sem dependências.
//   node tools/gltf_dequantize.js <entrada.glb> <saida.glb>
const fs = require("fs");
const [, , inPath, outPath] = process.argv;
if (!inPath || !outPath) { console.error("uso: node tools/gltf_dequantize.js <entrada.glb> <saida.glb>"); process.exit(1); }

const d = fs.readFileSync(inPath);
const jsonLen = d.readUInt32LE(12);
const j = JSON.parse(d.slice(20, 20 + jsonLen).toString());
const binStart = 20 + jsonLen + 8;
const bin = d.slice(binStart, binStart + d.readUInt32LE(20 + jsonLen));

const SIZE = { 5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4 };
const COMP = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4 };
function read(buf, off, ct) {
  switch (ct) {
    case 5120: return buf.readInt8(off);
    case 5121: return buf.readUInt8(off);
    case 5122: return buf.readInt16LE(off);
    case 5123: return buf.readUInt16LE(off);
    case 5125: return buf.readUInt32LE(off);
    default: return buf.readFloatLE(off);
  }
}
function norm(v, ct) {
  switch (ct) {
    case 5120: return Math.max(v / 127, -1);
    case 5121: return v / 255;
    case 5122: return Math.max(v / 32767, -1);
    case 5123: return v / 65535;
    default: return v;
  }
}

const extra = [];
let extraLen = 0;
const done = new Map();
for (const mesh of j.meshes) for (const prim of mesh.primitives) for (const [name, idx] of Object.entries(prim.attributes)) {
  const a = j.accessors[idx];
  if (a.componentType === 5126 || done.has(idx)) continue;
  const bv = j.bufferViews[a.bufferView];
  const n = COMP[a.type];
  const stride = bv.byteStride || SIZE[a.componentType] * n;
  const out = Buffer.alloc(a.count * n * 4);
  const min = Array(n).fill(Infinity), max = Array(n).fill(-Infinity);
  for (let i = 0; i < a.count; i++) {
    const v = [];
    for (let c = 0; c < n; c++) {
      let x = read(bin, (bv.byteOffset || 0) + (a.byteOffset || 0) + i * stride + c * SIZE[a.componentType], a.componentType);
      if (a.normalized) x = norm(x, a.componentType);
      v.push(x);
    }
    if (name === "NORMAL") { const l = Math.hypot(...v) || 1; for (let c = 0; c < n; c++) v[c] /= l; }
    for (let c = 0; c < n; c++) {
      out.writeFloatLE(v[c], (i * n + c) * 4);
      min[c] = Math.min(min[c], v[c]); max[c] = Math.max(max[c], v[c]);
    }
  }
  j.bufferViews.push({ buffer: 0, byteOffset: bin.length + extraLen, byteLength: out.length, target: 34962 });
  extra.push(out); extraLen += out.length;
  a.bufferView = j.bufferViews.length - 1; a.byteOffset = 0; a.componentType = 5126; delete a.normalized;
  if (name === "POSITION") { a.min = min; a.max = max; } else { delete a.min; delete a.max; }
  done.set(idx, true);
}
// texturas WebP sem a extensão: o Godot só tenta PNG/JPEG no `source`; com EXT_texture_webp ele decodifica
let webp = false;
for (const t of j.textures || []) {
  const img = j.images[t.source];
  if (img && img.mimeType === "image/webp") {
    t.extensions = Object.assign(t.extensions || {}, { EXT_texture_webp: { source: t.source } });
    delete t.source;
    webp = true;
  }
}
j.extensionsUsed = (j.extensionsUsed || []).filter(e => e !== "KHR_mesh_quantization");
if (webp && !j.extensionsUsed.includes("EXT_texture_webp")) j.extensionsUsed.push("EXT_texture_webp");
j.extensionsRequired = (j.extensionsRequired || []).filter(e => e !== "KHR_mesh_quantization");
if (!j.extensionsRequired.length) delete j.extensionsRequired;

let newBin = Buffer.concat([bin, ...extra]);
const pad = (4 - (newBin.length % 4)) % 4;
newBin = Buffer.concat([newBin, Buffer.alloc(pad)]);
j.buffers[0].byteLength = newBin.length;
let js = Buffer.from(JSON.stringify(j));
js = Buffer.concat([js, Buffer.alloc((4 - (js.length % 4)) % 4, 0x20)]);
const head = Buffer.alloc(12); head.write("glTF", 0); head.writeUInt32LE(2, 4);
const total = 12 + 8 + js.length + 8 + newBin.length; head.writeUInt32LE(total, 8);
const c1 = Buffer.alloc(8); c1.writeUInt32LE(js.length, 0); c1.write("JSON", 4);
const c2 = Buffer.alloc(8); c2.writeUInt32LE(newBin.length, 0); c2.write("BIN\0", 4);
fs.writeFileSync(outPath, Buffer.concat([head, c1, js, c2, newBin]));
console.log(`gravado ${outPath} (${done.size} atributos convertidos)`);
