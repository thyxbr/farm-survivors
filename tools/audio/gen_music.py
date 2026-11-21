"""Compõe as músicas dos mapas do Pântano Sussurrante e do Vulcão das Cinzas e as toca com instrumentos gravados.

A partitura é escrita aqui (MIDI montado à mão) e tocada pelo FluidSynth com o banco de sons MuseScore General
(MIT; FluidR3 de Frank Wen e outros, ver assets/audio/CREDITS.md). Para o loop emendar sem corte, a peça é
tocada duas vezes seguidas e só a segunda passada é guardada: o começo dela já traz o eco e as notas longas
que vêm do fim. Volume final nivelado em -20 LUFS, como o resto da trilha.

Precisa de:
    FluidSynth  (FLUIDSYNTH ou C:/Tools/fluidsynth/.../bin/fluidsynth.exe)
    MuseScore_General.sf2  (SOUNDFONT ou C:/Tools/soundfonts/MuseScore_General.sf2)
    ffmpeg no PATH

Uso (na raiz do projeto):
    python tools/audio/gen_music.py            # as duas, em assets/audio/music/
    python tools/audio/gen_music.py swamp      # só uma
"""
import glob
import os
import re
import struct
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 44100
PPQ = 480
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "music")
FLUIDSYNTH = os.environ.get("FLUIDSYNTH") or next(iter(glob.glob("C:/Tools/fluidsynth/*/bin/fluidsynth.exe")), "fluidsynth")
SOUNDFONT = os.environ.get("SOUNDFONT", "C:/Tools/soundfonts/MuseScore_General.sf2")
NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}

# programas General MIDI (0 = Acoustic Grand Piano)
HARP, CELESTA, MARIMBA, BELLS = 46, 8, 12, 14
STRINGS, SLOW_STRINGS, PIZZ, CELLO, CONTRABASS, TREMOLO = 48, 49, 45, 42, 43, 44
CHOIR, OOHS = 52, 53
HORN, TROMBONE, TUBA, BRASS = 60, 57, 58, 61
FLUTE, OBOE, CLARINET, BASSOON, SHAKUHACHI, ALTO_FLUTE = 73, 68, 71, 70, 77, 73
TIMPANI, TAIKO = 47, 116
# bateria (canal 10)
KICK, LOW_TOM, FLOOR_TOM, CRASH, SPLASH = 35, 41, 43, 49, 55
SHAKER, CLAVES, WOOD_HI, WOOD_LO, GUIRO_S, GUIRO_L, VIBRASLAP, CABASA = 70, 75, 76, 77, 73, 74, 58, 69


def midi(name):
    m = re.fullmatch(r"([A-G])([#b]?)(-?\d)", name)
    return 12 * (int(m.group(3)) + 1) + NOTE[m.group(1)] + {"#": 1, "b": -1, "": 0}[m.group(2)]


def seq(text):
    """'r:1 A4:0.5 D5:0.5' -> [(início_em_tempos, duração, midi)] (r = pausa)."""
    out, t = [], 0.0
    for tok in text.split():
        name, dur = tok.split(":")
        if name != "r":
            out.append((t, float(dur), midi(name)))
        t += float(dur)
    return out


def chord(root, quality):
    iv = {"m": [0, 3, 7], "M": [0, 4, 7], "m7": [0, 3, 7, 10], "M7": [0, 4, 7, 11], "7": [0, 4, 7, 10],
          "sus4": [0, 5, 7], "7sus4": [0, 5, 7, 10], "6": [0, 4, 7, 9], "m9": [0, 3, 7, 14], "m6": [0, 3, 7, 9]}[quality]
    return [midi(root) + i for i in iv]


