"""Зимняя тема локации «Снежный перекрёсток», собранная из кода.

Ми минор, очень медленный вальс на 3/4, 66 ударов в минуту. Спокойная, почти колыбельная:
мягкий хор и струнные тянут аккорды, арфа редко перебирает их по четвертям, мелодию тихо
ведёт челеста, низкий кларнет иногда отвечает ей вполголоса. Фоном — далёкий шорох метели.

  Вступление (4 такта) — арфа, хор и метель, без мелодии.
  A  (8 тактов)  — тема у челесты.
  A2 (8 тактов)  — тема у низкого кларнета вполголоса, челеста отвечает подголоском.
  B  (8 тактов)  — середина в соль мажоре: только аккорды и редкие ноты челесты внизу.
  A3 (8 тактов)  — тема у челесты и кларнета в унисон, так же тихо; к концу стихает,
                   последняя нота тянется через стык.
  R  (4 такта)   — передышка: снова вступление, нота в ноту.

Ни ударных, ни нарастаний, ни мелодии у струнных: громкость почти ровная по всей петле.

Петля — с начала A до конца R. Перед темой всегда звучит одно и то же (вступление или R,
сыгранные одинаково до сэмпла, метель тоже повторяется по тактам), поэтому начало темы
одинаково и после вступления, и после круга петли: стык не слышен. В Godot петля
начинается с LOOP_START секунд.

Запуск: python3 tools/compose_winter_theme.py  → assets/music/snowbound_crossroads.ogg
(нужны numpy и ffmpeg). Общие тембры и сведение — из compose_menu_theme.py.
"""
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import compose_menu_theme as base  # noqa: E402

RATE = base.RATE
BPM = 66.0
BEAT = 60.0 / BPM
BAR = BEAT * 3
INTRO_BARS = 4
LOOP_BARS = 36
LOOP_START = INTRO_BARS * BAR
freq = base.freq


def rng():
    return base.rng


# --- Тембры -----------------------------------------------------------------

def clarinet(f, length):
    """Кларнет: нечётные гармоники, деревянное дыхание, вибрато входит не сразу."""
    n = int((length + 0.5) * RATE)
    t = np.arange(n) / RATE
    vibrato = 1 + 0.0035 * np.sin(2 * np.pi * 5.1 * t + rng().uniform(0, 6.28)) * np.clip((t - 0.3) / 0.5, 0, 1)
    phase = 2 * np.pi * f * np.cumsum(vibrato) / RATE
    tone = np.sin(phase) + 0.42 * np.sin(3 * phase) + 0.17 * np.sin(5 * phase) + 0.07 * np.sin(7 * phase)
    tone += 0.06 * np.sin(2 * phase)
    breath = np.convolve(rng().standard_normal(n), np.ones(30) / 30, mode="same") * 0.035
    env = np.clip(t / 0.12, 0, 1) ** 1.4
    env *= np.where(t < length, 1.0, np.exp(-(t - length) / 0.2))
    return (tone + breath) * env * 0.12


def celesta(f, length):
    """Челеста: мягкий молоточек по пластине — чистый тон и быстро гаснущий звон сверху."""
    n = int((length + 2.4) * RATE)
    t = np.arange(n) / RATE
    tone = np.sin(2 * np.pi * f * t) * np.exp(-t / 1.4)
    tone += 0.32 * np.sin(2 * np.pi * f * 2.0 * t) * np.exp(-t / 0.5)
    tone += 0.12 * np.sin(2 * np.pi * f * 4.07 * t) * np.exp(-t / 0.12)
    return tone * np.minimum(t / 0.004, 1.0) * 0.085


def harp(f, length):
    """Арфа: щипок струны — гармоники гаснут тем быстрее, чем выше; мягкая атака пальца."""
    n = int((length + 2.0) * RATE)
    t = np.arange(n) / RATE
    out = np.zeros(n)
    for k in range(1, 8):
        if f * k > 9000:
            break
        out += np.sin(2 * np.pi * f * k * t + rng().uniform(0, 0.4)) * np.exp(-t * (0.9 + 0.8 * k)) / k ** 1.2
    return out * np.minimum(t / 0.006, 1.0) * 0.07


