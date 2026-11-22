"""Reduz a malha bruta de gerar.py para a pintura (FaceReducer do Hunyuan3D).
  python reduzir.py <bruto.glb> <saida.glb> [faces=40000]"""
import os, sys
AQUI = os.environ.get("IA3D", "D:/ia3d")   # pesos, ambiente e clone do Hunyuan3D-2 (fora do repositório)
sys.path.insert(0, os.path.join(AQUI, "repo"))
import trimesh
from hy3dgen.shapegen import FaceReducer, FloaterRemover, DegenerateFaceRemover
m = trimesh.load(sys.argv[1], force="mesh")
print("entrada", len(m.faces), "faces, pedacos:", len(m.split(only_watertight=False)), flush=True)
pc = m.split(only_watertight=False)
m = max(pc, key=lambda p: len(p.faces))   # so a peca principal: o resto sao lascas ou placas soltas (fundo da vista de costas)
print("pedacos:", sorted(len(p.faces) for p in pc), flush=True)
m = DegenerateFaceRemover()(m)
m = FaceReducer()(m, max_facenum=int(sys.argv[3]) if len(sys.argv) > 3 else 40000)
print("saida", len(m.faces), "faces, pedacos:", len(m.split(only_watertight=False)), flush=True)
m.export(sys.argv[2])