# ------------------------------------------------------------------ partitura -> arquivo MIDI
class Score:
    def __init__(self, bpm, beats, rng):
        self.bpm = bpm
        self.beats = beats
        self.rng = rng
        self.ev = []        # (tick, ordem, bytes)
        self.ch = {}

    def channel(self, name, program, vol=100, pan=64, reverb=60, chorus=0):
        ch = len(self.ch)
        if ch >= 9:
            ch += 1   # o canal 10 (índice 9) é da bateria
        self.ch[name] = ch
        for c, v in ((7, vol), (10, pan), (91, reverb), (93, chorus), (11, 127)):
            self.ev.append((0, 0, bytes([0xB0 | ch, c, v])))
        self.ev.append((0, 1, bytes([0xC0 | ch, program])))
        return ch

    def drums(self, vol=100, reverb=50):
        self.ch["drums"] = 9
        for c, v in ((7, vol), (91, reverb)):
            self.ev.append((0, 0, bytes([0xB9, c, v])))

    def tick(self, beat):
        return max(0, int(round(beat * PPQ)))

    def note(self, name, beat, dur, pitch, vel, human=0.012, legato=0.97):
        ch = self.ch[name]
        j = self.rng.normal(0, human) if human else 0.0
        vel = int(np.clip(vel + self.rng.integers(-5, 6), 1, 127))
        on = self.tick(beat + j)
        off = self.tick(beat + j + dur * legato)
        self.ev.append((on, 3, bytes([0x90 | ch, pitch, vel])))
        self.ev.append((max(off, on + 1), 2, bytes([0x80 | ch, pitch, 0])))

    def hit(self, beat, key, vel):
        self.note("drums", beat, 0.25, key, vel, human=0.006, legato=1.0)

    def expr(self, name, beat, dur, start, end, steps=16):
        """Crescendo/diminuendo (CC11) ao longo de `dur` tempos."""
        ch = self.ch[name]
        for i in range(steps + 1):
            v = int(start + (end - start) * i / steps)
            self.ev.append((self.tick(beat + dur * i / steps), 1, bytes([0xB0 | ch, 11, v])))

    def write(self, path, passes=2, tail_beats=8):
        """Toca a peça `passes` vezes seguidas e deixa `tail_beats` de silêncio para o eco acabar."""
        ev = []
        span = self.tick(self.beats)
        for p in range(passes):
            for t, o, b in self.ev:
                if p > 0 and t == 0 and b[0] & 0xF0 in (0xC0,):
                    continue
                ev.append((t + p * span, o, b))
        ev.sort(key=lambda e: (e[0], e[1]))
        tempo = int(60_000_000 / self.bpm)
        data = bytearray(b"\x00\xFF\x51\x03" + tempo.to_bytes(3, "big"))
        last = 0
        for t, _, b in ev:
            data += vlq(t - last) + b
            last = t
        data += vlq(span * passes + self.tick(tail_beats) - last) + b"\xFF\x2F\x00"
        with open(path, "wb") as f:
            f.write(b"MThd" + struct.pack(">IHHH", 6, 0, 1, PPQ))
            f.write(b"MTrk" + struct.pack(">I", len(data)) + data)
        return self.beats * 60.0 / self.bpm


def vlq(n):
    out = [n & 0x7F]
    n >>= 7
    while n:
        out.append((n & 0x7F) | 0x80)
        n >>= 7
    return bytes(reversed(out))


