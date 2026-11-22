"""Substituto em PyTorch puro do `custom_rasterizer` do Hunyuan3D-2 (o original é uma extensão CUDA).

Mesma interface e mesma conta do original (hy3dgen/texgen/custom_rasterizer): `rasterize` devolve, por pixel, o
índice da face da frente (+1; 0 = vazio) e as coordenadas baricêntricas com correção de perspectiva;
`interpolate` mistura um atributo dos vértices com elas.

Roda na CPU: os triângulos são agrupados pelo tamanho da caixa em pixels e cada grupo é resolvido de uma vez
(grade de pixels por triângulo, teste dentro/fora, profundidade), com o z-buffer por `scatter_reduce(amin)`.
Uma foto de 2048 x 2048 com dezenas de milhares de faces leva poucos segundos.
"""
import torch

_BITS = 31
_VAZIO = (1 << 62)
_LOTE = 6_000_000            # pixels candidatos por lote


def _tela(V, W, H):
    w = V[:, 3]
    x = (V[:, 0] / w * 0.5 + 0.5) * (W - 1) + 0.5
    y = (V[:, 1] / w * 0.5 + 0.5) * (H - 1) + 0.5
    z = V[:, 2] / w * 0.49999 + 0.5
    return x, y, z


def _bari(ax, ay, bx, by, cx, cy, px, py):
    """Igual a calculateBarycentricCoordinate do original (alpha, beta, gamma); área zero -> -1."""
    area = (cx - ax) * (by - ay) - (bx - ax) * (cy - ay)
    beta = (cx - ax) * (py - ay) - (px - ax) * (cy - ay)
    gamma = (px - ax) * (by - ay) - (bx - ax) * (py - ay)
    ok = area != 0
    inv = torch.where(ok, 1.0 / torch.where(ok, area, torch.ones_like(area)), torch.zeros_like(area))
    beta, gamma = beta * inv, gamma * inv
    alpha = 1.0 - beta - gamma
    neg = torch.full_like(alpha, -1.0)
    return torch.where(ok, alpha, neg), torch.where(ok, beta, neg), torch.where(ok, gamma, neg)


def rasterize(pos, tri, resolution, clamp_depth=torch.zeros(0), use_depth_prior=0):
    dev = pos.device
    V = pos[0].detach().float().cpu()
    F = tri.detach().long().cpu()
    H, W = int(resolution[0]), int(resolution[1])
    x, y, z = _tela(V, W, H)
    fx, fy, fz = x[F], y[F], z[F]                                   # (nf, 3)
    x0 = fx.min(dim=1).values.floor().long().clamp(0, W - 1)
    x1 = (fx.max(dim=1).values.floor().long() + 1).clamp(0, W - 1)
    y0 = fy.min(dim=1).values.floor().long().clamp(0, H - 1)
    y1 = (fy.max(dim=1).values.floor().long() + 1).clamp(0, H - 1)
    lado = torch.maximum(x1 - x0, y1 - y0) + 1
    fora = (fx.max(dim=1).values < 0) | (fx.min(dim=1).values > W) | (fy.max(dim=1).values < 0) | (fy.min(dim=1).values > H)
    zbuf = torch.full((H * W,), _VAZIO, dtype=torch.int64)
    prior = None
    if use_depth_prior and clamp_depth.numel():
        prior = clamp_depth.detach().float().cpu().reshape(-1) * 0.49999 + 0.5 + 1e-6
    s = 2
    while True:
        grupo = torch.where((lado <= s) & (lado > (s // 2 if s > 2 else 0)) & ~fora)[0]
        if len(grupo):
            oy, ox = torch.meshgrid(torch.arange(s), torch.arange(s), indexing="ij")
            ox, oy = ox.reshape(1, -1), oy.reshape(1, -1)
            passo = max(1, _LOTE // (s * s))
            for i in range(0, len(grupo), passo):
                g = grupo[i:i + passo]
                px = x0[g, None] + ox
                py = y0[g, None] + oy
                dentro = (px <= x1[g, None]) & (py <= y1[g, None])
                cxp, cyp = px.float() + 0.5, py.float() + 0.5
                a, b, c = _bari(fx[g, 0:1], fy[g, 0:1], fx[g, 1:2], fy[g, 1:2], fx[g, 2:3], fy[g, 2:3], cxp, cyp)
                dentro &= (a >= 0) & (a <= 1) & (b >= 0) & (b <= 1) & (c >= 0) & (c <= 1)
                prof = a * fz[g, 0:1] + b * fz[g, 1:2] + c * fz[g, 2:3]
                pix = py * W + px
                if prior is not None:
                    dentro &= prof >= prior[pix.clamp(0, H * W - 1)]
                ficha = (prof * (2 << 17)).long() * (1 << _BITS) + (g[:, None] + 1)
                zbuf.scatter_reduce_(0, pix[dentro], ficha[dentro], reduce="amin", include_self=True)
        if s >= max(W, H) * 2:
            break
        s *= 2
    cheio = zbuf != _VAZIO
    find = torch.where(cheio, zbuf & ((1 << _BITS) - 1), torch.zeros_like(zbuf))
    bar = torch.zeros((H * W, 3), dtype=torch.float32)
    idx = torch.where(cheio)[0]
    if len(idx):
        f = find[idx] - 1
        vx, vy, vw = x[F[f]], y[F[f]], V[:, 3][F[f]]
        cxp = (idx % W).float() + 0.5
        cyp = torch.div(idx, W, rounding_mode="floor").float() + 0.5
        a, b, c = _bari(vx[:, 0], vy[:, 0], vx[:, 1], vy[:, 1], vx[:, 2], vy[:, 2], cxp, cyp)
        b3 = torch.stack([a / vw[:, 0], b / vw[:, 1], c / vw[:, 2]], dim=1)
        bar[idx] = b3 / b3.sum(dim=1, keepdim=True)
    return find.int().reshape(H, W).to(dev), bar.reshape(H, W, 3).to(dev)


def interpolate(col, findices, barycentric, tri):
    f = findices - 1 + (findices == 0)
    vcol = col[0, tri.long()[f.long()]]
    result = barycentric.view(*barycentric.shape, 1) * vcol
    result = torch.sum(result, axis=-2)
    return result.view(1, *result.shape)
