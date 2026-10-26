#!/usr/bin/env python3
"""Synthesises Hunt Frenzy's eight bluegrass loops and encodes them to MP3.

Ported from BrewMagic's tools/music.py (../jamference-20261016) and re-voiced as a small
bluegrass band: a five-string banjo (bright plucked partials, the high ones dying fast)
plays forward rolls over the chords with the tune's notes on top, a fiddle (a bowed
wavetable with vibrato) carries or doubles the tune, a flat-picked guitar plays the
boom-chuck (bass note, then the chord), an upright bass walks the roots and fifths, and a
washboard or a brush keeps time where a track needs it. Every loop is built on one
original motif (MOTIF: a rise from G through B and D to E, a step back, then an answer
that settles on G): the title states it on banjo, each chapter recolours it (dawn a slow
fiddle air, noon a brisk breakdown, sunset in E minor, night a sparse waltz-like hush),
Endless and Time Attack drive it faster and fuller, and the results loop slows it into a
warm close. The melodies are written here from scratch; none quotes a traditional tune
or any game's music.

Each loop is rendered into a buffer exactly one loop long. Note tails that run past the
end wrap around to the start, so the last sample flows into the first and the loop is
seamless. MP3 encoding adds silence before and after the audio; lame records how much in
its LAME/Xing tag, and Godot's decoder (like ffmpeg) trims it, so the decoded file is
exactly one loop and Godot's plain whole-file loop is seamless. Never pass lame -t: it
drops that tag. After encoding, each file is decoded (gapless) with ffmpeg to check it is
exactly one loop long, and the loop is switched on in its .import file.

The rendered PCM of every loop is deterministic (stdlib only, fixed seeds); its sha256 and
length are recorded in tools/music.lock.json together with the sha256 and size of the MP3
made from it, which --check compares against a fresh render and the committed files (no
lame or ffmpeg needed, so validate.sh runs it locally and in CI).

Usage (from repo root):
    python3 tools/music.py           render, encode huntfrenzy/audio/music/<track>.mp3, write the lock
    python3 tools/music.py --check   render in memory and verify the lock, the MP3s (bytes and
                                     size) and their .import loop flags; prints "music: OK"
Generating needs lame and ffmpeg on PATH (Homebrew: brew install lame ffmpeg). The MP3s are
constant bitrate (96 kbps mono) without ID3 tags.
"""
import hashlib
import json
import math
import operator
import random
import shutil
import struct
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "huntfrenzy"
OUT_DIR = PROJECT / "audio" / "music"
LOCK = ROOT / "tools" / "music.lock.json"
RATE = 44100
# Music sits under the sound effects (tools/sfx.py PEAK 0.9).
PEAK = 0.6
NOTE_NAMES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
# The eight MP3s together must stay under this (all the audio stays under 8 MB: plan AC 15).
MAX_TOTAL_BYTES = 6 * 1024 * 1024
# Steps (8th notes) per bar: every track is in 4/4.
BAR_STEPS = 8


class MusicError(Exception):
    pass


def freq(note):
    """'C5', 'F#4', 'Bb3' -> Hz (A4 = 440)."""
    name, octave = note[:-1], int(note[-1])
    semitone = NOTE_NAMES[name[0]] + name.count("#") - name.count("b")
    return 440.0 * 2 ** ((semitone + 12 * (octave + 1) - 69) / 12)


def parse(bars, name, key):
    """Bars of BAR_STEPS space-separated steps: a note (or notes joined by '+') starts, '-'
    holds, '.' rests. Returns ([(notes, start_step, length_steps)], total_steps)."""
    for i, bar in enumerate(bars):
        if len(bar.split()) != BAR_STEPS:
            raise MusicError(f"{name}: '{key}' bar {i + 1} has {len(bar.split())} steps, expected {BAR_STEPS}")
    steps = " ".join(bars).split()
    events = []
    for i, token in enumerate(steps):
        if token in ("-", "."):
            continue
        length = 1
        while i + length < len(steps) and steps[i + length] == "-":
            length += 1
        events.append((token.split("+"), i, length))
    return events, len(steps)


_CACHE = {}


