"""Sintetiza os sons ambiente dos mapas (chuva, pântano, geleira, vulcão e dungeon) em OGG estéreo com loop.

Tudo é feito por código (numpy + ffmpeg), sem amostras de terceiros. Os loops emendam sem estalo porque
o ruído de fundo é gerado no domínio da frequência sobre o buffer inteiro (periódico por construção), os
eventos curtos (gotas, sapos, bolhas) dão a volta no fim do buffer e o eco é uma convolução circular.

Uso (na raiz do projeto):
    python tools/audio/gen_ambience.py            # gera todos em assets/audio/ambience/
    python tools/audio/gen_ambience.py rain lava  # só alguns
"""
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "ambience")


# ------------------------------------------------------------------ blocos
def shaped_noise(rng, n, mag_fn):
    """Ruído periódico (loop perfeito) com o espectro de amplitude mag_fn(freq_hz)."""
    f = np.fft.rfftfreq(n, 1.0 / SR)
    mag = mag_fn(np.maximum(f, 1.0))
    mag[0] = 0.0
    ph = rng.uniform(0, 2 * np.pi, f.size)
    x = np.fft.irfft(mag * np.exp(1j * ph), n)
    return x / (np.std(x) + 1e-12)


def moving_noise(rng, n, mag_fn_t, frame=4096):
    """Ruído cujo espectro muda com o tempo: mag_fn_t(freq_hz, t_fase 0..1). Overlap-add circular."""
    hop = frame // 4
    win = np.hanning(frame)
    out = np.zeros(n)
    f = np.fft.rfftfreq(frame, 1.0 / SR)
    f = np.maximum(f, 1.0)
    for start in range(0, n, hop):
        mag = mag_fn_t(f, start / n)
        spec = mag * np.exp(1j * rng.uniform(0, 2 * np.pi, f.size))
        seg = np.fft.irfft(spec, frame) * win
        idx = (np.arange(frame) + start) % n
        np.add.at(out, idx, seg)
    return out / (np.std(out) + 1e-12)


def periodic_lfo(n, cycles, phase=0.0):
    """Senoide com número inteiro de ciclos no buffer (emenda no loop)."""
    t = np.arange(n) / n
    return np.sin(2 * np.pi * cycles * t + phase)


def add_event(buf, start, sig, pan=0.0):
    """Soma `sig` (mono) em buf (n, 2) a partir de `start`, dando a volta no fim. pan -1..1."""
    n = buf.shape[0]
    idx = (np.arange(sig.size) + int(start)) % n
    l = np.cos((pan + 1) * np.pi / 4)
    r = np.sin((pan + 1) * np.pi / 4)
    np.add.at(buf[:, 0], idx, sig * l * 1.414)
    np.add.at(buf[:, 1], idx, sig * r * 1.414)


def env_exp(length, tau):
    t = np.arange(length) / SR
    return np.exp(-t / tau)


def lowpass_fft(x, cut, slope=2.0):
    n = x.size
    f = np.fft.rfftfreq(n, 1.0 / SR)
    return np.fft.irfft(np.fft.rfft(x) / (1 + (f / cut) ** slope), n)


def bandpass_burst(rng, length, lo, hi):
    x = rng.standard_normal(length)
    f = np.fft.rfftfreq(length, 1.0 / SR)
    m = ((f >= lo) & (f <= hi)).astype(float)
    return np.fft.irfft(np.fft.rfft(x) * m, length)


def reverb(buf, rng, seconds, wet, damp=3000.0):
    """Eco por convolução circular com uma cauda de ruído que decai (e escurece)."""
    n = buf.shape[0]
    L = int(seconds * SR)
    out = buf.copy()
    for ch in range(2):
        ir = rng.standard_normal(L) * np.exp(-np.arange(L) / SR / (seconds / 6.0))
        ir = lowpass_fft(ir, damp)
        ir /= np.sqrt(np.sum(ir ** 2)) + 1e-12
        irp = np.zeros(n)
        irp[:L] = ir
        out[:, ch] += wet * np.fft.irfft(np.fft.rfft(buf[:, ch]) * np.fft.rfft(irp), n)
    return out


def stereo_bed(rng, n, mag_fn, width=0.6):
    a = shaped_noise(rng, n, mag_fn)
    b = shaped_noise(rng, n, mag_fn)
    c = shaped_noise(rng, n, mag_fn)
    return np.stack([a * (1 - width) + b * width, a * (1 - width) + c * width], axis=1)


