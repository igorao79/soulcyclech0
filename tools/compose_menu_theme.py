"""Тема главного экрана «Цикл душ», собранная из кода.

Ре минор, 84 удара в минуту. Тихая мелодичная тема в духе музыки к Undertale и Deltarune:
простая запоминающаяся мелодия, «игрушечные» тембры и мягкая ретро-окраска.

  Вступление (4 такта) — музыкальная шкатулка перебирает аккорды над тихими струнными.
  A  (8 тактов)  — главная тема у мягкой флейты над шкатулкой, тянущимся басом и струнными.
  A2 (8 тактов)  — та же тема, шкатулка отвечает ей подголоском.
  B  (8 тактов)  — светлая середина: мягкий квадратный лид на октаву выше.
  A3 (8 тактов)  — кульминация: тема у флейты и лида вместе, струнные шире.
  R  (4 такта)   — передышка: снова вступление, шкатулка и струнные без мелодии.

Всё плавное, как вступление: ни ударных, ни отрывистого баса, ни звонких ударных нот —
мелодию ведёт тянущийся голос без удара в начале, аккорды тихо перебирает шкатулка.

Петля — с начала A до конца R. Перед темой всегда звучит одно и то же (вступление или R,
сыгранные одинаково до сэмпла), поэтому хвосты нот и реверберации в начале темы одинаковы
и после вступления, и после круга петли: ни на 11-й секунде, ни на стыке петли нет скачка.
В Godot петля начинается с LOOP_START секунд.

Запуск: python3 tools/compose_menu_theme.py  → assets/music/menu_theme.ogg (нужны numpy и ffmpeg).
"""
import os
import subprocess
import tempfile
import wave

import numpy as np

RATE = 44100
BPM = 84.0
BEAT = 60.0 / BPM
BAR = BEAT * 4
INTRO_BARS = 4
LOOP_BARS = 36
LOOP_START = INTRO_BARS * BAR
rng = np.random.default_rng(1993)

NOTE_INDEX = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6,
              "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def freq(name):
    """«A4», «C#5», «Bb3» → частота в герцах."""
    pitch, octave = name[:-1], int(name[-1])
    midi = 12 * (octave + 1) + NOTE_INDEX[pitch]
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


# --- Тембры -----------------------------------------------------------------

def envelope(n, attack, release, sustain_level=1.0, decay=0.0):
    t = np.arange(n) / RATE
    env = np.minimum(t / max(attack, 1e-4), 1.0)
    if decay > 0:
        env *= sustain_level + (1 - sustain_level) * np.exp(-np.maximum(t - attack, 0) / decay)
    tail = int(release * RATE)
    if tail > 0 and n > tail:
        env[-tail:] *= np.linspace(1.0, 0.0, tail) ** 2
    return env


def flute(f, length):
    """Мягкий тянущийся голос мелодии: тёплый тон с дыханием и вибрато, без удара в начале.
    Нота плавно входит и плавно уходит, поэтому соседние ноты переливаются одна в другую."""
    n = int((length + 0.45) * RATE)
    t = np.arange(n) / RATE
    vibrato = 1 + 0.004 * np.sin(2 * np.pi * 4.8 * t + rng.uniform(0, 6.28)) * np.clip((t - 0.2) / 0.4, 0, 1)
    phase = 2 * np.pi * f * np.cumsum(vibrato) / RATE
    tone = np.sin(phase) + 0.22 * np.sin(2 * phase) + 0.07 * np.sin(3 * phase)
    breath = rng.standard_normal(n)
    breath = np.convolve(breath, np.ones(24) / 24, mode="same") * 0.05
    held = length
    env = np.clip(t / 0.14, 0, 1) ** 1.5
    env *= np.where(t < held, 1.0, np.exp(-(t - held) / 0.16))
    env *= 0.92 + 0.08 * np.exp(-t / 0.5)
    return (tone + breath) * env * 0.16