def partials_tone(hz, n, partials, attack, damp_from=None, damp_len=0):
    """Sum of sine partials (frequency multiple, amplitude, decay per second), n samples,
    with a linear attack and, from sample damp_from on, a damp_len-sample fade out."""
    key = ("partials", round(hz, 6), n, partials, attack, damp_from, damp_len)
    if key in _CACHE:
        return _CACHE[key]
    out = [0.0] * n
    for mult, amp, decay in partials:
        w = 2 * math.pi * hz * mult / RATE
        if w >= math.pi:
            continue
        r = math.exp(-decay / RATE)
        out = list(map(operator.add, out, [amp * math.sin(w * i) * r ** i for i in range(n)]))
    a = max(1, int(attack * RATE))
    for i in range(min(a, n)):
        out[i] *= i / a
    if damp_from is not None:
        for i in range(damp_from, n):
            out[i] *= max(0.0, 1.0 - (i - damp_from) / max(1, damp_len))
    _CACHE[key] = out
    return out


# The fiddle's single bowed period: a bright saw-like spectrum with a body resonance bump.
FIDDLE_PARTIALS = tuple((h, (1.0 / h) * (1.0 + 0.8 * math.exp(-((h - 3) ** 2) / 2.0))) for h in range(1, 13))
WAVETABLE_SIZE = 2048
VIBRATO_HZ = 5.5
VIBRATO_DEPTH = 0.006


def bowed_tone(hz, n, attack, release):
    """A bowed note: the fiddle's wavetable (only the partials under Nyquist) read with a
    vibrato that starts after the attack, a linear attack and a linear release."""
    key = ("bowed", round(hz, 6), n, attack, release)
    if key in _CACHE:
        return _CACHE[key]
    table = [sum(amp * math.sin(2 * math.pi * mult * i / WAVETABLE_SIZE) for mult, amp in FIDDLE_PARTIALS if hz * mult < RATE / 2)
             for i in range(WAVETABLE_SIZE)]
    a, r = max(1, int(attack * RATE)), max(1, int(release * RATE))
    out, phase = [], 0.0
    vib_w = 2 * math.pi * VIBRATO_HZ / RATE
    for i in range(n):
        depth = VIBRATO_DEPTH * min(1.0, i / (3 * a))
        phase = (phase + hz * (1.0 + depth * math.sin(vib_w * i)) / RATE) % 1.0
        out.append(table[int(phase * WAVETABLE_SIZE)] * min(1.0, i / a, (n - i) / r))
    _CACHE[key] = out
    return out


# Plucked instruments: (partials, attack seconds, ring seconds, damped). A ringing one (the
# banjo) lets every note sound for `ring` seconds whatever its written length; a damped one
# (guitar, bass) stops at the written length with a short fade.
# Banjo: plucked near the bridge (bright, every partial present), the head's quick decay.
BANJO = (tuple((h, 0.9 / h ** 0.75 * (0.35 + abs(math.sin(math.pi * h * 0.11))), 7.0 + 4.0 * h) for h in range(1, 11)), 0.0015, 0.5, False)
GUITAR = (tuple((h, 0.9 / h ** 1.2 * abs(math.sin(math.pi * h * 0.2)), 2.6 + 1.8 * h) for h in range(1, 9)), 0.003, 0.0, True)
BASS = (tuple((h, 1.0 / h ** 1.5, 2.4 + 1.6 * h) for h in range(1, 6)), 0.006, 0.0, True)
DAMP_SECONDS = 0.05


def render_pluck(instrument, hz, seconds):
    partials, attack, ring, damped = instrument
    if damped:
        n = int((seconds + DAMP_SECONDS) * RATE)
        return partials_tone(hz, n, partials, attack, int(seconds * RATE), int(DAMP_SECONDS * RATE))
    # A ringing note still fades over its last DAMP_SECONDS, so its cut never clicks.
    n = int(max(seconds, ring) * RATE)
    return partials_tone(hz, n, partials, attack, n - int(DAMP_SECONDS * RATE), int(DAMP_SECONDS * RATE))


def add_into(buf, samples, start, gain):
    """Adds samples * gain into buf from `start`, wrapping past the end to the start."""
    size = len(buf)
    start %= size
    pos = 0
    while pos < len(samples):
        at = (start + pos) % size
        count = min(len(samples) - pos, size - at)
        buf[at:at + count] = map(operator.add, buf[at:at + count], [s * gain for s in samples[pos:pos + count]])
        pos += count


