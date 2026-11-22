"""Compõe a fanfarra curta da subida de nível (assets/audio/sfx/level_up_fanfare.wav).

Usa a partitura e o FluidSynth de gen_music.py (mesmo banco de sons). Peça de um tiro só, sem loop:
harpa sobe num glissando com celesta e rufar de tímpano, trompetes respondem em tercina (Dó-Mi-Sol),
cadência heroica Láb -> Sib -> Dó e o acorde final segura com coro, cordas e sinos brilhando por cima.

Uso (na raiz do projeto):
    python tools/audio/gen_levelup.py
"""
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from gen_music import (  # noqa: E402
    BELLS, BRASS, CELESTA, CHOIR, HARP, HORN, SR, STRINGS, TIMPANI, TREMOLO, FLUIDSYNTH, SOUNDFONT, CRASH,
    Score, loudness, midi,
)

TRUMPET = 56
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "sfx", "level_up_fanfare.wav")
BPM = 132


def fanfare(rng):
    s = Score(BPM, 10, rng)
    s.channel("harp", HARP, 100, 50, 70)
    s.channel("celesta", CELESTA, 84, 84, 80)
    s.channel("trumpet", TRUMPET, 108, 60, 60)
    s.channel("brass", BRASS, 92, 70, 60)
    s.channel("horn", HORN, 96, 52, 70)
    s.channel("strings", STRINGS, 88, 64, 75)
    s.channel("trem", TREMOLO, 70, 64, 75)
    s.channel("choir", CHOIR, 86, 64, 100)
    s.channel("bells", BELLS, 78, 90, 95)
    s.channel("timp", TIMPANI, 100, 60, 55)
    s.drums(90, 70)

    # 0-1: glissando de harpa (Dó maior) subindo duas oitavas, celesta dobrando a ponta; tímpano rufando
    gl = ["C4", "E4", "G4", "C5", "E5", "G5", "C6", "E6"]
    for i, n in enumerate(gl):
        s.note("harp", i * 0.125, 1.2, midi(n), 70 + i * 5, human=0.004)
        if i >= 4:
            s.note("celesta", i * 0.125, 0.8, midi(n) + 12, 60 + i * 4, human=0.004)
    for i in range(12):
        s.note("timp", i / 12, 0.1, midi("G2"), 40 + i * 4, human=0.0, legato=1.0)

    # 1-2: tercina de trompete
    for i, n in enumerate(["C5", "E5", "G5"]):
        s.note("trumpet", 1 + i / 3, 0.3, midi(n), 100 + i * 6, human=0.003, legato=0.85)
    # 2: Láb maior, 2.75: Sib maior (cadência heroica bVI - bVII - I)
    for beat, root, top in ((2.0, "Ab", "Eb5"), (2.75, "Bb", "F5")):
        tri = [midi(root + "3") + i for i in (0, 4, 7)]
        for p in tri:
            s.note("brass", beat, 0.7, p + 12, 100, human=0.003, legato=0.9)
            s.note("horn", beat, 0.7, p, 92, human=0.003, legato=0.9)
        s.note("trumpet", beat, 0.7, midi(top), 112, human=0.003, legato=0.9)
        s.note("strings", beat, 0.7, tri[0] - 12, 90, human=0.003)
        s.note("timp", beat, 0.3, tri[0] - 12, 100, human=0.0)

    # 3.5: Dó maior final, segurado
    end = 3.5
    hold = 4.5
    s.note("trumpet", end, hold, midi("C6"), 118, human=0.0, legato=1.0)
    s.note("trumpet", end, hold, midi("G5"), 104, human=0.0, legato=1.0)
    for p in ("C4", "E4", "G4", "C5"):
        s.note("brass", end, hold, midi(p), 108, human=0.0)
        s.note("horn", end, hold, midi(p) - 12, 96, human=0.0)
    for p in ("C3", "G3", "E4", "G4", "C5"):
        s.note("strings", end, hold, midi(p), 96, human=0.0)
        s.note("trem", end, hold, midi(p) + 12, 70, human=0.0)
    for p in ("C4", "E4", "G4", "C5"):
        s.note("choir", end, hold + 1, midi(p), 92, human=0.0)
    s.expr("brass", end + 1.5, 3.0, 127, 50)
    s.expr("trumpet", end + 1.5, 3.0, 127, 40)
    s.note("timp", end, 0.5, midi("C2"), 120, human=0.0)
    s.note("timp", end, 0.5, midi("C3"), 100, human=0.0)
    s.hit(end, CRASH, 110)
    # sinos e celesta brilhando sobre o acorde
    sparkle = ["C6", "E6", "G6", "C7", "G6", "E6", "G6", "C7"]
    for i, n in enumerate(sparkle):
        s.note("bells", end + 0.25 + i * 0.25, 1.5, midi(n), 76 - i * 3, human=0.004)
        s.note("celesta", end + 0.375 + i * 0.25, 1.0, midi(n), 66 - i * 3, human=0.004)
    return s


def main():
    s = fanfare(np.random.default_rng(7))
    tmp = tempfile.mkdtemp()
    mid = os.path.join(tmp, "lu.mid")
    raw = os.path.join(tmp, "lu_raw.wav")
    s.write(mid, passes=1, tail_beats=6)
    subprocess.run([FLUIDSYNTH, "-ni", "-q", "-F", raw, "-r", str(SR), "-g", "0.6", "-R", "1", "-C", "1",
                    "-o", "synth.reverb.room-size=0.8", "-o", "synth.reverb.damp=0.3",
                    "-o", "synth.reverb.width=1.0", "-o", "synth.reverb.level=0.7",
                    SOUNDFONT, mid], check=True, capture_output=True)
    with wave.open(raw) as w:
        x = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64).reshape(-1, w.getnchannels()) / 32768
    # corta o silêncio do fim, com um fade curto
    lvl = np.abs(x).max(axis=1)
    last = min(np.nonzero(lvl > 0.004)[0][-1], int(6.0 * SR))   # no máximo 6 s: o eco não fica arrastando
    x = x[: last + 1]
    fade = min(int(1.2 * SR), x.shape[0])
    x[-fade:] *= np.linspace(1, 0, fade)[:, None] ** 2
    x = x / (np.abs(x).max() + 1e-12) * 0.9
    mid_wav = os.path.join(tmp, "lu_mid.wav")
    with wave.open(mid_wav, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32000).astype("<i2").tobytes())
    gain = -14.0 - loudness(mid_wav)   # efeito de destaque: mais alto que a trilha (-20 LUFS)
    dst = os.path.abspath(OUT)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", mid_wav, "-af",
                    "volume=%.2fdB,alimiter=limit=0.89:level=false" % gain, "-c:a", "pcm_s16le", dst], check=True)
    print("ok", dst, "%.1f s" % (x.shape[0] / SR), "%.1f LUFS" % loudness(dst))


if __name__ == "__main__":
    main()