# ------------------------------------------------------------------ Pântano Sussurrante
def swamp(rng):
    """Ré menor, 68 BPM, 32 compassos (~113 s). Névoa de cordas, harpa, madeiras graves e o coaxar do guiro.
    A: cordas e harpa; A': clarinete; B: oboé com as cordas abrindo; B': flauta e trompa, mais cheio."""
    A = [("D2", "m"), ("D2", "m"), ("Bb1", "M7"), ("Bb1", "M7"), ("G1", "m"), ("G1", "m6"), ("A1", "sus4"), ("A1", "7")]
    B = [("Bb1", "M7"), ("C2", "6"), ("A1", "m7"), ("D2", "m"), ("G1", "m7"), ("C2", "M"), ("A1", "sus4"), ("A1", "7")]
    form = A + A + B + B
    s = Score(68, len(form) * 4, rng)
    s.channel("bass", CONTRABASS, 92, 58, 50)
    s.channel("cello", CELLO, 84, 50, 60)
    s.channel("strings", SLOW_STRINGS, 78, 70, 85, 20)
    s.channel("harp", HARP, 88, 40, 75)
    s.channel("celesta", CELESTA, 60, 95, 110)
    s.channel("clarinet", CLARINET, 98, 74, 70)
    s.channel("oboe", OBOE, 92, 80, 75)
    s.channel("flute", FLUTE, 86, 84, 85)
    s.channel("horn", HORN, 74, 52, 90)
    s.channel("timp", TIMPANI, 84, 64, 70)
    s.drums(78, 60)

    for bar, (root, q) in enumerate(form):
        b0 = bar * 4
        tones = chord(root, q)
        sec = bar // 8
        r = tones[0]
        # contrabaixo e violoncelo: nota longa que cresce e some, como a névoa
        s.note("bass", b0, 4, r, 70)
        s.expr("bass", b0, 4, 70, 110 if bar % 2 == 0 else 85)
        s.note("cello", b0, 2, r + 12, 62)
        s.note("cello", b0 + 2, 2, tones[2] + 12 if bar % 2 else r + 12, 58)
        # cordas: acorde aberto (fundamental, quinta, terça em cima), mais presentes no B
        if bar % 2 == 0:
            voicing = [r + 24, tones[2] + 24, tones[1] + 36] + ([tones[3] + 24] if len(tones) > 3 else [])
            for p in voicing:
                s.note("strings", b0, 8, p, 58 if sec < 2 else 70, legato=1.0)
            s.expr("strings", b0, 4, 55, 112)
            s.expr("strings", b0 + 4, 4, 112, 70)
        # harpa: arpejo subindo e descendo em colcheias
        arp = [0, 7, 12, 15 if q.startswith("m") else 16, 19, 15 if q.startswith("m") else 16, 12, 7]
        for i, iv in enumerate(arp):
            s.note("harp", b0 + i * 0.5, 1.5, r + 24 + iv, 62 if i % 4 == 0 else 48)
        # tímpano bem baixinho no começo de cada par de compassos
        if bar % 2 == 0:
            s.note("timp", b0, 1, r + 12, 50 if sec < 3 else 66)
        # percussão do brejo: guiro (sapo), claves de madeira, chocalho discreto no B
        if bar % 2 == 1:
            s.hit(b0 + 2.5, GUIRO_L, 64)
            s.hit(b0 + 3.5, GUIRO_S, 50)
        if bar % 4 == 3:
            s.hit(b0 + 3.0, VIBRASLAP, 40)
        s.hit(b0 + 1.5, WOOD_LO, 36)
        if sec >= 2:
            for i in range(8):
                s.hit(b0 + i * 0.5, SHAKER, 30 if i % 2 else 42)
        # fogo-fátuo: notas soltas de celesta no começo calmo
        if sec == 0 and bar % 2 == 1:
            for k in range(3):
                s.note("celesta", b0 + 0.5 + k * 1.0 + rng.uniform(0, 0.3), 1.5, r + 48 + int(rng.choice([0, 3, 7, 10, 14])), 52)

    mel_a = seq("r:1 A3:0.5 D4:0.5 E4:1 F4:1   E4:1.5 D4:0.5 A3:2   r:0.5 F4:0.5 G4:1 A4:1.5 G4:0.5   F4:1 D4:3 "
                "r:1 Bb3:0.5 D4:0.5 G4:1.5 F4:0.5   E4:1 D4:1 Bb3:2   D4:1.5 E4:0.5 D4:1 A3:1   C#4:3 r:1")
    mel_b = seq("D5:1 F5:1 A5:2   G5:1.5 E5:0.5 C5:2   r:0.5 E5:0.5 G5:1 A5:1 G5:1   F5:2 E5:1 D5:1 "
                "G5:1.5 F5:0.5 D5:1 Bb4:1   C5:1 E5:1 G5:1 E5:1   D5:2 F5:1 E5:1   E5:1 C#5:1 A4:2")
    for t, d, m in mel_a:
        s.note("clarinet", 32 + t, d, m, 84, legato=1.0)
    s.expr("clarinet", 32, 32, 100, 120)
    for t, d, m in mel_b:
        s.note("oboe", 64 + t, d, m - 12, 80, legato=1.0)
        s.note("flute", 96 + t, d, m, 78, legato=1.0)
        s.note("horn", 96 + t, d, m - 24, 60, legato=1.0)
    return s