def washboard(rng, seconds):
    """A thimble scraped down a washboard: a burst of ridged, high-passed noise."""
    n, last, out = int(seconds * RATE), 0.0, []
    for i in range(n):
        x = rng.uniform(-1.0, 1.0) * (0.55 + 0.45 * math.sin(2 * math.pi * 160.0 * i / RATE))
        out.append((x - last) * math.exp(-28.0 * i / RATE) * min(1.0, i / 40))
        last = x
    return out


def brush(rng):
    """A brush swept on a snare: a soft, slowly swelling and fading hiss."""
    n, y, out = int(0.18 * RATE), 0.0, []
    for i in range(n):
        y += 0.35 * (rng.uniform(-1.0, 1.0) - y)
        out.append(y * math.sin(math.pi * i / n) ** 2)
    return out


def thump(rng):
    """A soft kick on the guitar's body (the downbeat of the driving tracks)."""
    n, phase, out = int(0.16 * RATE), 0.0, []
    for i in range(n):
        phase += (80.0 * (1.0 + 0.7 * math.exp(-30.0 * i / RATE))) / RATE
        out.append(math.sin(2 * math.pi * phase) * math.exp(-18.0 * i / RATE) + rng.uniform(-0.05, 0.05) * math.exp(-80.0 * i / RATE))
    return out


# Chords: bass root, bass fifth, chord tones low to high (the guitar strums them, the banjo
# rolls them).
CHORDS = {
    "G": ("G2", "D3", ("G3", "B3", "D4", "G4")),
    "C": ("C3", "G2", ("G3", "C4", "E4", "G4")),
    "D": ("D3", "A2", ("F#3", "A3", "D4", "F#4")),
    "Em": ("E2", "B2", ("G3", "B3", "E4", "G4")),
    "Am": ("A2", "E3", ("A3", "C4", "E4", "A4")),
    "Bm": ("B2", "F#3", ("F#3", "B3", "D4", "F#4")),
}

# The shared motif (8 bars of eight 8th-note steps, 4/4) and its chords.
MOTIF = [
    "G4 - B4 D5 E5 - D5 B4", "A4 - G4 A4 B4 - - -", "D5 - E5 G5 E5 - D5 B4", "A4 - B4 A4 G4 - - -",
    "B4 - D5 E5 G5 - E5 D5", "E5 - D5 B4 A4 - - -", "G4 - A4 B4 D5 - B4 A4", "G4 - - - - - - -",
]
MOTIF_CHORDS = ["G", "D", "G", "D", "Em", "C", "D", "G"]
# The answer: the motif's rise turned around the C chord, then home.
ANSWER = [
    "E5 - D5 E5 G5 - E5 D5", "D5 - B4 G4 A4 - - -", "E5 - G5 E5 D5 - B4 A4", "B4 - A4 G4 B4 - - -",
    "C5 - E5 G5 A5 - G5 E5", "D5 - B4 D5 G5 - - -", "A4 - B4 D5 E5 - D5 B4", "G4 - - - - - - -",
]
ANSWER_CHORDS = ["C", "D", "C", "G", "Am", "G", "D", "G"]
# The motif with eighth-note runs filled in (the breakdowns).
MOTIF_RUN = [
    "G4 A4 B4 D5 E5 D5 D5 B4", "A4 B4 G4 A4 B4 A4 G4 B4", "D5 D5 E5 G5 E5 D5 D5 B4", "A4 G4 B4 A4 G4 B4 D5 B4",
    "B4 D5 D5 E5 G5 A5 E5 D5", "E5 G5 D5 B4 A4 B4 A4 G4", "G4 A4 A4 B4 D5 E5 B4 A4", "G4 - B4 D5 G5 - - -",
]
# The motif in E minor (sunset): the same rise from E, the turn on C, the close on E.
MOTIF_MINOR = [
    "E4 - G4 B4 C5 - B4 G4", "F#4 - E4 F#4 G4 - - -", "B4 - C5 E5 C5 - B4 G4", "F#4 - G4 F#4 E4 - - -",
    "G4 - B4 C5 E5 - C5 B4", "C5 - B4 G4 F#4 - - -", "E4 - F#4 G4 B4 - G4 F#4", "E4 - - - - - - -",
]
MINOR_CHORDS = ["Em", "D", "Em", "Bm", "C", "Am", "Bm", "Em"]
# The motif slowed to half notes (night, dawn): its outline only.
MOTIF_SLOW = [
    "G4 - - - B4 - D5 -", "A4 - - - - - - -", "D5 - - - E5 - D5 -", "A4 - - - B4 - - -",
    "B4 - - - G5 - E5 -", "E5 - - - A4 - - -", "G4 - - - D5 - B4 -", "G4 - - - - - - -",
]
# The results close: the motif's answer slowed, ending on a held G with a last lift.
CLOSE = [
    "B4 - - - D5 - E5 -", "D5 - - - B4 - A4 -", "G4 - - - A4 - B4 -", "A4 - - - - - - -",
    "C5 - - - E5 - G5 -", "D5 - - - B4 - D5 -", "A4 - - - B4 - A4 -", "G4 - - - - - D5 -",
]
CLOSE_CHORDS = ["G", "G", "C", "D", "C", "G", "D", "G"]