def finish(buf, rms_db):
    buf = buf - buf.mean(axis=0)
    rms = np.sqrt(np.mean(buf ** 2))
    buf *= 10 ** (rms_db / 20) / (rms + 1e-12)
    # limitador suave: picos raros (um sapo alto, uma gota perto) não estouram
    return np.tanh(buf * 1.2) / 1.2


def write_ogg(name, buf):
    os.makedirs(OUT, exist_ok=True)
    pcm = (np.clip(buf, -1, 1) * 32000).astype("<i2")
    tmp = os.path.join(tempfile.gettempdir(), name + "_amb.wav")
    with wave.open(tmp, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    dst = os.path.abspath(os.path.join(OUT, name + ".ogg"))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "4", dst],
                   check=True)
    os.remove(tmp)
    print("ok", dst, "%.1f s" % (buf.shape[0] / SR))


# ------------------------------------------------------------------ chuva
def rain(rng):
    n = SR * 14
    # chiado: muitas gotas finas longe, cheio entre 1 e 7 kHz, sem grave embolado
    hiss = stereo_bed(rng, n, lambda f: (f / 1500) ** 0.6 / (1 + (f / 6500) ** 2.5) / (1 + (400 / f) ** 2), 0.8)
    swell = 1.0 + 0.10 * periodic_lfo(n, 2) + 0.06 * periodic_lfo(n, 5, 1.3)
    buf = hiss * 0.55 * swell[:, None]
    # chuva batendo no chão e nas folhas: ruído médio mais escuro
    body = stereo_bed(rng, n, lambda f: 1 / (1 + (f / 900) ** 2) / (1 + (120 / f) ** 3), 0.7)
    buf += body * 0.35
    # gotas perto: estalinhos curtos de ruído claro, muitos fracos e poucos fortes
    for _ in range(9000):
        L = int(rng.uniform(0.0015, 0.006) * SR)
        g = bandpass_burst(rng, L, rng.uniform(1500, 3500), rng.uniform(5000, 11000)) * env_exp(L, L / SR / 4)
        add_event(buf, rng.integers(n), g * rng.pareto(3.0) * 0.08, rng.uniform(-0.9, 0.9))
    # pingos em poça / telha: "plic" com o tom caindo
    for _ in range(260):
        L = int(0.05 * SR)
        t = np.arange(L) / SR
        f0 = rng.uniform(1800, 4200)
        tone = np.sin(2 * np.pi * np.cumsum(f0 * (1 - 0.35 * t / t[-1])) / SR) * env_exp(L, 0.009)
        add_event(buf, rng.integers(n), tone * rng.uniform(0.03, 0.12), rng.uniform(-0.8, 0.8))
    # escorrendo das calhas: fio de água grave e contínuo, bem baixo
    buf += stereo_bed(rng, n, lambda f: np.exp(-((f - 350) / 220) ** 2), 0.5) * 0.08
    buf = reverb(buf, rng, 1.2, 0.25, 5000)
    return finish(buf, -25)


# ------------------------------------------------------------------ pântano
def croak(rng, base, pulses, rate):
    """Coaxar: rajada de pulsos com tom grave e harmônicos (garganta)."""
    dur = pulses / rate
    L = int(dur * SR)
    t = np.arange(L) / SR
    f0 = base * (1 + 0.08 * np.sin(np.pi * t / dur))
    ph = 2 * np.pi * np.cumsum(f0) / SR
    tone = np.sin(ph) + 0.6 * np.sin(2 * ph) + 0.35 * np.sin(3 * ph + 0.4) + 0.2 * np.sin(5 * ph)
    pulse = np.clip(np.sin(np.pi * rate * t), 0, 1) ** 3
    env = np.sin(np.pi * t / dur) ** 0.5
    return tone * pulse * env


def bloop(rng, f_lo, f_hi, dur):
    L = int(dur * SR)
    t = np.arange(L) / SR
    f = f_lo * (f_hi / f_lo) ** (t / dur)   # bolha sobe de tom ao estourar
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * t / dur) ** 1.5


