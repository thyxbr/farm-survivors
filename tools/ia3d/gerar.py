"""Gera uma malha 3D a partir de tres vistas (frente, lado, costas) com Hunyuan3D-2mv.

Uso:
  python gerar.py <pasta_com_frente_lado_costas.png> <saida.glb> [--passos 50] [--octree 380] [--turbo]

So a etapa de geometria: nada de textura (que exige CUDA).
A vista de lado deve estar com o objeto olhando para a esquerda da imagem.

O recorte de fundo roda em um processo separado (--recortar): onnxruntime e o
PyTorch ROCm no mesmo processo derrubam o Python com violacao de acesso.
"""
import argparse
import os
import subprocess
import sys
import time

AQUI = os.environ.get("IA3D", "D:/ia3d")   # pesos, ambiente e clone do Hunyuan3D-2 (fora do repositório)
os.environ.setdefault("HY3DGEN_MODELS", os.path.join(AQUI, "models"))
os.environ.setdefault("HF_HOME", os.path.join(AQUI, "hf"))
os.environ.setdefault("U2NET_HOME", os.path.join(AQUI, "models", "u2net"))
os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")
sys.path.insert(0, os.path.join(AQUI, "repo"))

from PIL import Image

NOMES = {"front": "frente.png", "left": "lado.png", "back": "costas.png"}

ap = argparse.ArgumentParser()
ap.add_argument("pasta")
ap.add_argument("saida")
ap.add_argument("--passos", type=int, default=50)
ap.add_argument("--octree", type=int, default=380)
ap.add_argument("--semente", type=int, default=12345)
ap.add_argument("--turbo", action="store_true")
ap.add_argument("--recortar", action="store_true", help="interno: so remove o fundo")
a = ap.parse_args()

recortes = os.path.join(os.path.dirname(os.path.abspath(a.saida)), "recortes")
os.makedirs(recortes, exist_ok=True)

if a.recortar:
    from hy3dgen.rembg import BackgroundRemover
    rembg = BackgroundRemover()
    for arq in NOMES.values():
        caminho = os.path.join(a.pasta, arq)
        if not os.path.exists(caminho):
            continue
        img = Image.open(caminho)
        tem_alfa = img.mode == "RGBA" and img.getextrema()[3][0] < 250
        img = img.convert("RGBA") if tem_alfa else rembg(img.convert("RGB"))
        img.save(os.path.join(recortes, arq))
        print("recortado:", arq, flush=True)
    sys.exit(0)

subprocess.run([sys.executable, os.path.abspath(__file__), a.pasta, a.saida, "--recortar"], check=True)
imagens = {}
for chave, arq in NOMES.items():
    caminho = os.path.join(recortes, arq)
    if os.path.exists(caminho):
        imagens[chave] = Image.open(caminho).convert("RGBA")
print("vistas:", list(imagens), flush=True)

import torch
from hy3dgen.shapegen import Hunyuan3DDiTFlowMatchingPipeline

print("torch", torch.__version__, "| gpu:", torch.cuda.get_device_name(0), flush=True)

sub = "hunyuan3d-dit-v2-mv-turbo" if a.turbo else "hunyuan3d-dit-v2-mv"
t0 = time.time()
pipe = Hunyuan3DDiTFlowMatchingPipeline.from_pretrained(
    "tencent/Hunyuan3D-2mv", subfolder=sub, variant="fp16")
if a.turbo:
    pipe.enable_flashvdm()
print("modelo carregado em %.0fs" % (time.time() - t0), flush=True)

t0 = time.time()
malha = pipe(
    image=imagens,
    num_inference_steps=5 if a.turbo else a.passos,
    octree_resolution=a.octree,
    num_chunks=20000,
    generator=torch.manual_seed(a.semente),
    output_type="trimesh",
)[0]
print("geracao em %.0fs | vertices %d | faces %d" % (
    time.time() - t0, len(malha.vertices), len(malha.faces)), flush=True)
malha.export(a.saida)
print("salvo:", a.saida)