def roll(chords, melody, pattern):
    """The banjo's bars: the melody's notes where it has an onset, else the forward-roll
    `pattern` (indexes into the chord's tones, one per step) picking the chord."""
    bars = []
    for chord, bar in zip(chords, melody):
        tones = CHORDS[chord][2]
        steps = bar.split()
        out = []
        for i, token in enumerate(steps):
            out.append(token if token not in ("-", ".") else "~" + tones[pattern[i % len(pattern)]])
        bars.append(" ".join(out))
    return bars


def guitar_bars(chords, style):
    """Per-bar guitar: 'boomchuck' (bass note on 1 and 3, the chord on 2 and 4), 'strum'
    (the chord on every beat) or 'arp' (the chord picked up and down in 8ths)."""
    bars = []
    for name in chords:
        root, fifth, (t0, t1, t2, t3) = CHORDS[name]
        chord = f"{t0}+{t1}+{t2}"
        if style == "boomchuck":
            bars.append(f"{t0} . {chord} . {t1} . {chord} .")
        elif style == "strum":
            bars.append(f"{chord} . {chord} . {chord} . {chord} {chord}")
        elif style == "arp":
            bars.append(f"{t0} {t1} {t2} {t3} {t2} {t1} {t2} {t1}")
        else:
            raise MusicError(f"unknown guitar style '{style}'")
    return bars


def bass_bars(chords, style):
    """Per-bar upright bass: 'two' (root on 1, fifth on 3), 'walk' (root, fifth and a
    passing step on every beat) or 'whole' (one long root)."""
    bars = []
    for name in chords:
        root, fifth = CHORDS[name][0], CHORDS[name][1]
        if style == "two":
            bars.append(f"{root} - . . {fifth} - . .")
        elif style == "walk":
            bars.append(f"{root} - {fifth} - {root} - {fifth} -")
        elif style == "whole":
            bars.append(f"{root} - - - - - - -")
        else:
            raise MusicError(f"unknown bass style '{style}'")
    return bars


FORWARD_ROLL = (0, 2, 3, 0, 2, 3, 0, 3)
BACKWARD_ROLL = (3, 2, 0, 3, 2, 0, 3, 2)


def track(name, bpm, melody, chords, *, banjo=1.0, banjo_roll=FORWARD_ROLL, fiddle=0.0, fiddle_octave=0,
          guitar="boomchuck", guitar_gain=0.14, bass="two", perc=None):
    """A loop at `bpm` quarter notes a minute: the tune (`melody` bars, one chord each),
    the banjo playing it in rolls at gain `banjo` (0: no banjo), the fiddle doubling it at
    gain `fiddle` (`fiddle_octave` up or down), the guitar and bass styles, and the
    percussion bars (BAR_STEPS characters: 'w' washboard, 'W' a long scrape, 'b' brush,
    'k' body thump, '.' none; None: no percussion)."""
    return {"name": name, "step": 60.0 / bpm / 2, "melody": melody, "chords": chords, "banjo": banjo,
            "banjo_roll": banjo_roll, "fiddle": fiddle, "fiddle_octave": fiddle_octave,
            "guitar": guitar_bars(chords, guitar) if guitar else None, "guitar_gain": guitar_gain,
            "bass": bass_bars(chords, bass), "perc": perc if perc is not None else ["." * BAR_STEPS] * len(melody)}