def swamp(rng):
    n = SR * 24
    # fundo: água parada e brisa abafada
    buf = stereo_bed(rng, n, lambda f: 1 / (1 + (f / 500) ** 2) / (1 + (60 / f) ** 2), 0.7) * 0.22
    # insetos: chiado agudo em pulsos rápidos, que cresce e some devagar
    t = np.arange(n) / SR
    for k, (fc, rate, cyc) in enumerate([(4300, 38, 3), (5600, 52, 2), (3600, 27, 4)]):
        band = shaped_noise(rng, n, lambda f, fc=fc: np.exp(-((f - fc) / 350) ** 2))
        am = (0.5 + 0.5 * np.sin(2 * np.pi * rate * t)) ** 2
        sw = np.clip(periodic_lfo(n, cyc, k * 2.1), 0, 1) ** 1.5
        pan = (-0.6, 0.5, 0.0)[k]
        add_event(buf, 0, band * am * sw * 0.07, pan)
    # sapos: alguns perto (graves, fortes), outros longe (mais baixos e abafados)
    frogs = [(140, 0.30, -0.5, 12, 30), (210, 0.22, 0.6, 9, 38), (320, 0.10, -0.2, 7, 45), (95, 0.18, 0.2, 18, 24)]
    for base, amp, pan, count, rate in frogs:
        for _ in range(count):
            start = rng.integers(n)
            reps = rng.integers(1, 4)
            for r in range(reps):
                c = croak(rng, base * rng.uniform(0.95, 1.05), int(rng.integers(6, 14)), rate)
                if amp < 0.15:
                    c = lowpass_fft(c, 900)
                add_event(buf, start + int(r * (c.size + rng.uniform(0.08, 0.2) * SR)), c * amp, pan)
    # bolhas subindo da lama
    for _ in range(70):
        b = bloop(rng, rng.uniform(180, 320), rng.uniform(500, 900), rng.uniform(0.03, 0.07))
        add_event(buf, rng.integers(n), b * rng.uniform(0.04, 0.12), rng.uniform(-0.7, 0.7))
    buf = reverb(buf, rng, 1.6, 0.35, 2500)
    return finish(buf, -26)


# ------------------------------------------------------------------ geleira
def chime(rng, f0, dur):
    L = int(dur * SR)
    t = np.arange(L) / SR
    out = np.zeros(L)
    for ratio, a, tau in [(1.0, 1.0, 0.6), (2.76, 0.5, 0.35), (5.40, 0.25, 0.2), (8.93, 0.12, 0.12)]:
        out += a * np.sin(2 * np.pi * f0 * ratio * t) * np.exp(-t / (tau * dur))
    return out * (1 - np.exp(-t / 0.002))


def ice(rng):
    n = SR * 24
    # vento frio: ruído com um assobio que passeia de tom e cresce em rajadas
    def wind_mag(f, ph):
        center = 520 + 260 * np.sin(2 * np.pi * 3 * ph) + 120 * np.sin(2 * np.pi * 7 * ph + 1)
        q = np.exp(-((f - center) / (center * 0.12)) ** 2)
        base = 1 / (1 + (f / 1200) ** 2) / (1 + (90 / f) ** 2)
        return base * 0.6 + q * 1.4
    gust = 0.65 + 0.35 * (0.5 + 0.5 * periodic_lfo(n, 3, 0.4)) ** 2
    wl = moving_noise(rng, n, wind_mag)
    wr = moving_noise(rng, n, wind_mag)
    buf = np.stack([wl, wr], axis=1) * gust[:, None] * 0.35
    # neve fina batendo: chiado claro e baixinho
    buf += stereo_bed(rng, n, lambda f: (f / 3000) ** 0.5 / (1 + (f / 9000) ** 3) / (1 + (1500 / f) ** 3)) * 0.05
    # cristais tilintando ao vento, em grupinhos
    for _ in range(26):
        start = rng.integers(n)
        f0 = rng.uniform(1400, 2600)
        pan = rng.uniform(-0.8, 0.8)
        for k in range(rng.integers(1, 5)):
            c = chime(rng, f0 * rng.choice([1.0, 1.122, 1.335, 1.498]), rng.uniform(0.6, 1.4))
            add_event(buf, start + int(k * rng.uniform(0.06, 0.18) * SR), c * rng.uniform(0.015, 0.045), pan)
    # gelo estalando longe: estalo grave e curto, raro
    for _ in range(4):
        L = int(0.25 * SR)
        cr = lowpass_fft(rng.standard_normal(L) * env_exp(L, 0.03), 700)
        add_event(buf, rng.integers(n), cr * 0.25, rng.uniform(-0.6, 0.6))
    buf = reverb(buf, rng, 2.2, 0.4, 4000)
    return finish(buf, -26.5)