def choir(f, length):
    """Хор на «а»: несколько чуть расстроенных голосов, гармоники взвешены формантами гласной."""
    n = int((length + 1.2) * RATE)
    t = np.arange(n) / RATE
    out = np.zeros(n)
    formants = ((700.0, 130.0, 1.0), (1220.0, 170.0, 0.55), (2600.0, 250.0, 0.25))
    for detune in (-0.006, -0.002, 0.003, 0.007):
        fd = f * (1 + detune)
        vib = 1 + 0.004 * np.sin(2 * np.pi * (4.3 + detune * 100) * t + rng().uniform(0, 6.28))
        phase = 2 * np.pi * fd * np.cumsum(vib) / RATE
        for k in range(1, 30):
            h = fd * k
            if h > 4500:
                break
            weight = sum(a * np.exp(-((h - c) / w) ** 2) for c, w, a in formants) + 0.04 / k
            out += np.sin(k * phase) * weight
    return out * base.envelope(n, 0.9, 1.1) * 0.012


def bell(f):
    """Колокольчик метели: высокий чистый звон с негармоническим призвуком."""
    n = int(2.5 * RATE)
    t = np.arange(n) / RATE
    tone = np.sin(2 * np.pi * f * t) + 0.4 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t / 0.3)
    return tone * np.exp(-t / 0.8) * np.minimum(t / 0.002, 1.0) * 0.05


def wind_bar(seed):
    """Метель на один такт с запасом: шум, отфильтрованный в полосу, медленно дышит.
    Такты перекрываются плавными окнами, поэтому шорох идёт без швов."""
    gen = np.random.default_rng(seed)
    n = int(BAR * 2 * RATE)
    noise = gen.standard_normal(n)
    spectrum = np.fft.rfft(noise)
    f = np.fft.rfftfreq(n, 1.0 / RATE)
    centre = 520 + 260 * gen.uniform()
    spectrum *= np.exp(-((np.log(f + 1) - np.log(centre)) / 0.55) ** 2)
    out = np.fft.irfft(spectrum, n)
    out /= np.max(np.abs(out)) + 1e-9
    t = np.arange(n) / RATE
    gust = 0.6 + 0.4 * np.sin(2 * np.pi * t / (BAR * 2) * (1 + gen.uniform()) + gen.uniform(0, 6.28))
    window = np.sin(np.pi * np.arange(n) / n) ** 2
    return out * gust * window * 0.03


# --- Партитура ---------------------------------------------------------------
# Ноты — (высота, длительность в долях). «-» — пауза. Такт — три доли.

THEME = [
    [("B4", 2), ("E5", 1)],
    [("G5", 2), ("F#5", 0.5), ("E5", 0.5)],
    [("D5", 1.5), ("B4", 0.5), ("D5", 1)],
    [("A4", 3)],
    [("B4", 1), ("E5", 1), ("G5", 1)],
    [("A5", 2), ("G5", 0.5), ("F#5", 0.5)],
    [("F#5", 1), ("D#5", 1), ("B4", 1)],
    [("E5", 3)],
]
THEME_CHORDS = [
    ("Em", ["E2", "B2", "E3", "G3"]), ("C", ["C2", "G2", "C3", "E3"]),
    ("G", ["G2", "D3", "G3", "B3"]), ("D", ["D2", "A2", "D3", "F#3"]),
    ("Em", ["E2", "B2", "E3", "G3"]), ("Am", ["A2", "E3", "A3", "C4"]),
    ("B7", ["B1", "F#2", "D#3", "A3"]), ("Em", ["E2", "B2", "E3", "G3"]),
]
BRIDGE = [
    [("G5", 1), ("A5", 1), ("B5", 1)],
    [("D6", 2), ("B5", 1)],
    [("C6", 1.5), ("B5", 0.5), ("A5", 1)],
    [("G5", 3)],
    [("E5", 1), ("G5", 1), ("C6", 1)],
    [("B5", 2), ("G5", 1)],
    [("A5", 1), ("C6", 1), ("E6", 1)],
    [("D#6", 1.5), ("B5", 1.5)],
]
BRIDGE_CHORDS = [
    ("C", ["C2", "G2", "C3", "E3"]), ("G", ["G2", "D3", "G3", "B3"]),
    ("Am", ["A2", "E3", "A3", "C4"]), ("Em", ["E2", "B2", "E3", "G3"]),
    ("C", ["C2", "G2", "C3", "E3"]), ("G", ["G2", "D3", "G3", "B3"]),
    ("Am", ["A2", "E3", "A3", "C4"]), ("B7", ["B1", "F#2", "D#3", "A3"]),
]
# Подголосок кларнета во второй теме: отвечает челесте на второй и третьей доле.
COUNTER = [
    [("-", 1), ("G4", 1), ("B4", 1)],
    [("-", 1), ("E4", 1), ("G4", 1)],
    [("-", 1), ("B4", 1), ("G4", 1)],
    [("F#4", 1.5), ("A4", 1.5)],
    [("-", 1), ("G4", 1), ("B4", 1)],
    [("-", 1), ("C5", 1), ("E5", 1)],
    [("D#5", 1), ("F#4", 1), ("A4", 1)],
    [("G4", 1.5), ("B4", 1.5)],
]
# Последняя нота кульминации тянется через стык: в A3 она снята из темы.
THEME_OPEN_END = THEME[:-1] + [[("-", 3)]]
A3_DYNAMICS = [1.0, 1.0, 1.0, 1.0, 1.0, 0.95, 0.85, 0.75]