# Title: the motif and its answer on banjo over boom-chuck guitar and a two-beat bass.
TITLE = track("title", 116, MOTIF + ANSWER, MOTIF_CHORDS + ANSWER_CHORDS, fiddle=0.18,
              perc=["....b..."] * 16)
# Dawn: a slow fiddle air on the motif's outline, the guitar picking arpeggios, no banjo.
CAMPAIGN_DAWN = track("campaign_dawn", 84, MOTIF_SLOW + MOTIF, MOTIF_CHORDS * 2, banjo=0.0, fiddle=0.5,
                      guitar="arp", guitar_gain=0.16, bass="whole")
# Noon: a brisk breakdown, banjo rolls on the filled-in motif, washboard on the off-beats.
CAMPAIGN_NOON = track("campaign_noon", 132, MOTIF_RUN + ANSWER, MOTIF_CHORDS + ANSWER_CHORDS, fiddle=0.12,
                      perc=[".w.w.w.w"] * 16)
# Sunset: the motif in E minor, fiddle lead with backward banjo rolls under it.
CAMPAIGN_SUNSET = track("campaign_sunset", 104, MOTIF_MINOR * 2, MINOR_CHORDS * 2, banjo=0.55,
                        banjo_roll=BACKWARD_ROLL, fiddle=0.42, perc=["b...b..."] * 16)
# Night: a sparse hush, the slow outline on a low fiddle, soft guitar, one bass note a bar.
CAMPAIGN_NIGHT = track("campaign_night", 76, MOTIF_SLOW + CLOSE, MOTIF_CHORDS + CLOSE_CHORDS, banjo=0.0,
                       fiddle=0.45, fiddle_octave=-1, guitar="arp", guitar_gain=0.12, bass="whole",
                       perc=["b......."] * 16)
# Endless: the breakdown driving on, walking bass, thump and washboard.
ENDLESS = track("endless", 144, MOTIF_RUN + ANSWER + MOTIF + MOTIF_RUN, (MOTIF_CHORDS + ANSWER_CHORDS) * 2,
                fiddle=0.2, guitar="strum", bass="walk", perc=["kw.wkw.w"] * 32)
# Time Attack: the fastest, banjo and fiddle in unison on the runs, washboard every 8th.
TIME_ATTACK = track("time_attack", 168, MOTIF_RUN * 2 + ANSWER + MOTIF_RUN, MOTIF_CHORDS * 2 + ANSWER_CHORDS + MOTIF_CHORDS,
                    fiddle=0.3, guitar="strum", bass="walk", perc=["kwwWkwwW"] * 32)
# Results: the close, warm and slower, banjo and fiddle together.
RESULTS = track("results", 96, CLOSE + MOTIF, CLOSE_CHORDS + MOTIF_CHORDS, banjo=0.7, fiddle=0.32,
                perc=["b...b..."] * 16)

TRACKS = (TITLE, CAMPAIGN_DAWN, CAMPAIGN_NOON, CAMPAIGN_SUNSET, CAMPAIGN_NIGHT, ENDLESS, TIME_ATTACK, RESULTS)

# Voice gains (before the whole loop is normalised to PEAK).
MELODY_GAIN = 0.34
ROLL_GAIN = 0.18
BASS_GAIN = 0.36
PERC_GAINS = {"w": 0.07, "W": 0.1, "b": 0.05, "k": 0.22}