# ------------------------------------------------------------------ Vulcão das Cinzas
def volcano(rng):
    """Mi frígio / menor harmônico, 96 BPM, 32 compassos (80 s). Taikos e tímpanos, cordas graves em ostinato,
    trompas com o tema, coro e metais no fim. A: tambores e cordas; A': trompas; B: coro; B': tudo junto."""
    A = [("E2", "m"), ("E2", "m"), ("F2", "M"), ("E2", "m"), ("A1", "m"), ("C2", "M"), ("D2", "M"), ("B1", "M")]
    B = [("C2", "M"), ("D2", "M"), ("E2", "m"), ("E2", "m"), ("A1", "m"), ("F2", "M"), ("B1", "M"), ("B1", "7")]
    form = A + A + B + B
    s = Score(96, len(form) * 4, rng)
    s.channel("bass", CONTRABASS, 100, 60, 40)
    s.channel("celli", STRINGS, 96, 48, 50)
    s.channel("violas", STRINGS, 80, 82, 55)
    s.channel("horn", HORN, 104, 56, 75)
    s.channel("trombone", TROMBONE, 88, 74, 60)
    s.channel("tuba", TUBA, 80, 64, 50)
    s.channel("choir", CHOIR, 92, 64, 95)
    s.channel("timp", TIMPANI, 104, 60, 55)
    s.channel("taiko", TAIKO, 112, 70, 50)
    s.channel("bells", BELLS, 66, 90, 90)
    s.drums(92, 45)

    for bar, (root, q) in enumerate(form):
        b0 = bar * 4
        tones = chord(root, q)
        r = tones[0]
        sec = bar // 8
        third = tones[1] - r
        # ostinato em colcheias nas cordas graves (acentos no 1, no "e" do 2 e no 4)
        pat = [0, 0, 12, 0, 7, 0, 12, third + 12]
        for i, iv in enumerate(pat):
            acc = 100 if i in (0, 3, 6) else 72
            s.note("celli", b0 + i * 0.5, 0.5, r + 12 + iv, acc, legato=0.55)
            if sec >= 1:
                s.note("violas", b0 + i * 0.5, 0.5, r + 24 + iv, acc - 12, legato=0.5)
        s.note("bass", b0, 2, r, 92, legato=0.9)
        s.note("bass", b0 + 2, 2, r, 80, legato=0.9)
        # taikos e tímpano: BUM . . bum BUM . bum .
        for beat, v in ((0, 118), (1.5, 82), (2, 108), (3, 86)):
            s.note("taiko", b0 + beat, 1, 48 if beat in (0, 2) else 55, v, human=0.004)
        s.note("timp", b0, 1, r + 12, 96)
        if bar % 4 == 3:   # rufar no fim da frase
            for i in range(8):
                s.note("timp", b0 + 2 + i * 0.25, 0.25, r + 12, 60 + i * 7, human=0.003)
            s.hit(b0 + 3.5, FLOOR_TOM, 100)
        s.hit(b0, KICK, 96)
        s.hit(b0 + 2, KICK, 84)
        if sec >= 1:
            for i in range(4):
                s.hit(b0 + i + 0.5, LOW_TOM, 54)
        if bar % 8 == 0:
            s.hit(b0, CRASH, 74 if bar else 50)
            s.note("bells", b0, 3, midi("E4"), 72)
        # metais em acordes curtos e coro sustentando o acorde nas seções B
        if sec >= 2:
            for beat in (0, 2.5):
                for p in tones:
                    s.note("trombone", b0 + beat, 0.75, p + 12, 92, legato=0.8)
                s.note("tuba", b0 + beat, 0.75, r, 90, legato=0.8)
            for p in [r + 24, tones[1] + 24, tones[2] + 24]:
                s.note("choir", b0, 4, p, 76, legato=1.0)
            s.expr("choir", b0, 4, 80, 120)

    horn = seq("E4:1.5 F4:0.5 G4:1 E4:1   B4:3 A4:0.5 G4:0.5   A4:1.5 G4:0.5 F4:1 A4:1   G4:1 F4:1 E4:2 "
               "C5:1.5 B4:0.5 A4:1 E4:1   G4:1.5 A4:0.5 G4:1 E4:1   F#4:1 A4:1 D5:2   B4:1.5 A4:0.5 F#4:1 D#4:1")
    high = seq("E5:2 G5:2   F#5:2 A5:1 F#5:1   G5:3 F#5:0.5 E5:0.5   B4:4 "
               "C5:2 E5:2   F5:2 A5:1 G5:0.5 F5:0.5   D#5:2 F#5:2   B4:3 r:1")
    for t, d, m in horn:
        s.note("horn", 32 + t, d, m - 12, 96, legato=0.95)
    for t, d, m in high:
        s.note("horn", 96 + t, d, m - 12, 104, legato=0.95)
        s.note("choir", 64 + t, d, m, 88, legato=1.0)
    return s