def place_melody(track, bars, start_bar, voice, octave_shift=0, gain=1.0, pan=0.0, bar_gain=None):
    for b, bar in enumerate(bars):
        at = (start_bar + b) * BAR
        level = gain * (bar_gain[b] if bar_gain else 1.0)
        for note, beats in bar:
            if note != "-":
                f = freq(note) * (2.0 ** octave_shift)
                humanize = rng().uniform(-0.008, 0.008)
                track.add(voice(f, beats * BEAT * 0.96), at + humanize, level * rng().uniform(0.92, 1.0), pan)
            at += beats * BEAT


# Аккомпанемент вальса: бас на сильную долю, волна арфы восьмыми, хор и струнные держат аккорд.
# harp_from — с какой громкости арфа сходит к harp_gain за первые два такта.
def place_harmony(track, chords, start_bar, harp_gain, choir_gain, string_gain, gain=1.0,
                  harp_from=None, bar_gain=None):
    for b, (_, tones) in enumerate(chords):
        at = (start_bar + b) * BAR
        g = gain * (bar_gain[b] if bar_gain else 1.0)
        h = harp_gain if harp_from is None else harp_from + (harp_gain - harp_from) * min((b + 0.5) / 2.0, 1.0)
        track.add(base.warm_bass(freq(tones[0]), BAR * 0.95), at, 0.85 * g, -0.05)
        for tone in tones[1:]:
            if choir_gain > 0:
                track.add(choir(freq(tone) * 2, BAR), at, choir_gain * g, rng().uniform(-0.5, 0.5))
            if string_gain > 0:
                track.add(base.strings(freq(tone) * 2, BAR), at, string_gain * g, rng().uniform(-0.4, 0.4))
        # Арфа редко, по четвертям: вверх по аккорду, на две октавы выше баса.
        for i, idx in enumerate([1, 2, 3]):
            track.add(harp(freq(tones[idx]) * 2, BEAT), at + i * BEAT, h * g, 0.25 - 0.2 * i)


def place_wind(track, start_bar, bars, gain=1.0):
    for b in range(bars):
        bar = start_bar + b
        # Шорох повторяется по тактам петли: на стыке звучит то же, что в её начале.
        # Вступление дует так же, как передышка R в конце петли (её такты 32–35).
        seed = 500 + ((bar - INTRO_BARS) % LOOP_BARS if bar >= INTRO_BARS else LOOP_BARS - INTRO_BARS + bar)
        gust = wind_bar(seed)
        at = (bar - 0.5) * BAR
        if at < 0:
            gust = gust[int(-at * RATE):]
            at = 0.0
        track.add(gust, at, gain, (seed % 7) / 7 - 0.5)


INTRO_HARP = 1.0