def render(spec):
    """One loop of `spec` as float samples."""
    step = spec["step"]
    name = spec["name"]
    melody, total = parse(spec["melody"], name, "melody")
    if len(spec["chords"]) * BAR_STEPS != total:
        raise MusicError(f"{name}: {len(spec['chords'])} chords for {total // BAR_STEPS} bars")
    size = int(round(total * step * RATE))
    buf = [0.0] * size

    def at(start):
        return int(round(start * step * RATE))

    if spec["banjo"] > 0.0:
        banjo, steps = parse(roll(spec["chords"], spec["melody"], spec["banjo_roll"]), name, "banjo")
        for notes, start, length in banjo:
            for note in notes:
                rolled = note.startswith("~")
                add_into(buf, render_pluck(BANJO, freq(note.lstrip("~")), length * step * 0.95), at(start),
                         spec["banjo"] * (ROLL_GAIN if rolled else MELODY_GAIN))
    if spec["fiddle"] > 0.0:
        for notes, start, length in melody:
            for note in notes:
                hz = freq(note) * 2.0 ** spec["fiddle_octave"]
                n = int(length * step * 0.97 * RATE)
                add_into(buf, bowed_tone(hz, n, 0.04, min(0.08, length * step * 0.4)), at(start), spec["fiddle"] * MELODY_GAIN)
    for key, instrument, gain in (("guitar", GUITAR, spec["guitar_gain"]), ("bass", BASS, BASS_GAIN)):
        if spec[key] is None:
            continue
        events, steps = parse(spec[key], name, key)
        if steps != total:
            raise MusicError(f"{name}: '{key}' is {steps} steps, expected {total}")
        for notes, start, length in events:
            for i, note in enumerate(notes):
                # A strum: each string a hair after the one below it.
                add_into(buf, render_pluck(instrument, freq(note), length * step * 0.9), at(start) + i * int(0.008 * RATE), gain)
    hits = "".join(spec["perc"])
    if len(hits) != total:
        raise MusicError(f"{name}: 'perc' is {len(hits)} steps, expected {total}")
    rng = random.Random(f"music/{name}")
    kit = {"w": washboard(rng, 0.05), "W": washboard(rng, 0.12), "b": brush(rng), "k": thump(rng)}
    for i, hit in enumerate(hits):
        if hit in kit:
            add_into(buf, kit[hit], at(i), PERC_GAINS[hit])
        elif hit != ".":
            raise MusicError(f"{name}: unknown percussion '{hit}'")
    return buf


def to_pcm(samples):
    top = max(abs(s) for s in samples) or 1.0
    return b"".join(struct.pack("<h", int(s / top * PEAK * 32767)) for s in samples)