# ------------------------------------------------------------------ áudio
def render(score, name):
    tmp = tempfile.mkdtemp()
    mid = os.path.join(tmp, name + ".mid")
    wav = os.path.join(tmp, name + "_raw.wav")
    seconds = score.write(mid)
    subprocess.run([FLUIDSYNTH, "-ni", "-q", "-F", wav, "-r", str(SR), "-g", "0.6", "-R", "1", "-C", "1",
                    "-o", "synth.reverb.room-size=0.82", "-o", "synth.reverb.damp=0.35",
                    "-o", "synth.reverb.width=1.0", "-o", "synth.reverb.level=0.75",
                    "-o", "synth.chorus.level=1.2", SOUNDFONT, mid], check=True, capture_output=True)
    with wave.open(wav) as w:
        ch = w.getnchannels()
        raw = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64) / 32768
    x = raw.reshape(-1, ch)
    n = int(round(seconds * SR))
    # segunda passada: o começo dela já traz o eco e as notas longas da primeira, igual a cada volta do loop
    return x[n:2 * n].copy()


def master(buf):
    buf = buf - buf.mean(axis=0)
    n = buf.shape[0]
    f = np.fft.rfftfreq(n, 1.0 / SR)
    shelf = 1 / np.sqrt(1 + (f / 8000) ** 2) / (1 + (30 / np.maximum(f, 1)) ** 4)
    for c in range(2):
        buf[:, c] = np.fft.irfft(np.fft.rfft(buf[:, c]) * shelf, n)
    return buf / (np.max(np.abs(buf)) + 1e-12) * 0.9


def loudness(path):
    r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-af", "ebur128", "-f", "null", "-"],
                       capture_output=True, text=True)
    return float(re.findall(r"I:\s+(-?[\d.]+) LUFS", r.stderr)[-1])


def write(name, buf, target=-20.0):
    os.makedirs(OUT, exist_ok=True)
    tmp = os.path.join(tempfile.gettempdir(), name + "_mus.wav")
    with wave.open(tmp, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(buf, -1, 1) * 32000).astype("<i2").tobytes())
    gain = target - loudness(tmp)
    dst = os.path.abspath(os.path.join(OUT, name + ".ogg"))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-af",
                    "volume=%.2fdB,alimiter=limit=0.89:level=false" % gain, "-c:a", "libvorbis", "-q:a", "6", dst],
                   check=True)
    os.remove(tmp)
    print("ok", dst, "%.1f s" % (buf.shape[0] / SR), "%.1f LUFS" % loudness(dst))


TRACKS = {"swamp_whispering_marsh": (swamp, 41), "volcano_ash_crown": (volcano, 66)}
ALIASES = {"swamp": "swamp_whispering_marsh", "volcano": "volcano_ash_crown"}

if __name__ == "__main__":
    for name in [ALIASES.get(a, a) for a in sys.argv[1:]] or list(TRACKS):
        fn, seed = TRACKS[name]
        write(name, master(render(fn(np.random.default_rng(seed)), name)))