def music_box(f, length):
    """Шкатулка: язычок звенит чистым тоном с негармоническим призвуком и гаснет."""
    n = int((length + 1.8) * RATE)
    t = np.arange(n) / RATE
    tone = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * f * 3.98 * t) * np.exp(-t / 0.18)
    tone += 0.12 * np.sin(2 * np.pi * f * 2.0 * t)
    return tone * np.exp(-t / 0.9) * np.minimum(t / 0.002, 1.0) * 0.13


def pulse_lead(f, length, duty=0.5):
    """Мягкий квадратный лид 8-битной приставки: мало обертонов, плавная атака, вибрато."""
    n = int((length + 0.25) * RATE)
    t = np.arange(n) / RATE
    vibrato = 1 + 0.006 * np.sin(2 * np.pi * 5.2 * t) * np.clip((t - 0.25) / 0.3, 0, 1)
    phase = 2 * np.pi * f * np.cumsum(vibrato) / RATE
    out = np.zeros(n)
    for k in range(1, 10):
        if f * k > RATE * 0.42:
            break
        out += (2 / (np.pi * k)) * np.sin(np.pi * k * duty) * np.cos(k * phase) / (1 + 0.15 * k)
    env = envelope(n, 0.07, 0.25, sustain_level=0.8, decay=0.6)
    return out * env * 0.075


def warm_bass(f, length):
    """Тянущийся бас: чистый тон с лёгкой второй гармоникой, мягко входит и мягко уходит."""
    n = int((length + 0.8) * RATE)
    t = np.arange(n) / RATE
    tone = np.sin(2 * np.pi * f * t) + 0.18 * np.sin(2 * np.pi * 2 * f * t)
    return tone * envelope(n, 0.35, 0.8) * 0.16


def strings(f, length):
    """Струнные: три расстроенные пилы с завалом верхов, медленная атака, лёгкое тремоло."""
    n = int((length + 0.9) * RATE)
    t = np.arange(n) / RATE
    out = np.zeros(n)
    for detune in (-0.0045, 0.0, 0.0052):
        fd = f * (1 + detune)
        for k in range(1, 14):
            if fd * k > 6000:
                break
            out += np.sin(2 * np.pi * fd * k * t + rng.uniform(0, 6.28)) / (k ** 1.45)
    tremolo = 1 + 0.05 * np.sin(2 * np.pi * 4.6 * t)
    return out * tremolo * envelope(n, 0.45, 0.8) * 0.035


# --- Партитура ---------------------------------------------------------------
# Ноты — (высота, длительность в долях). «-» — пауза.

THEME = [
    [("A4", 1), ("D5", 1), ("E5", 1), ("F5", 1)],
    [("E5", 3), ("D5", 1)],
    [("C5", 1), ("A4", 1), ("C5", 1), ("F5", 1)],
    [("E5", 4)],
    [("D5", 1), ("Bb4", 1), ("D5", 1), ("G5", 1)],
    [("F5", 2), ("E5", 1), ("D5", 1)],
    [("C#5", 1), ("E5", 1), ("A5", 2)],
    [("D5", 4)],
]
THEME_CHORDS = [
    ("D", ["D3", "A3", "D4", "F4"]), ("Bb", ["Bb2", "F3", "Bb3", "D4"]),
    ("F", ["F2", "C3", "F3", "A3"]), ("C", ["C3", "G3", "C4", "E4"]),
    ("Gm", ["G2", "D3", "G3", "Bb3"]), ("Dm", ["D3", "A3", "D4", "F4"]),
    ("A", ["A2", "E3", "A3", "C#4"]), ("Dm", ["D3", "A3", "D4", "F4"]),
]
BRIDGE = [
    [("F5", 1), ("A5", 1), ("Bb5", 2)],
    [("C6", 1), ("Bb5", 1), ("A5", 2)],
    [("A5", 1), ("G5", 1), ("E5", 1), ("C5", 1)],
    [("D5", 3), ("F5", 1)],
    [("G5", 1), ("Bb5", 1), ("D6", 2)],
    [("C#6", 1), ("Bb5", 1), ("A5", 1), ("G5", 1)],
    [("F5", 1), ("E5", 1), ("D5", 1), ("E5", 1)],
    [("E5", 2), ("C#5", 2)],
]
BRIDGE_CHORDS = [
    ("Bb", ["Bb2", "F3", "Bb3", "D4"]), ("C", ["C3", "G3", "C4", "E4"]),
    ("Am", ["A2", "E3", "A3", "C4"]), ("Dm", ["D3", "A3", "D4", "F4"]),
    ("Gm", ["G2", "D3", "G3", "Bb3"]), ("A", ["A2", "E3", "A3", "C#4"]),
    ("Dm", ["D3", "A3", "D4", "F4"]), ("A", ["A2", "E3", "A3", "C#4"]),
]
# Подголосок шкатулки во второй теме: отвечает мелодии в паузах между фразами.
COUNTER = [
    [("-", 2), ("A5", 1), ("D6", 1)],
    [("-", 2), ("F5", 1), ("D5", 1)],
    [("-", 2), ("A5", 1), ("C6", 1)],
    [("G5", 1), ("E5", 1), ("C5", 1), ("E5", 1)],
    [("-", 2), ("Bb5", 1), ("G5", 1)],
    [("-", 2), ("A5", 1), ("F5", 1)],
    [("E5", 1), ("G5", 1), ("C#6", 1), ("E6", 1)],
    [("D6", 2), ("A5", 2)],
]


