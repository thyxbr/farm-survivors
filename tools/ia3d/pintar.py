"""Pinta uma malha com a etapa de textura do Hunyuan3D-2 numa placa AMD.

  python pintar.py <malha.glb> <pasta_recortes> <saida.glb> [--turbo]

<pasta_recortes> tem frente.png, lado.png e costas.png sem fundo (saem de gerar.py, em <saida>/recortes).
O rasterizador CUDA do Hunyuan3D e trocado pelo de cr_amd/custom_rasterizer (PyTorch puro).
"""
import os
import sys
import time

AQUI = os.environ.get("IA3D", "D:/ia3d")   # pesos, ambiente e clone do Hunyuan3D-2 (fora do repositório)
os.environ.setdefault("HY3DGEN_MODELS", os.path.join(AQUI, "models"))
os.environ.setdefault("HF_HOME", os.path.join(AQUI, "hf"))
os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "cr_amd"))   # rasterizador para AMD (aqui no repositório)
sys.path.insert(0, os.path.join(AQUI, "repo"))

import torch
import trimesh
from PIL import Image

import numpy as np

from hy3dgen.texgen import Hunyuan3DPaintPipeline
from hy3dgen.texgen.differentiable_renderer import mesh_render


def inpaint_vertices(texture, mask, vtx_pos, vtx_uv, pos_idx, uv_idx, method="smooth"):
    """Mesma ideia de meshVerticeInpaint (mesh_processor.py), em numpy: a cor passa de vértice pintado para
    vizinho sem cor, pesada por 1/distância², até não mudar mais. O original em Python puro leva dezenas de
    minutos numa malha de 40 mil faces (a extensão C++ dele não está compilada aqui)."""
    H, W, _ = texture.shape
    vi, ui = pos_idx.reshape(-1), uv_idx.reshape(-1)
    cu = np.rint(vtx_uv[ui, 0] * (W - 1)).astype(np.int64)
    cv = np.rint((1.0 - vtx_uv[ui, 1]) * (H - 1)).astype(np.int64)
    pintado = mask[cv, cu] > 0
    n = vtx_pos.shape[0]
    tem = np.zeros(n, bool)
    cor = np.zeros((n, texture.shape[2]), np.float32)
    tem[vi[pintado]] = True
    cor[vi[pintado]] = texture[cv[pintado], cu[pintado]]
    a, b = pos_idx.reshape(-1), np.roll(pos_idx, -1, axis=1).reshape(-1)       # aresta a -> b
    a, b = np.concatenate([a, b]), np.concatenate([b, a])
    peso = 1.0 / np.maximum(np.linalg.norm(vtx_pos[a] - vtx_pos[b], axis=1), 1e-4) ** 2
    for _ in range(4 * n):
        usa = tem[b] & ~tem[a]
        if not usa.any():
            break
        soma = np.zeros_like(cor)
        tot = np.zeros(n, np.float32)
        np.add.at(soma, a[usa], cor[b[usa]] * peso[usa, None])
        np.add.at(tot, a[usa], peso[usa])
        novo = tot > 0
        cor[novo] = soma[novo] / tot[novo, None]
        tem[novo] = True
    nt, nm = texture.copy(), mask.copy()
    ok = tem[vi]
    nt[cv[ok], cu[ok]] = cor[vi[ok]]
    nm[cv[ok], cu[ok]] = 255
    return nt, nm


mesh_render.meshVerticeInpaint = inpaint_vertices

malha_in, recortes, saida = sys.argv[1:4]
turbo = "--turbo" in sys.argv
print("torch", torch.__version__, "| gpu:", torch.cuda.get_device_name(0), flush=True)
imagens = [Image.open(os.path.join(recortes, n)).convert("RGBA")
           for n in ("frente.png", "lado.png", "costas.png") if os.path.exists(os.path.join(recortes, n))]
t0 = time.time()
pipe = Hunyuan3DPaintPipeline.from_pretrained(
    "tencent/Hunyuan3D-2", subfolder="hunyuan3d-paint-v2-0-turbo" if turbo else "hunyuan3d-paint-v2-0")
print("modelos carregados em %.0fs" % (time.time() - t0), flush=True)

# As vistas geradas ficam em <saida>_vistas: se a montagem da textura falhar, a GPU não roda de novo.
cache = os.path.splitext(saida)[0] + "_vistas"
os.makedirs(cache, exist_ok=True)


def cronometro(nome, fn):
    def roda(*a, **k):
        t = time.time()
        r = fn(*a, **k)
        print("ETAPA %-22s %.0fs" % (nome, time.time() - t), flush=True)
        return r
    return roda


class Guardado:
    """Embrulha um modelo: guarda em disco as imagens que ele devolve e as reusa na execução seguinte."""

    def __init__(self, modelo, prefixo):
        self.modelo, self.prefixo, self.n = modelo, prefixo, 0

    def __call__(self, *a, **k):
        base = os.path.join(cache, "%s_%d" % (self.prefixo, self.n))
        self.n += 1
        if os.path.exists(base + "_0.png"):
            fotos = []
            while os.path.exists("%s_%d.png" % (base, len(fotos))):
                fotos.append(Image.open("%s_%d.png" % (base, len(fotos))).convert("RGB"))
            print("ETAPA %-22s reusada (%d imagens)" % (self.prefixo, len(fotos)), flush=True)
            return fotos if self.prefixo == "vistas" else fotos[0]
        t = time.time()
        r = self.modelo(*a, **k)
        for i, im in enumerate(r if isinstance(r, list) else [r]):
            im.save("%s_%d.png" % (base, i))
        print("ETAPA %-22s %.0fs" % (self.prefixo, time.time() - t), flush=True)
        return r


pipe.models["delight_model"] = Guardado(pipe.models["delight_model"], "sem_luz")
pipe.models["multiview_model"] = Guardado(pipe.models["multiview_model"], "vistas")
pipe.bake_from_multiview = cronometro("projetar na textura", pipe.bake_from_multiview)
pipe.texture_inpaint = cronometro("fechar buracos", pipe.texture_inpaint)
mesh_render.meshVerticeInpaint = cronometro("  buracos por vertice", inpaint_vertices)
malha = trimesh.load(malha_in, force="mesh")
t0 = time.time()
pintada = pipe(malha, image=imagens)
print("pintura em %.0fs | pico de VRAM %.1f GB" % (time.time() - t0, torch.cuda.max_memory_allocated() / 2 ** 30), flush=True)
pintada.export(saida)
print("salvo:", saida)
