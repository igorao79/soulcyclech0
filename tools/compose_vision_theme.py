"""Тема видения — сцены с двойником и книгой «Цикл душ», собранная из кода.

До-диез минор, без такта: 56 ударов в минуту, но слышно его только по редким нотам.
Низкий гул органа держит тонику, над ним медленно меняются аккорды хора, сверху,
как падающие звёзды, редко звенят ноты челесты (короткий мотив из пяти нот, каждый
раз чуть иначе), и всё тонет в огромном зале. Ни мелодии, ни ритма — только пространство.

Петля целиком (16 тактов по 4 доли); оба прохода играются одинаково до сэмпла, в файл
идёт второй — в нём уже есть хвосты реверберации с конца первого, поэтому стык не слышен.

Запуск: python3 tools/compose_vision_theme.py → assets/music/vision_theme.ogg
(нужны numpy и ffmpeg). Тембры и зал — из compose_menu_theme.py и compose_winter_theme.py.
"""
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import compose_menu_theme as base  # noqa: E402
import compose_winter_theme as winter  # noqa: E402

RATE = base.RATE
BPM = 56.0
BEAT = 60.0 / BPM
BAR = BEAT * 4
LOOP_BARS = 16
freq = base.freq


def organ(f, length):
    """Гул органа: тон и октава, очень медленная атака, дыхание мехов."""
    n = int((length + 2.5) * RATE)
    t = np.arange(n) / RATE
    tone = np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * f * 2 * t) + 0.18 * np.sin(2 * np.pi * f * 3.001 * t)
    tone *= 1 + 0.06 * np.sin(2 * np.pi * 0.11 * t)
    return tone * base.envelope(n, 2.5, 2.5) * 0.07


def shimmer(f, length):
    """Мерцание сверху: два почти совпадающих тона дают медленные биения."""
    n = int((length + 3.0) * RATE)
    t = np.arange(n) / RATE
    tone = np.sin(2 * np.pi * f * t) + np.sin(2 * np.pi * f * 1.003 * t + 1.0)
    return tone * base.envelope(n, 3.0, 3.0) * 0.012


# Аккорды хора по два такта: тоника, VI, iv, V, тоника, VI, II (неаполитанский), V.
CHORDS = [
    ["C#4", "E4", "G#4"], ["A3", "C#4", "E4"], ["F#3", "A3", "C#4"], ["G#3", "B#3", "D#4"],
    ["C#4", "E4", "G#4"], ["A3", "C#4", "E4"], ["D3", "F#3", "A3"], ["G#3", "B#3", "D#4"],
]
# Мотив челесты: падает, как звезда, и замирает.
MOTIF = ["G#6", "E6", "C#6", "D#6", "B5"]


def fix(name):
    # «B#3» в таблице нот нет: это до следующей октавы.
    if name.startswith("B#"):
        return "C" + str(int(name[-1]) + 1)
    return name


def compose_pass(track, start_bar):
    base.rng = np.random.default_rng(77)
    gen = np.random.default_rng(5)
    for i, chord in enumerate(CHORDS):
        at = (start_bar + i * 2) * BAR
        for note in chord:
            track.add(winter.choir(freq(fix(note)), BAR * 2), at, 1.1, gen.uniform(-0.6, 0.6))
        track.add(shimmer(freq(fix(chord[-1])) * 4, BAR * 2), at, 1.0, gen.uniform(-0.8, 0.8))
    # Гул тоники всю петлю, подменяемый по два такта, чтобы не было швов.
    for b in range(0, LOOP_BARS, 2):
        track.add(organ(freq("C#2"), BAR * 2), (start_bar + b) * BAR, 1.0, 0.0)
    # Звёзды: мотив звучит трижды за петлю, каждый раз чуть иначе по времени и громкости.
    for k, bar in enumerate((1, 6, 11)):
        at = (start_bar + bar) * BAR + BEAT * 0.5
        for j, note in enumerate(MOTIF):
            if k == 1 and j == 3:
                continue
            shift = gen.uniform(-0.12, 0.12)
            track.add(winter.celesta(freq(note), BEAT), at + j * BEAT * 1.25 + shift,
                      0.7 * gen.uniform(0.7, 1.0), gen.uniform(-0.7, 0.7))
    # Одинокий колокол где-то далеко в середине петли.
    track.add(winter.bell(freq("C#6")), (start_bar + 8) * BAR, 0.8, -0.3)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_path = os.path.join(root, "assets", "music", "vision_theme.ogg")
    track = base.Track(LOOP_BARS * BAR * 2)
    compose_pass(track, 0)
    compose_pass(track, LOOP_BARS)
    wet_l = base.reverb(track.left, seconds=6.0, seed=7)
    wet_r = base.reverb(track.right, seconds=6.0, seed=8)
    left = track.left * 0.5 + wet_l * 0.75
    right = track.right * 0.5 + wet_r * 0.75
    peak = max(np.max(np.abs(left)), np.max(np.abs(right)))
    left, right = np.tanh(left / peak), np.tanh(right / peak)
    peak = max(np.max(np.abs(left)), np.max(np.abs(right)))
    left, right = left / peak * 0.8, right / peak * 0.8
    loop_len = int(round(LOOP_BARS * BAR * RATE))
    left, right = left[loop_len:loop_len * 2], right[loop_len:loop_len * 2]
    pcm = (np.stack([left, right], axis=1) * 32767).astype(np.int16)
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = os.path.join(tmp, "theme.wav")
        with wave.open(wav_path, "wb") as wav:
            wav.setnchannels(2)
            wav.setsampwidth(2)
            wav.setframerate(RATE)
            wav.writeframes(pcm.tobytes())
        subprocess.run(
            ["ffmpeg", "-v", "error", "-y", "-i", wav_path, "-c:a", "libvorbis", "-q:a", "6", out_path],
            check=True,
        )
    print("%s: %.1f s, loops whole" % (out_path, len(left) / RATE))


if __name__ == "__main__":
    main()