class Track:
    def __init__(self, seconds):
        self.left = np.zeros(int(seconds * RATE) + RATE * 4)
        self.right = np.zeros_like(self.left)

    def add(self, signal, at, gain=1.0, pan=0.0):
        start = int(at * RATE)
        end = min(start + len(signal), len(self.left))
        part = signal[: end - start] * gain
        self.left[start:end] += part * np.sqrt(0.5 * (1 - pan))
        self.right[start:end] += part * np.sqrt(0.5 * (1 + pan))


def place_melody(track, bars, start_bar, voice, octave_shift=0, gain=1.0, pan=0.0, swing=0.0):
    for b, bar in enumerate(bars):
        at = (start_bar + b) * BAR
        for note, beats in bar:
            if note != "-":
                f = freq(note) * (2.0 ** octave_shift)
                humanize = rng.uniform(-0.008, 0.008) + swing
                track.add(voice(f, beats * BEAT * 0.95), at + humanize, gain * rng.uniform(0.92, 1.0), pan)
            at += beats * BEAT


# figure — громкость шкатулки: под мелодией тише, в одиночку громче.
# ramp_from — с какой громкости шкатулка плавно сходит к figure за первые два такта.
def place_harmony(track, chords, start_bar, figure, gain=1.0, ramp_from=None):
    for b, (_, tones) in enumerate(chords):
        at = (start_bar + b) * BAR
        box = figure if ramp_from is None else ramp_from + (figure - ramp_from) * min((b + 0.5) / 2.0, 1.0)
        root = freq(tones[0])
        track.add(warm_bass(root, BAR), at, 0.9 * gain, -0.05)
        for tone in tones[1:]:
            track.add(strings(freq(tone), BAR), at, 0.8 * gain, rng.uniform(-0.4, 0.4))
        # Шкатулка перебирает аккорд на две октавы выше, как во вступлении.
        order = [1, 2, 3, 2, 3, 1, 2, 3]
        for i, idx in enumerate(order):
            track.add(music_box(freq(tones[idx]) * 4, BEAT * 0.5), at + i * BEAT * 0.5, box * gain, 0.35)


INTRO_BOX = 0.7


def place_intro(track, at_bar):
    """Шкатулка и струнные без мелодии. Звучит в начале и ещё раз в конце петли: перед темой
    всегда одно и то же, поэтому её начало одинаково и после вступления, и после круга петли."""
    global rng
    rng = np.random.default_rng(77)
    place_harmony(track, THEME_CHORDS[:4], at_bar, INTRO_BOX, 0.85)