def place_intro(track, at_bar, harp_from=None):
    """Арфа, хор и метель без мелодии. Звучит в начале и в конце петли одинаково до сэмпла."""
    base.rng = np.random.default_rng(31)
    place_harmony(track, THEME_CHORDS[:4], at_bar, INTRO_HARP, 0.8, 0.35, 0.8, harp_from=harp_from)
    # Колокольчики метели: два звона на вступление.
    track.add(bell(freq("B6")), (at_bar + 1) * BAR + BEAT, 0.7, 0.5)
    track.add(bell(freq("E7")), (at_bar + 3) * BAR + 2 * BEAT, 0.5, -0.5)


def compose():
    total_bars = INTRO_BARS + LOOP_BARS * 2
    track = base.Track(total_bars * BAR)
    place_intro(track, 0)
    for cycle in range(2):
        # Оба прохода петли одинаковы до сэмпла: хвосты с конца петли совпадают с её началом.
        base.rng = np.random.default_rng(2025)
        start = INTRO_BARS + cycle * LOOP_BARS
        # A: тема у челесты; арфа сходит со вступления тише.
        place_harmony(track, THEME_CHORDS, start, 0.75, 0.7, 0.35, 0.8, harp_from=INTRO_HARP)
        place_melody(track, THEME, start, celesta, gain=1.05, pan=0.2)
        # A2: тема у низкого кларнета вполголоса, челеста отвечает подголоском.
        place_harmony(track, THEME_CHORDS, start + 8, 0.7, 0.75, 0.4, 0.8)
        place_melody(track, THEME, start + 8, clarinet, octave_shift=-1, gain=0.6, pan=-0.1)
        place_melody(track, COUNTER, start + 8, celesta, octave_shift=1, gain=0.55, pan=0.4)
        # B: середина — аккорды и редкие ноты челесты внизу.
        place_harmony(track, BRIDGE_CHORDS, start + 16, 0.75, 0.85, 0.45, 0.8)
        place_melody(track, BRIDGE, start + 16, celesta, octave_shift=-1, gain=0.8, pan=-0.2)
        # A3: тема у челесты и кларнета в унисон, тихо; к концу стихает.
        place_harmony(track, THEME_CHORDS, start + 24, 0.7, 0.8, 0.4, 0.8, bar_gain=A3_DYNAMICS)
        place_melody(track, THEME_OPEN_END, start + 24, celesta, gain=0.95, pan=0.2, bar_gain=A3_DYNAMICS)
        place_melody(track, THEME_OPEN_END, start + 24, clarinet, octave_shift=-1, gain=0.45, pan=-0.1, bar_gain=A3_DYNAMICS)
        # Последняя «ми» тянется через стык и гаснет во вступлении.
        held = clarinet(freq("E4"), 1.7 * BAR)
        held *= np.clip(1.0 - np.arange(len(held)) / len(held), 0.0, 1.0) ** 1.6
        track.add(held, (start + 31) * BAR, 0.5 * A3_DYNAMICS[-1], -0.1)
        # Передышка — снова вступление; арфа входит тихо и разгорается.
        place_intro(track, start + 32, harp_from=0.3)
    place_wind(track, 0, total_bars, 0.6)
    return track


def master(track):
    # Зал больше, чем у темы меню: снежная тишина звенит дольше.
    wet_l = base.reverb(track.left, seconds=4.2, seed=3)
    wet_r = base.reverb(track.right, seconds=4.2, seed=4)
    left = track.left * 0.68 + wet_l * 0.5
    right = track.right * 0.68 + wet_r * 0.5
    peak = max(np.max(np.abs(left)), np.max(np.abs(right)))
    left, right = np.tanh(left / peak * 1.05), np.tanh(right / peak * 1.05)
    peak = max(np.max(np.abs(left)), np.max(np.abs(right)))
    return left / peak * 0.89, right / peak * 0.89


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_path = os.path.join(root, "assets", "music", "snowbound_crossroads.ogg")
    left, right = master(compose())
    intro_end = int(round(LOOP_START * RATE))
    loop_len = int(round(LOOP_BARS * BAR * RATE))
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
    print("%s: %.1f s, loop from %.4f s" % (out_path, len(left) / RATE, LOOP_START))


if __name__ == "__main__":
    main()