# ------------------------------------------------------------------ vulcão
def lava(rng):
    n = SR * 24
    # ronco da terra: grave fundo que incha devagar
    rumble = stereo_bed(rng, n, lambda f: 1 / (1 + (f / 110) ** 3) / (1 + (25 / f) ** 4), 0.4)
    swell = 0.75 + 0.25 * periodic_lfo(n, 2) + 0.1 * periodic_lfo(n, 5, 2.0)
    buf = rumble * 0.6 * swell[:, None]
    # magma borbulhando: bolhas grossas e lentas, em grupos
    for _ in range(55):
        start = rng.integers(n)
        pan = rng.uniform(-0.7, 0.7)
        for k in range(rng.integers(2, 6)):
            b = bloop(rng, rng.uniform(70, 120), rng.uniform(180, 320), rng.uniform(0.07, 0.16))
            b = lowpass_fft(b, 900)
            add_event(buf, start + int(k * rng.uniform(0.07, 0.2) * SR), b * rng.uniform(0.12, 0.3), pan)
    # estouro da bolha: "plof" de ruído abafado
    for _ in range(40):
        L = int(0.12 * SR)
        p = lowpass_fft(rng.standard_normal(L) * env_exp(L, 0.025), 1400)
        add_event(buf, rng.integers(n), p * rng.uniform(0.12, 0.3), rng.uniform(-0.7, 0.7))
    # brasas estalando: cliques secos espalhados
    for _ in range(500):
        L = int(rng.uniform(0.001, 0.004) * SR)
        c = bandpass_burst(rng, L, 1200, 7000) * env_exp(L, L / SR / 3)
        add_event(buf, rng.integers(n), c * rng.pareto(2.5) * 0.06, rng.uniform(-0.9, 0.9))
    # vapor saindo das fendas: chiado que sobe e desce
    for _ in range(6):
        L = int(rng.uniform(1.0, 2.2) * SR)
        h = bandpass_burst(rng, L, 2500, 9000) * np.sin(np.pi * np.arange(L) / L) ** 2
        add_event(buf, rng.integers(n), h * rng.uniform(0.04, 0.08), rng.uniform(-0.8, 0.8))
    buf = reverb(buf, rng, 1.4, 0.3, 2000)
    return finish(buf, -23.5)


# ------------------------------------------------------------------ dungeon
def cave(rng):
    n = SR * 24
    # ar parado de caverna: zumbido grave e um sopro distante
    buf = stereo_bed(rng, n, lambda f: 1 / (1 + (f / 180) ** 3) / (1 + (35 / f) ** 3), 0.5) * 0.4
    air = moving_noise(rng, n, lambda f, ph: np.exp(-((f - (300 + 120 * np.sin(2 * np.pi * 2 * ph))) / 120) ** 2))
    buf += np.stack([air, np.roll(air, SR // 3)], axis=1) * 0.08
    # goteiras com eco
    for _ in range(34):
        L = int(0.06 * SR)
        t = np.arange(L) / SR
        f0 = rng.uniform(900, 2200)
        d = np.sin(2 * np.pi * np.cumsum(f0 * (1 + 0.6 * t / t[-1])) / SR) * env_exp(L, 0.012)
        add_event(buf, rng.integers(n), d * rng.uniform(0.08, 0.2), rng.uniform(-0.8, 0.8))
    # pedrinhas rolando longe, raras
    for _ in range(5):
        start = rng.integers(n)
        for k in range(rng.integers(3, 7)):
            L = int(0.02 * SR)
            s = lowpass_fft(rng.standard_normal(L) * env_exp(L, 0.004), 2500)
            add_event(buf, start + int(k * rng.uniform(0.04, 0.12) * SR), s * 0.12, rng.uniform(-0.5, 0.5))
    buf = reverb(buf, rng, 3.0, 0.7, 2500)
    return finish(buf, -26)


SOUNDS = {"rain": rain, "swamp": swamp, "ice": ice, "lava": lava, "cave": cave}

if __name__ == "__main__":
    names = sys.argv[1:] or list(SOUNDS)
    for i, name in enumerate(names):
        write_ogg(name, SOUNDS[name](np.random.default_rng(1000 + list(SOUNDS).index(name))))