def compose():
    total_bars = INTRO_BARS + LOOP_BARS * 2
    track = Track(total_bars * BAR)
    place_intro(track, 0)
    global rng
    for cycle in range(2):
        # Оба прохода петли играются одинаково до сэмпла: тогда хвосты нот с конца петли
        # в точности совпадают с теми, что звучат в её начале, и на стыке нет щелчка.
        rng = np.random.default_rng(2024)
        base = INTRO_BARS + cycle * LOOP_BARS
        # A: тема у флейты.
        # Тема входит тихо, сразу за вступлением, без скачка громкости; дальше всё нарастает.
        place_harmony(track, THEME_CHORDS, base, 0.32, 0.85, ramp_from=INTRO_BOX)
        place_melody(track, THEME, base, flute, gain=0.85, pan=0.1)
        # A2: та же тема, шкатулка отвечает подголоском.
        place_harmony(track, THEME_CHORDS, base + 8, 0.28, 0.95)
        place_melody(track, THEME, base + 8, flute, gain=1.0, pan=0.1)
        place_melody(track, COUNTER, base + 8, music_box, gain=0.9, pan=0.45)
        # B: светлая середина у мягкого квадратного лида.
        place_harmony(track, BRIDGE_CHORDS, base + 16, 0.55, 0.9)
        place_melody(track, BRIDGE, base + 16, pulse_lead, gain=1.0, pan=-0.15)
        # A3: кульминация — флейта и лид вместе, струнные шире.
        place_harmony(track, THEME_CHORDS, base + 24, 0.32, 1.2)
        place_melody(track, THEME, base + 24, flute, gain=1.2, pan=0.1)
        place_melody(track, THEME, base + 24, pulse_lead, octave_shift=1, gain=0.35, pan=-0.2)
        place_melody(track, COUNTER, base + 24, music_box, gain=0.6, pan=0.45)
        # Передышка после кульминации — снова вступление, и круг начинается с темы.
        place_intro(track, base + 32)
    return track


# --- Пространство и сведение -------------------------------------------------

def reverb(signal, seconds=2.6, seed=0):
    """Свёртка с синтетическим залом: экспоненциально гаснущий шум с ранними отражениями."""
    gen = np.random.default_rng(seed)
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    ir = gen.standard_normal(n) * np.exp(-t / (seconds / 6.9)) * (1 - np.exp(-t / 0.012))
    for delay, amp in ((0.011, 0.6), (0.019, 0.45), (0.031, 0.35), (0.047, 0.25)):
        ir[int(delay * RATE)] += amp
    # Тёмный зал: высокие гаснут быстрее.
    kernel = np.ones(9) / 9.0
    ir = np.convolve(ir, kernel, mode="same")
    ir /= np.sqrt(np.sum(ir ** 2))
    size = 1 << int(np.ceil(np.log2(len(signal) + n)))
    out = np.fft.irfft(np.fft.rfft(signal, size) * np.fft.rfft(ir, size), size)
    return out[: len(signal)]


def master(track):
    wet_l = reverb(track.left, seed=1)
    wet_r = reverb(track.right, seed=2)
    left = track.left * 0.78 + wet_l * 0.34
    right = track.right * 0.78 + wet_r * 0.34
    # Мягкое ограничение пиков, без резкого клиппинга.
    peak = max(np.max(np.abs(left)), np.max(np.abs(right)))
    left, right = left / peak * 1.25, right / peak * 1.25
    left, right = np.tanh(left), np.tanh(right)
    peak = max(np.max(np.abs(left)), np.max(np.abs(right)))
    return left / peak * 0.89, right / peak * 0.89


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_path = os.path.join(root, "assets", "music", "menu_theme.ogg")
    left, right = master(compose())
    # Вступление + вторая петля: в неё уже входит хвост реверберации от первой, стык не слышен.
    intro_end = int(LOOP_START * RATE)
    loop_len = int(LOOP_BARS * BAR * RATE)
    second = intro_end + loop_len
    pick = np.r_[0:intro_end, second:second + loop_len]
    left, right = left[pick], right[pick]
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
    print("%s: %.1f s, loop from %.3f s" % (out_path, len(left) / RATE, LOOP_START))


if __name__ == "__main__":
    main()