def render_all():
    """{track name: (16-bit mono PCM bytes, sample count)} for every track."""
    rendered = {}
    for spec in TRACKS:
        pcm = to_pcm(render(spec))
        rendered[spec["name"]] = (pcm, len(pcm) // 2)
    return rendered


def file_sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def lock_entry(pcm, samples, mp3):
    return {"samples": samples, "seconds": round(samples / RATE, 3), "sha256": hashlib.sha256(pcm).hexdigest(),
            "mp3_sha256": file_sha(mp3), "mp3_bytes": mp3.stat().st_size}


def import_has_loop(mp3):
    path = Path(str(mp3) + ".import")
    return path.exists() and "loop=true" in path.read_text().splitlines()


def check():
    try:
        lock = json.loads(LOCK.read_text())
    except (OSError, ValueError) as e:
        raise MusicError(f"cannot read {LOCK.relative_to(ROOT)}: {e}; run python3 tools/music.py")
    problems = []
    rendered = render_all()
    if sorted(lock) != sorted(rendered):
        problems.append(f"{LOCK.relative_to(ROOT)} lists {sorted(lock)}, the tracks are {sorted(rendered)}")
    total_bytes = 0
    for name, (pcm, samples) in rendered.items():
        want = lock.get(name, {})
        if want.get("samples") != samples:
            problems.append(f"{name}: the loop is {samples} samples, the lock says {want.get('samples')}")
        if want.get("sha256") != hashlib.sha256(pcm).hexdigest():
            problems.append(f"{name}: the rendered audio differs from the lock, run python3 tools/music.py")
        mp3 = OUT_DIR / f"{name}.mp3"
        if not mp3.exists():
            problems.append(f"{mp3.relative_to(ROOT)} missing, run python3 tools/music.py")
            continue
        total_bytes += mp3.stat().st_size
        if want.get("mp3_bytes") != mp3.stat().st_size or want.get("mp3_sha256") != file_sha(mp3):
            problems.append(f"{mp3.relative_to(ROOT)} differs from the MP3 the lock records, run python3 tools/music.py")
        if not import_has_loop(mp3):
            problems.append(f"{mp3.relative_to(ROOT)}.import does not switch the loop on (loop=true)")
    for path in sorted(OUT_DIR.glob("*.mp3")):
        if path.stem not in rendered:
            problems.append(f"{path.relative_to(ROOT)} is stale: no track makes it any more")
    if total_bytes > MAX_TOTAL_BYTES:
        problems.append(f"the MP3s total {total_bytes} bytes, over {MAX_TOTAL_BYTES}")
    if problems:
        raise MusicError("\n".join(problems))
    print(f"music: OK ({len(rendered)} loops, {total_bytes} bytes of MP3)")


def check_decode(ffmpeg, mp3, samples):
    """Decodes `mp3` the gapless way (as Godot does) and confirms it is exactly `samples` long."""
    raw = subprocess.run([ffmpeg, "-v", "error", "-i", str(mp3), "-f", "s16le", "-ac", "1", "-"],
                         capture_output=True, check=True).stdout
    if len(raw) // 2 != samples:
        raise MusicError(f"{mp3} decodes to {len(raw) // 2} samples, expected {samples}; is lame still writing its LAME tag?")


def write_import(mp3):
    """Switches Godot's plain loop on in <mp3>.import, keeping whatever else Godot wrote there."""
    path = Path(str(mp3) + ".import")
    params = {"loop": "true", "loop_offset": "0", "bpm": "0", "beat_count": "0", "bar_beats": "4"}
    if path.exists():
        lines, seen = [], set()
        for line in path.read_text().splitlines():
            key = line.split("=", 1)[0]
            if key in params:
                line = f"{key}={params[key]}"
                seen.add(key)
            lines.append(line)
        lines += [f"{k}={v}" for k, v in params.items() if k not in seen]
        text = "\n".join(lines) + "\n"
    else:
        res = "res://" + mp3.resolve().relative_to(PROJECT).as_posix()
        text = (f'[remap]\n\nimporter="mp3"\ntype="AudioStreamMP3"\n\n[deps]\n\nsource_file="{res}"\n\n[params]\n\n'
                + "".join(f"{k}={v}\n" for k, v in params.items()))
    path.write_text(text)


def generate():
    lame, ffmpeg = shutil.which("lame"), shutil.which("ffmpeg")
    if lame is None or ffmpeg is None:
        raise MusicError("lame and ffmpeg are needed on PATH to encode (Homebrew: brew install lame ffmpeg)")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    lock = {}
    with tempfile.TemporaryDirectory() as tmp:
        for name, (pcm, samples) in render_all().items():
            wav = Path(tmp) / f"{name}.wav"
            with wave.open(str(wav), "wb") as w:
                w.setnchannels(1)
                w.setsampwidth(2)
                w.setframerate(RATE)
                w.writeframes(pcm)
            mp3 = OUT_DIR / f"{name}.mp3"
            # CBR, no ID3 tags. Keep the LAME tag (no -t): it makes the decoded file one loop long.
            result = subprocess.run([lame, "--quiet", "-m", "m", "-b", "96", "--noreplaygain", str(wav), str(mp3)],
                                    capture_output=True, text=True)
            if result.returncode != 0:
                raise MusicError(f"lame failed for {mp3}: {result.stderr.strip()}")
            check_decode(ffmpeg, mp3, samples)
            write_import(mp3)
            lock[name] = lock_entry(pcm, samples, mp3)
            print(f"music: wrote {mp3.relative_to(ROOT)} ({samples / RATE:.3f}s loop, {samples} samples, {mp3.stat().st_size} bytes)")
    for path in sorted(OUT_DIR.glob("*.mp3")):
        if path.stem not in lock:
            raise MusicError(f"{path.relative_to(ROOT)} is stale: no track makes it any more; delete it and its .import")
    LOCK.write_text(json.dumps(lock, indent=2) + "\n")
    print(f"music: wrote {LOCK.relative_to(ROOT)}")


def main():
    try:
        if sys.argv[1:] == ["--check"]:
            check()
        elif not sys.argv[1:]:
            generate()
        else:
            print(__doc__, file=sys.stderr)
            return 2
    except MusicError as e:
        print(f"music: error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
