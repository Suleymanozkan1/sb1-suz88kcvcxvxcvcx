#!/usr/bin/env python3
"""Procedural sound bank for FLUX DROP.

Synthesises every sound effect, music loop and stinger used by the game from
scratch (oscillators, hashed noise, envelopes and simple filters; no samples
and no third-party audio) and writes 22050 Hz mono 16-bit PCM WAV files:

  game/assets/audio/sfx/<kind>.wav            one-shot effects, 0.05-1.5 s
  game/assets/audio/music/<world>.wav         base loop (drums + bass + pad), 8 bars
  game/assets/audio/music/<world>_hi.wav      intensity stem (arps + hats), same length
  game/assets/audio/music/<world>_boss.wav    faster, heavier boss loop, 8 bars
  game/assets/audio/music/menu.wav            calm ambient loop, 8 bars
  game/assets/audio/music/level_complete.wav  stinger
  game/assets/audio/music/perfect_fanfare.wav stinger

Tempo, scale and root note of every world loop are read from
game/data/worlds/*.json so music always matches the level data. Loops are
rendered into a circular buffer (tails wrap to the start), which makes them
seamless, and carry a RIFF "smpl" chunk so Godot imports them as looping.

Output is deterministic: noise comes from a counter-based hash and every
"random" choice is seeded from a name, so the same inputs give byte-identical
files on the same platform. --verify regenerates in memory and compares with
the files on disk.

Usage:
  python3 tools/audio/synth_bank.py              # write every file
  python3 tools/audio/synth_bank.py --only sfx   # or: --only music
  python3 tools/audio/synth_bank.py --verify     # exit 1 if any file differs
  python3 tools/audio/synth_bank.py --hashes     # print sha256 per file
"""
from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
import zlib
from pathlib import Path
from typing import Callable

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / "game"
SFX_DIR = GAME / "assets" / "audio" / "sfx"
MUSIC_DIR = GAME / "assets" / "audio" / "music"
WORLDS_DIR = GAME / "data" / "worlds"

SR = 22050
PEAK_DBFS = -1.0
PEAK = 10.0 ** (PEAK_DBFS / 20.0)
FADE_IN_S = 0.002
FADE_OUT_S = 0.012
MAX_HARMONICS = 40
SFX_MIN_S = 0.05
SFX_MAX_S = 1.5

BARS = 8
STEPS_PER_BAR = 16
BEATS_PER_BAR = 4
BOSS_TEMPO_FACTOR = 1.125
BASS_FLOOR_MIDI = 33
PAD_FLOOR_MIDI = 52
ARP_FLOOR_MIDI = 69

MENU = {"bpm": 76, "root_midi": 57, "scale": "dorian"}
STINGER_ROOT_MIDI = 60

SCALES: dict[str, list[int]] = {
    "major": [0, 2, 4, 5, 7, 9, 11],
    "minor_pentatonic": [0, 3, 5, 7, 10],
    "major_pentatonic": [0, 2, 4, 7, 9],
    "dorian": [0, 2, 3, 5, 7, 9, 10],
    "phrygian": [0, 1, 3, 5, 7, 8, 10],
    "aeolian": [0, 2, 3, 5, 7, 8, 10],
    "mixolydian": [0, 2, 4, 5, 7, 9, 10],
    "lydian": [0, 2, 4, 6, 7, 9, 11],
    "harmonic_minor": [0, 2, 3, 5, 7, 8, 11],
    "locrian": [0, 1, 3, 5, 6, 8, 10],
}

# ---------------------------------------------------------------------------
# Per-world arrangement. Patterns are 16 steps per bar:
#   drums: X accent, x hit, g ghost, . rest      hats: x closed, o open
#   bass:  r root, o octave, t 2nd chord tone, f 3rd chord tone, - hold, . rest
# ---------------------------------------------------------------------------
STYLES: dict[str, dict] = {
    "neon_core": {
        "swing": 0.0, "chord_bars": 1, "prog": [0, 0, 4, 4, 1, 1, 3, 4],
        "kit": {"kick_f0": 150, "kick_f1": 47, "kick_sweep": 0.04, "kick_decay": 0.30, "kick_click": 0.5,
                "kick_drive": 1.6, "snare_tone": 185, "snare_lo": 900, "snare_hi": 7000, "snare_decay": 0.15,
                "clap": 0.8, "hat_cut": 7000, "hat_decay": 0.035, "metal": 0.4, "perc": "tom"},
        "kick": "X...x...X...x...", "snare": "....x.......x...", "hat": "..x...x...x...x.",
        "perc": "..............x.", "fill": "....x.......x.xx",
        "bass": {"shape": "saw", "pattern": "r.r.o.r.r.r.o.r.", "cutoff": 380, "env": 1400, "fdecay": 0.08,
                 "decay": 0.5, "reso": 0.6, "drive": 1.3, "level": 0.62},
        "pad": {"shape": "saw", "detune": 9, "cutoff": 1500, "sidechain": 0.6, "level": 0.30, "space": 0.35},
        "arp": {"shape": "square", "order": "up", "rate": 16, "decay": 0.11, "cutoff": 3200, "echo": 0.35,
                "span": 2, "level": 0.55},
        "hi_hats": {"closed": "x.xxx.xxx.xxx.xx", "open": "..o...o...o...o.", "shaker": ""},
    },
    "crystal_valley": {
        "swing": 0.0, "chord_bars": 1, "prog": [0, 3, 0, 3, 6, 6, 4, 4],
        "kit": {"kick_f0": 120, "kick_f1": 52, "kick_sweep": 0.03, "kick_decay": 0.24, "kick_click": 0.3,
                "kick_drive": 1.0, "snare_tone": 420, "snare_lo": 1800, "snare_hi": 9000, "snare_decay": 0.06,
                "clap": 0.0, "hat_cut": 8500, "hat_decay": 0.025, "metal": 0.7, "perc": "shaker"},
        "kick": "X.....x...x.....", "snare": "....x.......x...", "hat": "x.x.x.x.x.x.x.x.",
        "perc": ".x.x.x.x.x.x.x.x", "fill": "....x.......x.x.",
        "bass": {"shape": "tri", "pattern": "r..r..r...r.f...", "cutoff": 1200, "env": 600, "fdecay": 0.1,
                 "decay": 0.35, "reso": 0.0, "drive": 1.0, "level": 0.7},
        "pad": {"shape": "glass", "detune": 4, "cutoff": 2600, "sidechain": 0.0, "level": 0.34, "space": 0.55},
        "arp": {"shape": "bell", "order": "updown", "rate": 16, "decay": 0.18, "cutoff": 5000, "echo": 0.4,
                "span": 2, "level": 0.5},
        "hi_hats": {"closed": "", "open": "......o.......o.", "shaker": "xxxxxxxxxxxxxxxx"},
    },
    "molten_grid": {
        "swing": 0.0, "chord_bars": 1, "prog": [0, 0, 1, 1, 0, 0, 6, 1],
        "kit": {"kick_f0": 180, "kick_f1": 42, "kick_sweep": 0.05, "kick_decay": 0.36, "kick_click": 0.7,
                "kick_drive": 3.0, "snare_tone": 160, "snare_lo": 600, "snare_hi": 5000, "snare_decay": 0.22,
                "clap": 0.6, "hat_cut": 6000, "hat_decay": 0.04, "metal": 0.9, "perc": "metal"},
        "kick": "X..x..x...x..x..", "snare": "....X.......X...", "hat": "x.x.x.x.x.x.x.x.",
        "perc": ".......x.......x", "fill": "....X.......X.xx",
        "bass": {"shape": "square", "pattern": "rrr.rr.rrr.r.rr.", "cutoff": 300, "env": 900, "fdecay": 0.06,
                 "decay": 0.3, "reso": 0.9, "drive": 3.0, "level": 0.6},
        "pad": {"shape": "saw", "detune": 14, "cutoff": 700, "sidechain": 0.3, "level": 0.26, "space": 0.3,
                "octave": -12},
        "arp": {"shape": "saw", "order": "down", "rate": 8, "decay": 0.16, "cutoff": 2400, "echo": 0.25,
                "span": 2, "level": 0.5, "drive": 2.0},
        "hi_hats": {"closed": "xxxxxxxxxxxxxxxx", "open": "", "shaker": ""},
    },
    "cloud_factory": {
        "swing": 0.18, "chord_bars": 1, "prog": [0, 0, 3, 3, 1, 1, 4, 4],
        "kit": {"kick_f0": 130, "kick_f1": 55, "kick_sweep": 0.03, "kick_decay": 0.2, "kick_click": 0.2,
                "kick_drive": 1.0, "snare_tone": 260, "snare_lo": 1500, "snare_hi": 8000, "snare_decay": 0.08,
                "clap": 0.9, "hat_cut": 7500, "hat_decay": 0.03, "metal": 0.3, "perc": "tom"},
        "kick": "X.......x.x.....", "snare": "....x.......x...", "hat": "x.x.x.x.x.x.x.x.",
        "perc": "......x.......x.", "fill": "....x.......xxx.",
        "bass": {"shape": "square", "pattern": "r...o...r...o.f.", "cutoff": 900, "env": 700, "fdecay": 0.05,
                 "decay": 0.12, "reso": 0.2, "drive": 1.0, "level": 0.6},
        "pad": {"shape": "tri", "detune": 6, "cutoff": 3000, "sidechain": 0.0, "level": 0.34, "space": 0.3},
        "arp": {"shape": "pulse25", "order": "pingpong", "rate": 12, "decay": 0.09, "cutoff": 4000, "echo": 0.2,
                "span": 2, "level": 0.5},
        "hi_hats": {"closed": "x.x.x.x.x.x.x.x.", "open": "", "shaker": "..x...x...x...x."},
    },
    "deep_ocean": {
        "swing": 0.0, "chord_bars": 2, "prog": [0, 5, 2, 6],
        "kit": {"kick_f0": 110, "kick_f1": 40, "kick_sweep": 0.05, "kick_decay": 0.5, "kick_click": 0.1,
                "kick_drive": 1.0, "snare_tone": 150, "snare_lo": 400, "snare_hi": 3000, "snare_decay": 0.3,
                "clap": 0.0, "hat_cut": 6500, "hat_decay": 0.05, "metal": 0.2, "perc": "bubble"},
        "kick": "X.........x.....", "snare": "........x.......", "hat": "..x...x...x...x.",
        "perc": ".....x.....x..x.", "fill": "........x.....x.",
        "bass": {"shape": "sub", "pattern": "r-------r---f---", "cutoff": 400, "env": 200, "fdecay": 0.2,
                 "decay": 3.0, "reso": 0.0, "drive": 1.2, "level": 0.75},
        "pad": {"shape": "saw", "detune": 18, "cutoff": 1100, "sidechain": 0.0, "level": 0.42, "space": 0.65,
                "tremolo": 0.25},
        "arp": {"shape": "sine", "order": "seeded", "rate": 8, "decay": 0.3, "cutoff": 3000, "echo": 0.55,
                "span": 2, "level": 0.6},
        "hi_hats": {"closed": "x.x.x.x.x.x.x.x.", "open": "", "shaker": "...x.......x...."},
    },
    "cyber_garden": {
        "swing": 0.08, "chord_bars": 1, "prog": [0, 0, 6, 6, 3, 3, 0, 6],
        "kit": {"kick_f0": 140, "kick_f1": 50, "kick_sweep": 0.035, "kick_decay": 0.27, "kick_click": 0.4,
                "kick_drive": 1.3, "snare_tone": 200, "snare_lo": 1000, "snare_hi": 7500, "snare_decay": 0.12,
                "clap": 1.0, "hat_cut": 7500, "hat_decay": 0.03, "metal": 0.5, "perc": "rim"},
        "kick": "X...x...X...x...", "snare": "....x.......x...", "hat": ".x.x.x.x.x.x.x.x",
        "perc": "..x..x....x..x..", "fill": "....x.......x.x.",
        "bass": {"shape": "saw", "pattern": "r..r..o..r.r.f..", "cutoff": 250, "env": 2200, "fdecay": 0.07,
                 "decay": 0.25, "reso": 1.2, "drive": 1.4, "level": 0.6},
        "pad": {"shape": "organ", "detune": 3, "cutoff": 2400, "sidechain": 0.4, "level": 0.24, "space": 0.3},
        "arp": {"shape": "marimba", "order": "updown", "rate": 16, "decay": 0.12, "cutoff": 4500, "echo": 0.25,
                "span": 2, "level": 0.55},
        "hi_hats": {"closed": "x.xxx.xxx.xxx.xx", "open": "..o...o...o...o.", "shaker": ""},
    },
    "frozen_pulse": {
        "swing": 0.0, "chord_bars": 1, "prog": [0, 1, 0, 1, 4, 4, 1, 1],
        "kit": {"kick_f0": 160, "kick_f1": 50, "kick_sweep": 0.04, "kick_decay": 0.28, "kick_click": 0.6,
                "kick_drive": 1.6, "snare_tone": 220, "snare_lo": 1500, "snare_hi": 9000, "snare_decay": 0.1,
                "clap": 0.7, "hat_cut": 9000, "hat_decay": 0.02, "metal": 0.6, "perc": ""},
        "kick": "X...x...X...x...", "snare": "....x.......x...", "hat": "..x...x...x...x.",
        "perc": "", "fill": "....x.......xxxx",
        "bass": {"shape": "saw", "pattern": ".rrr.rrr.rrr.rrr", "cutoff": 600, "env": 1500, "fdecay": 0.05,
                 "decay": 0.12, "reso": 0.5, "drive": 1.2, "level": 0.55},
        "pad": {"shape": "tri", "detune": 6, "cutoff": 4000, "sidechain": 0.7, "level": 0.32, "space": 0.5,
                "octave": 12},
        "arp": {"shape": "glass", "order": "up", "rate": 16, "decay": 0.14, "cutoff": 6000, "echo": 0.3,
                "span": 3, "level": 0.5},
        "hi_hats": {"closed": "xxxxxxxxxxxxxxxx", "open": "", "shaker": ""},
    },
    "desert_reactor": {
        "swing": 0.05, "chord_bars": 1, "prog": [0, 0, 5, 5, 3, 3, 4, 4],
        "kit": {"kick_f0": 135, "kick_f1": 48, "kick_sweep": 0.04, "kick_decay": 0.3, "kick_click": 0.3,
                "kick_drive": 1.4, "snare_tone": 200, "snare_lo": 800, "snare_hi": 6000, "snare_decay": 0.14,
                "clap": 0.5, "hat_cut": 7000, "hat_decay": 0.03, "metal": 0.3, "perc": "tom"},
        "kick": "X..x....x..x....", "snare": "....x.......x..x", "hat": "x.x.x.x.x.x.x.x.",
        "perc": "..x..x.x..x...x.", "fill": "....x.....x.xxxx",
        "bass": {"shape": "tri", "pattern": "r..r..r.r..r.f.r", "cutoff": 900, "env": 900, "fdecay": 0.06,
                 "decay": 0.3, "reso": 0.3, "drive": 1.6, "level": 0.65},
        "pad": {"shape": "reed", "detune": 7, "cutoff": 1800, "sidechain": 0.2, "level": 0.24, "space": 0.4},
        "arp": {"shape": "pulse25", "order": "seeded", "rate": 16, "decay": 0.1, "cutoff": 3500, "echo": 0.25,
                "span": 2, "level": 0.5, "vibrato": 0.18, "gate": "xx.xx.x.xx.x.xx."},
        "hi_hats": {"closed": "", "open": "", "shaker": "x.xxx.xxx.xxx.xx"},
    },
    "void_space": {
        "swing": 0.0, "chord_bars": 1, "prog": [0, 0, 1, 1, 5, 5, 4, 4],
        "kit": {"kick_f0": 120, "kick_f1": 38, "kick_sweep": 0.05, "kick_decay": 0.4, "kick_click": 0.4,
                "kick_drive": 2.0, "snare_tone": 180, "snare_lo": 1000, "snare_hi": 8000, "snare_decay": 0.18,
                "clap": 0.0, "hat_cut": 8000, "hat_decay": 0.02, "metal": 0.5, "perc": "zap"},
        "kick": "X.........x.x...", "snare": "....x..g....x...", "hat": "x.x.x.x.x.x.x.x.",
        "perc": "...........x....", "fill": "....x..g....x.xx",
        "bass": {"shape": "fm", "pattern": "r-------r---r---", "cutoff": 500, "env": 400, "fdecay": 0.3,
                 "decay": 2.0, "reso": 0.0, "drive": 1.8, "level": 0.7},
        "pad": {"shape": "saw", "detune": 22, "cutoff": 600, "sidechain": 0.0, "level": 0.3, "space": 0.7},
        "arp": {"shape": "glass", "order": "seeded", "rate": 8, "decay": 0.2, "cutoff": 5000, "echo": 0.5,
                "span": 3, "level": 0.5, "gate": "x..x.x..x...x.x."},
        "hi_hats": {"closed": "xxxxxxxxxxxxxxxx", "open": "", "shaker": ""},
    },
    "candy_reactor": {
        "swing": 0.0, "chord_bars": 2, "prog": [0, 4, 5, 3],
        "kit": {"kick_f0": 170, "kick_f1": 52, "kick_sweep": 0.035, "kick_decay": 0.25, "kick_click": 0.6,
                "kick_drive": 2.0, "snare_tone": 230, "snare_lo": 1200, "snare_hi": 8000, "snare_decay": 0.1,
                "clap": 1.0, "hat_cut": 8000, "hat_decay": 0.025, "metal": 0.4, "perc": ""},
        "kick": "X...x...X...x...", "snare": "....x.......x...", "hat": "..x...x...x...x.",
        "perc": "", "fill": "....x...x.x.xxxx",
        "bass": {"shape": "square", "pattern": "r.o.r.o.r.o.r.o.", "cutoff": 1200, "env": 900, "fdecay": 0.04,
                 "decay": 0.1, "reso": 0.2, "drive": 1.0, "level": 0.55},
        "pad": {"shape": "saw", "detune": 10, "cutoff": 2600, "sidechain": 0.5, "level": 0.28, "space": 0.3},
        "arp": {"shape": "square", "order": "updown", "rate": 16, "decay": 0.08, "cutoff": 5000, "echo": 0.2,
                "span": 2, "level": 0.5},
        "hi_hats": {"closed": "x.xxx.xxx.xxx.xx", "open": "..o...o...o...o.", "shaker": ""},
    },
}

BOSS = {
    "kick": "X...x..xX...x.x.", "snare": "....X.......X...", "fill": "....X.....x.XXXX",
    "hat": "xxxxxxxxxxxxxxxx", "bass": "rrorrrorrrorrfro", "stab": "x..x..x...x..x..",
}


# ---------------------------------------------------------------------------
# DSP primitives
# ---------------------------------------------------------------------------
def ns(seconds: float) -> int:
    return max(1, int(round(seconds * SR)))


def t_axis(n: int) -> np.ndarray:
    return np.arange(n, dtype=np.float64) / SR


def hz(midi: float) -> float:
    return 440.0 * 2.0 ** ((midi - 69.0) / 12.0)


def seed_of(name: str) -> int:
    return zlib.crc32(name.encode("utf-8"))


def noise(n: int, seed: int) -> np.ndarray:
    """Counter-based splitmix64 noise in [-1, 1): independent of numpy's RNG streams."""
    mask = (1 << 64) - 1
    offset = (seed * 0x9E3779B97F4A7C15) & mask
    with np.errstate(over="ignore"):
        z = np.arange(n, dtype=np.uint64) + np.uint64(offset)
        z = z + np.uint64(0x9E3779B97F4A7C15)
        z = (z ^ (z >> np.uint64(30))) * np.uint64(0xBF58476D1CE4E5B9)
        z = (z ^ (z >> np.uint64(27))) * np.uint64(0x94D049BB133111EB)
        z = z ^ (z >> np.uint64(31))
    return (z >> np.uint64(11)).astype(np.float64) / float(1 << 53) * 2.0 - 1.0


def hash_unit(name: str, i: int) -> float:
    """Deterministic value in [0, 1) for choice number i of a named decision."""
    return float(noise(1, seed_of(f"{name}#{i}"))[0] * 0.5 + 0.5)


def env_exp(n: int, attack: float, decay: float) -> np.ndarray:
    t = t_axis(n)
    rise = np.clip(t / max(attack, 1e-4), 0.0, 1.0)
    return rise * np.exp(-np.maximum(t - attack, 0.0) / max(decay, 1e-4))


def env_points(n: int, points: list[tuple[float, float]]) -> np.ndarray:
    ts = np.array([p[0] for p in points], dtype=np.float64)
    vs = np.array([p[1] for p in points], dtype=np.float64)
    return np.interp(t_axis(n), ts, vs)


def gate_env(n: int, attack: float, hold: float, release: float, decay: float = 1e9) -> np.ndarray:
    """Attack, exponential decay while held, linear release after [hold] seconds."""
    t = t_axis(n)
    rise = np.clip(t / max(attack, 1e-4), 0.0, 1.0)
    body = np.exp(-np.maximum(t - attack, 0.0) / decay)
    tail = np.clip(1.0 - (t - hold) / max(release, 1e-4), 0.0, 1.0)
    return rise * body * np.where(t < hold, 1.0, tail)


def sweep(f0: float, f1: float, n: int, curve: str = "exp") -> np.ndarray:
    x = np.linspace(0.0, 1.0, n, endpoint=False)
    if curve == "exp":
        return f0 * (f1 / f0) ** x
    return f0 + (f1 - f0) * x


def phase_of(freq: float | np.ndarray, n: int) -> np.ndarray:
    f = np.broadcast_to(np.asarray(freq, dtype=np.float64), (n,))
    ph = np.empty(n, dtype=np.float64)
    ph[0] = 0.0
    np.cumsum(f[:-1], out=ph[1:])
    return ph * (2.0 * np.pi / SR)


def lp_gain(fh: np.ndarray | float, cutoff: np.ndarray | float, reso: float) -> np.ndarray | float:
    ratio = np.maximum(np.asarray(fh, dtype=np.float64) / np.maximum(cutoff, 1.0), 1e-6)
    g = 1.0 / np.sqrt(1.0 + ratio ** 4)
    if reso > 0.0:
        g = g * (1.0 + reso * np.exp(-(np.log2(ratio) ** 2) / 0.045))
    return g


def harmonic_amps(shape: str, k: int) -> float:
    if shape == "saw":
        return 1.0 / k
    if shape == "square":
        return 1.0 / k if k % 2 == 1 else 0.0
    if shape == "tri":
        return ((-1.0) ** ((k - 1) // 2)) / (k * k) if k % 2 == 1 else 0.0
    if shape == "pulse25":
        return abs(np.sin(np.pi * k * 0.25)) / k
    if shape == "organ":
        return {1: 1.0, 2: 0.8, 3: 0.6, 4: 0.5, 6: 0.35, 8: 0.25}.get(k, 0.0)
    if shape == "reed":
        return (1.0 / k) * (1.0 if k % 2 == 1 else 0.35)
    raise ValueError(f"unknown shape {shape}")


SHAPE_NORM = {"saw": 0.55, "square": 0.75, "tri": 0.81, "pulse25": 0.6, "organ": 0.3, "reed": 0.6}


def osc(shape: str, freq: float | np.ndarray, n: int, cutoff: float | np.ndarray | None = None,
        reso: float = 0.0) -> np.ndarray:
    """Band-limited additive oscillator with an optional (time-varying) low-pass response."""
    f = np.broadcast_to(np.asarray(freq, dtype=np.float64), (n,))
    ph = phase_of(f, n)
    if shape == "sine":
        return np.sin(ph)
    fmax = float(np.max(f))
    kmax = int(max(1, min(MAX_HARMONICS, (SR * 0.45) // max(fmax, 1.0))))
    out = np.zeros(n, dtype=np.float64)
    for k in range(1, kmax + 1):
        a = harmonic_amps(shape, k)
        if a == 0.0:
            continue
        if cutoff is None:
            out += a * np.sin(k * ph)
            continue
        g = lp_gain(k * f, cutoff, reso)
        if float(np.max(g)) < 2e-3:
            break
        out += a * g * np.sin(k * ph)
    return out * SHAPE_NORM[shape]


def fm(freq: float | np.ndarray, n: int, ratio: float, index: float | np.ndarray) -> np.ndarray:
    ph = phase_of(freq, n)
    return np.sin(ph + np.asarray(index) * np.sin(ph * ratio))


def drive(x: np.ndarray, amount: float) -> np.ndarray:
    if amount <= 1.0:
        return x
    return np.tanh(x * amount) / np.tanh(amount)


def spectral(x: np.ndarray, lo: float, hi: float, circular: bool = False) -> np.ndarray:
    """Zero-phase band filter in the frequency domain (circular for loops, padded otherwise)."""
    n = len(x)
    size = n if circular else n * 2
    spec = np.fft.rfft(x, size)
    f = np.fft.rfftfreq(size, 1.0 / SR)
    g = np.ones_like(f)
    if lo > 0.0:
        g *= 1.0 / np.sqrt(1.0 + (lo / np.maximum(f, 1e-3)) ** 4)
    if hi < SR / 2:
        g *= 1.0 / np.sqrt(1.0 + (f / hi) ** 4)
    return np.fft.irfft(spec * g, size)[:n]


def svf(x: np.ndarray, cutoff: np.ndarray | float, q: float, mode: str) -> np.ndarray:
    """Time-varying TPT state-variable filter (sample loop; used on short one-shots only)."""
    n = len(x)
    fc = np.clip(np.broadcast_to(np.asarray(cutoff, dtype=np.float64), (n,)), 20.0, SR * 0.45)
    g = np.tan(np.pi * fc / SR)
    k = 1.0 / q
    a1 = 1.0 / (1.0 + g * (g + k))
    a2 = g * a1
    a3 = g * a2
    out = np.empty(n, dtype=np.float64)
    ic1 = 0.0
    ic2 = 0.0
    xs = x.tolist()
    a1l = a1.tolist()
    a2l = a2.tolist()
    a3l = a3.tolist()
    for i in range(n):
        v3 = xs[i] - ic2
        v1 = a1l[i] * ic1 + a2l[i] * v3
        v2 = ic2 + a2l[i] * ic1 + a3l[i] * v3
        ic1 = 2.0 * v1 - ic1
        ic2 = 2.0 * v2 - ic2
        if mode == "lp":
            out[i] = v2
        elif mode == "bp":
            out[i] = v1 * k
        else:
            out[i] = xs[i] - k * v1 - v2
    return out


def place(buf: np.ndarray, sound: np.ndarray, pos: int, gain: float = 1.0, circular: bool = True) -> None:
    n = len(buf)
    pos %= n if circular else max(n, 1)
    if not circular:
        end = min(n, pos + len(sound))
        buf[pos:end] += sound[: end - pos] * gain
        return
    offset = 0
    remaining = len(sound)
    while remaining > 0:
        take = min(remaining, n - pos)
        buf[pos:pos + take] += sound[offset:offset + take] * gain
        offset += take
        remaining -= take
        pos = 0


def echo(x: np.ndarray, delay_s: float, feedback: float, taps: int, circular: bool) -> np.ndarray:
    d = ns(delay_s)
    out = np.zeros_like(x)
    for i in range(1, taps + 1):
        g = feedback ** i
        if circular:
            out += np.roll(x, i * d) * g
        elif i * d < len(x):
            out[i * d:] += x[: len(x) - i * d] * g
    return out


SPACE_TAPS_MS = [23, 31, 41, 53, 67, 79, 97, 113, 137, 157, 181, 211, 241, 277]


def space(x: np.ndarray, size: float, circular: bool, name: str) -> np.ndarray:
    """Cheap diffuse reverb: decaying multi-tap echoes with seeded polarity, then darkened."""
    out = np.zeros_like(x)
    for i, ms in enumerate(SPACE_TAPS_MS):
        d = ns(ms * size / 1000.0)
        g = (0.72 ** (i * 0.6)) * (1.0 if hash_unit(name, i) > 0.5 else -1.0) * 0.35
        if circular:
            out += np.roll(x, d) * g
        elif d < len(x):
            out[d:] += x[: len(x) - d] * g
    return spectral(out, 120.0, 3800.0, circular)


def normalize(x: np.ndarray, peak: float = PEAK) -> np.ndarray:
    m = float(np.max(np.abs(x)))
    if m <= 1e-9:
        return x
    return x * (peak / m)


def finish_oneshot(x: np.ndarray) -> np.ndarray:
    x = spectral(x, 25.0, SR / 2, circular=False)
    x = x - float(np.mean(x))
    fi = min(ns(FADE_IN_S), len(x) // 4)
    fo = min(ns(FADE_OUT_S), len(x) // 3)
    x[:fi] *= np.linspace(0.0, 1.0, fi, endpoint=False)
    x[len(x) - fo:] *= 0.5 + 0.5 * np.cos(np.linspace(0.0, np.pi, fo))
    return normalize(x)


def finish_loop(x: np.ndarray) -> np.ndarray:
    x = spectral(x, 25.0, SR / 2, circular=True)
    return normalize(x)


# ---------------------------------------------------------------------------
# Instruments
# ---------------------------------------------------------------------------
def bell(freq: float, dur: float, ratio: float = 3.5, index: float = 1.4, decay: float = 0.3) -> np.ndarray:
    n = ns(dur)
    idx = index * env_exp(n, 0.0005, decay * 0.5)
    return fm(freq, n, ratio, idx) * env_exp(n, 0.002, decay)


def kick(kit: dict, name: str) -> np.ndarray:
    n = ns(kit["kick_decay"] * 2.2 + 0.05)
    t = t_axis(n)
    f = kit["kick_f1"] + (kit["kick_f0"] - kit["kick_f1"]) * np.exp(-t / kit["kick_sweep"])
    body = np.sin(phase_of(f, n)) * env_exp(n, 0.001, kit["kick_decay"])
    click = spectral(noise(n, seed_of(name + "kc")) * env_exp(n, 0.0003, 0.004), 1500.0, 8000.0)
    return drive(body + click * kit["kick_click"], kit["kick_drive"])


def snare(kit: dict, name: str) -> np.ndarray:
    n = ns(kit["snare_decay"] * 3.0 + 0.03)
    tone_f = kit["snare_tone"]
    tone = (np.sin(phase_of(tone_f, n)) + 0.5 * np.sin(phase_of(tone_f * 1.72, n))) * env_exp(n, 0.001, 0.05)
    nz = spectral(noise(n, seed_of(name + "sn")), kit["snare_lo"], kit["snare_hi"])
    out = tone * 0.6 + nz * env_exp(n, 0.001, kit["snare_decay"]) * 1.4
    if kit.get("clap", 0.0) > 0.0:
        cl = clap(name)
        if len(cl) > n:
            out = np.concatenate([out, np.zeros(len(cl) - n)])
        place(out, cl, 0, kit["clap"], circular=False)
    return out


def clap(name: str) -> np.ndarray:
    n = ns(0.3)
    t = t_axis(n)
    env = np.zeros(n)
    for i, start in enumerate((0.0, 0.011, 0.022)):
        env += np.where(t >= start, np.exp(-np.maximum(t - start, 0.0) / (0.006 if i < 2 else 0.09)), 0.0)
    return spectral(noise(n, seed_of(name + "cl")), 900.0, 5000.0) * env * 1.2


def hat(kit: dict, name: str, open_hat: bool) -> np.ndarray:
    decay = kit["hat_decay"] * (6.0 if open_hat else 1.0)
    n = ns(decay * 4.0 + 0.01)
    nz = noise(n, seed_of(name + ("ho" if open_hat else "hc")))
    metal = np.zeros(n)
    for r in (2.0, 3.0, 4.16, 5.43, 6.79, 8.21):
        metal += np.sign(np.sin(phase_of(205.3 * r, n)))
    mix = nz + metal * 0.12 * kit.get("metal", 0.4)
    return spectral(mix, kit["hat_cut"], SR / 2) * env_exp(n, 0.0005, decay)


TOM_HZ = (180.0, 140.0, 110.0)


def perc(kind: str, name: str, step: int, tune: Callable[[float], float] | None = None) -> np.ndarray:
    if kind == "tom":
        f0 = TOM_HZ[step % len(TOM_HZ)]
        f0 = tune(f0) if tune is not None else f0
        n = ns(0.35)
        f = f0 * (1.0 + 0.6 * np.exp(-t_axis(n) / 0.02))
        return np.sin(phase_of(f, n)) * env_exp(n, 0.001, 0.12)
    if kind == "shaker":
        n = ns(0.08)
        return spectral(noise(n, seed_of(name + f"sh{step}")), 4000.0, 10000.0) * env_points(
            n, [(0.0, 0.0), (0.012, 1.0), (0.08, 0.0)]) * 0.5
    if kind == "metal":
        n = ns(0.4)
        return (fm(320.0, n, 2.76, 3.0 * env_exp(n, 0.0005, 0.08)) * env_exp(n, 0.0005, 0.12)
                + spectral(noise(n, seed_of(name + "mt")), 3000.0, 9000.0) * env_exp(n, 0.0005, 0.02))
    if kind == "rim":
        n = ns(0.06)
        return (np.sin(phase_of(1700.0, n)) * 0.6 + np.sin(phase_of(450.0, n))) * env_exp(n, 0.0003, 0.012)
    if kind == "bubble":
        n = ns(0.09)
        f = sweep(300.0 + 200.0 * hash_unit(name, step), 1100.0, n)
        return np.sin(phase_of(f, n)) * env_exp(n, 0.002, 0.03) * 0.8
    if kind == "zap":
        n = ns(0.18)
        return osc("saw", sweep(1800.0, 120.0, n), n, cutoff=3000.0) * env_exp(n, 0.001, 0.06)
    raise ValueError(f"unknown perc {kind}")


def crash(name: str, dur: float = 1.6) -> np.ndarray:
    n = ns(dur)
    return spectral(noise(n, seed_of(name + "cr")), 3500.0, 10500.0) * env_exp(n, 0.002, dur * 0.35)


def note_voice(shape: str, midi: float, dur: float, decay: float, cutoff: float, reso: float = 0.0,
               env_amt: float = 0.0, fdecay: float = 0.1, release: float = 0.03, vibrato: float = 0.0,
               attack: float = 0.003) -> np.ndarray:
    n = ns(dur + release)
    t = t_axis(n)
    f0 = hz(midi)
    freq: float | np.ndarray = f0
    if vibrato > 0.0:
        freq = f0 * (1.0 + vibrato * 0.03 * np.sin(2.0 * np.pi * 5.5 * t) * np.clip(t / 0.15, 0.0, 1.0))
    amp = gate_env(n, attack, dur, release, decay)
    if shape == "sine":
        return np.sin(phase_of(freq, n)) * amp
    if shape == "sub":
        ph = phase_of(freq, n)
        return (np.sin(ph) + 0.28 * np.sin(2.0 * ph) + 0.1 * np.sin(3.0 * ph)) * amp
    if shape == "fm":
        idx = 1.2 + 1.8 * np.exp(-t / fdecay)
        return fm(freq, n, 1.0, idx) * amp
    if shape == "bell":
        return fm(freq, n, 3.5, 1.6 * np.exp(-t / (decay * 0.4))) * amp
    if shape == "marimba":
        return fm(freq, n, 4.0, 2.2 * np.exp(-t / 0.02)) * amp
    if shape == "glass":
        return (fm(freq, n, 7.0, 0.7 * np.exp(-t / (decay * 0.5))) + 0.4 * np.sin(phase_of(f0 * 2.0, n))) * amp
    cut = cutoff + env_amt * np.exp(-t / fdecay) if env_amt > 0.0 else cutoff
    return osc(shape, freq, n, cutoff=cut, reso=reso) * amp


def pad_voice(shape: str, midi: float, dur: float, detune: float, cutoff: float, name: str,
              release: float = 0.6) -> np.ndarray:
    n = ns(dur + release)
    attack = min(0.35 * dur, 0.6)
    amp = gate_env(n, attack, dur, release)
    out = np.zeros(n)
    if shape == "glass":
        for cents in (-detune, detune):
            f = hz(midi + cents / 100.0)
            out += fm(f, n, 2.0, 0.6) * 0.5 + np.sin(phase_of(f * 2.0, n)) * 0.2
        return out * amp
    for i, cents in enumerate((-detune, detune * 0.4, detune)):
        f = hz(midi + cents / 100.0)
        vib = 1.0 + 0.002 * np.sin(2.0 * np.pi * (0.3 + 0.17 * i) * t_axis(n) + 6.28 * hash_unit(name, i))
        out += osc(shape, f * vib, n, cutoff=cutoff) * (0.5 if i == 1 else 0.4)
    return out * amp


# ---------------------------------------------------------------------------
# Music
# ---------------------------------------------------------------------------
def register(root: int, floor: int) -> int:
    r = root
    while r >= floor + 12:
        r -= 12
    while r < floor:
        r += 12
    return r


def degree_midi(scale: list[int], base: int, deg: int) -> int:
    octave, idx = divmod(deg, len(scale))
    return base + 12 * octave + scale[idx]


def chord_degrees(scale: list[int], deg: int, size: int = 3) -> list[int]:
    steps = (0, 2, 4, 6) if len(scale) >= 7 else (0, 1, 3, 5)
    return [deg + s for s in steps[:size]]


class Loop:
    """A fixed-length circular buffer addressed in 16th-note steps."""

    def __init__(self, bpm: float, bars: int = BARS, swing: float = 0.0) -> None:
        self.bpm = bpm
        self.bars = bars
        self.swing = swing
        self.step_s = 60.0 / bpm / 4.0
        self.n = int(round(bars * STEPS_PER_BAR * self.step_s * SR))
        self.buf = np.zeros(self.n, dtype=np.float64)

    @property
    def steps(self) -> int:
        return self.bars * STEPS_PER_BAR

    def pos(self, step: float) -> int:
        t = step * self.step_s
        if self.swing > 0.0 and float(step).is_integer() and int(step) % 2 == 1:
            t += self.swing * self.step_s
        return int(round(t * SR))

    def add(self, sound: np.ndarray, step: float, gain: float = 1.0) -> None:
        place(self.buf, sound, self.pos(step), gain, circular=True)


def velocity(ch: str) -> float:
    return {"X": 1.0, "x": 0.78, "o": 0.78, "g": 0.32}.get(ch, 0.0)


def lay_pattern(loop: Loop, pattern: str, sound_for: Callable[[int], np.ndarray], gain: float,
                fill: str = "") -> list[int]:
    hits: list[int] = []
    if not pattern:
        return hits
    for bar in range(loop.bars):
        pat = fill if fill and bar % 4 == 3 else pattern
        for i, ch in enumerate(pat):
            v = velocity(ch)
            if v <= 0.0:
                continue
            step = bar * STEPS_PER_BAR + i
            vel = v
            if fill and bar % 4 == 3 and i >= 12:
                vel *= 0.6 + 0.1 * (i - 12)
            loop.add(sound_for(step), step, gain * vel)
            hits.append(loop.pos(step))
    return hits


def sidechain(n: int, hits: list[int], depth: float, release_s: float = 0.11) -> np.ndarray:
    if depth <= 0.0 or not hits:
        return np.ones(n)
    pos = np.array(sorted(set(hits)), dtype=np.int64)
    idx = np.arange(n, dtype=np.int64)
    which = np.searchsorted(pos, idx, side="right") - 1
    last = np.where(which >= 0, pos[np.maximum(which, 0)], pos[-1] - n)
    dt = (idx - last) / SR
    return 1.0 - depth * np.exp(-dt / release_s)


def chord_at(style: dict, bar: int) -> int:
    prog = style["prog"]
    return prog[(bar // style["chord_bars"]) % len(prog)]


def scale_tuner(scale: list[int], root: int) -> Callable[[float], float]:
    """Snaps a frequency to the nearest note of the world's scale (tuned drums)."""
    pcs = {(root + s) % 12 for s in scale}

    def tune(freq: float) -> float:
        midi = 69.0 + 12.0 * np.log2(freq / 440.0)
        best = min((m for m in range(int(midi) - 6, int(midi) + 7) if m % 12 in pcs), key=lambda m: abs(m - midi))
        return hz(best)

    return tune


def render_drums(loop: Loop, style: dict, name: str, boss: bool, tune: Callable[[float], float]) \
        -> tuple[np.ndarray, list[int]]:
    kit = dict(style["kit"])
    kit["snare_tone"] = tune(kit["snare_tone"])
    kit["kick_f1"] = tune(kit["kick_f1"])
    k = kick(kit, name)
    s = snare(kit, name)
    hc = hat(kit, name, False)
    ho = hat(kit, name, True)
    drums = Loop(loop.bpm, loop.bars, loop.swing)
    kick_pat = BOSS["kick"] if boss else style["kick"]
    hits = lay_pattern(drums, kick_pat, lambda _s: k, 1.0)
    lay_pattern(drums, BOSS["snare"] if boss else style["snare"], lambda _s: s, 0.8,
                fill=BOSS["fill"] if boss else style["fill"])
    hat_pat = BOSS["hat"] if boss else style["hat"]
    lay_pattern(drums, hat_pat.replace("o", "x"), lambda _s: hc, 0.22)
    if style["perc"] and kit.get("perc"):
        lay_pattern(drums, style["perc"], lambda st: perc(kit["perc"], name, st, tune), 0.42)
    if boss:
        drums.add(crash(name), 0, 0.5)
        drums.add(crash(name + "b"), 4 * STEPS_PER_BAR, 0.35)
        lay_pattern(drums, "..o...o...o...o.", lambda _s: ho, 0.18)
    return drums.buf, hits


def render_bass(loop: Loop, style: dict, scale: list[int], root: int, boss: bool) -> np.ndarray:
    b = style["bass"]
    base = register(root, BASS_FLOOR_MIDI)
    pattern = BOSS["bass"] if boss else b["pattern"]
    shape = b["shape"]
    drive_amt = b["drive"] * (2.2 if boss else 1.0)
    if boss and shape in ("sine", "sub", "tri"):
        shape = "saw"
    out = Loop(loop.bpm, loop.bars, loop.swing)
    for bar in range(loop.bars):
        chord = chord_degrees(scale, chord_at(style, bar))
        i = 0
        while i < STEPS_PER_BAR:
            ch = pattern[i]
            if ch in ".-":
                i += 1
                continue
            length = 1
            while i + length < STEPS_PER_BAR and pattern[i + length] == "-":
                length += 1
            deg = chord[0]
            shift = 0
            if ch == "o":
                shift = 12
            elif ch == "t":
                deg = chord[1]
            elif ch == "f":
                deg = chord[2]
            midi = degree_midi(scale, base, deg) + shift
            dur = length * loop.step_s * (0.92 if length > 1 else 0.8)
            v = note_voice(shape, midi, dur, b["decay"], b["cutoff"] * (1.4 if boss else 1.0), b["reso"],
                           b["env"], b["fdecay"])
            out.add(drive(v, drive_amt), bar * STEPS_PER_BAR + i, 1.0)
            i += length
    return out.buf


def render_pad(loop: Loop, style: dict, scale: list[int], root: int, name: str) -> np.ndarray:
    p = style["pad"]
    base = register(root, PAD_FLOOR_MIDI) + p.get("octave", 0)
    out = Loop(loop.bpm, loop.bars, loop.swing)
    bars_per = style["chord_bars"]
    seg = bars_per * STEPS_PER_BAR * loop.step_s
    for bar in range(0, loop.bars, bars_per):
        for j, deg in enumerate(chord_degrees(scale, chord_at(style, bar), 4 if p["shape"] != "glass" else 3)):
            midi = degree_midi(scale, base, deg)
            v = pad_voice(p["shape"], midi, seg, p["detune"], p["cutoff"], f"{name}{bar}{j}")
            out.add(v, bar * STEPS_PER_BAR, 0.6 if j == 3 else 1.0)
    buf = out.buf
    if p.get("tremolo", 0.0) > 0.0:
        beats = loop.bars * BEATS_PER_BAR
        ph = np.arange(loop.n) / loop.n * 2.0 * np.pi * (beats / 2)
        buf = buf * (1.0 - p["tremolo"] * (0.5 + 0.5 * np.sin(ph)))
    if p.get("space", 0.0) > 0.0:
        buf = buf + space(buf, 1.6, True, name + "pad") * p["space"] * 2.0
    return buf


def arp_sequence(style: dict, scale: list[int], bar: int, count: int, name: str) -> list[int]:
    a = style["arp"]
    chord = chord_degrees(scale, chord_at(style, bar))
    tones: list[int] = []
    for octave in range(a["span"]):
        tones.extend(d + octave * len(scale) for d in chord)
    order = a["order"]
    if order == "down":
        tones = tones[::-1]
    elif order in ("updown", "pingpong"):
        tones = tones + tones[-2:0:-1]
    if order == "seeded":
        return [tones[int(hash_unit(f"{name}arp{bar}", i) * len(tones))] for i in range(count)]
    return [tones[i % len(tones)] for i in range(count)]


def render_arp(loop: Loop, style: dict, scale: list[int], root: int, name: str) -> np.ndarray:
    a = style["arp"]
    base = register(root, ARP_FLOOR_MIDI) + a.get("octave", 0)
    out = Loop(loop.bpm, loop.bars, 0.0 if a["rate"] == 12 else loop.swing)
    per_bar = a["rate"]
    step_unit = STEPS_PER_BAR / per_bar
    gate = a.get("gate", "")
    for bar in range(loop.bars):
        seq = arp_sequence(style, scale, bar, per_bar, name)
        for i, deg in enumerate(seq):
            step = bar * STEPS_PER_BAR + i * step_unit
            if gate and per_bar == 16 and gate[i] != "x":
                continue
            if gate and per_bar == 8 and gate[i * 2] != "x":
                continue
            accent = 1.0 if i % 4 == 0 else 0.72
            v = note_voice(a["shape"], degree_midi(scale, base, deg), loop.step_s * step_unit * 0.7, a["decay"],
                           a["cutoff"], 0.3, 0.0, 0.1, 0.02, a.get("vibrato", 0.0))
            v = drive(v, a.get("drive", 1.0))
            place(out.buf, v, int(round(step * loop.step_s * SR)), accent, circular=True)
    buf = out.buf
    if a.get("echo", 0.0) > 0.0:
        buf = buf + spectral(echo(buf, loop.step_s * 3.0, a["echo"], 4, True), 200.0, 4000.0, True)
    return buf


def world_loop(world: dict, style: dict, stem: str) -> np.ndarray:
    music = world["music"]
    scale = SCALES[music["scale"]]
    root = int(music["root_midi"])
    name = f"{world['id']}_{stem}"
    if stem == "boss":
        bpm = boss_bpm(int(music["bpm"]))
        loop = Loop(bpm, BARS, 0.0)
        drums, hits = render_drums(loop, style, name, True, scale_tuner(scale, root))
        bass = render_bass(loop, style, scale, root, True)
        stabs = render_stabs(loop, style, scale, root, name)
        siren = render_siren(loop, style, scale, root)
        duck = sidechain(loop.n, hits, 0.45)
        mix = drums * 1.0 + bass * style["bass"]["level"] * 0.9 * duck + stabs * 0.3 * duck + siren * 0.16
        return finish_loop(mix)
    loop = Loop(float(music["bpm"]), BARS, style["swing"])
    if stem == "base":
        drums, hits = render_drums(loop, style, name, False, scale_tuner(scale, root))
        bass = render_bass(loop, style, scale, root, False)
        pad = render_pad(loop, style, scale, root, name)
        duck = sidechain(loop.n, hits, style["pad"]["sidechain"])
        bass_duck = sidechain(loop.n, hits, 0.35 if style["bass"]["shape"] in ("sub", "fm", "sine") else 0.0)
        mix = drums + bass * style["bass"]["level"] * bass_duck + pad * style["pad"]["level"] * duck
        return finish_loop(mix)
    arp = render_arp(loop, style, scale, root, name)
    hats = render_hi_hats(loop, style, name)
    return finish_loop(arp * style["arp"]["level"] + hats * 0.5)


def render_hi_hats(loop: Loop, style: dict, name: str) -> np.ndarray:
    kit = style["kit"]
    h = style["hi_hats"]
    out = Loop(loop.bpm, loop.bars, loop.swing)
    hc = hat(kit, name + "hi", False)
    ho = hat(kit, name + "hi", True)
    if h["closed"]:
        accents = "Xxgx"
        for bar in range(loop.bars):
            for i, ch in enumerate(h["closed"]):
                if ch == "x":
                    out.add(hc, bar * STEPS_PER_BAR + i, velocity(accents[i % 4]) * 0.5)
    if h["open"]:
        lay_pattern(out, h["open"], lambda _s: ho, 0.45)
    if h["shaker"]:
        lay_pattern(out, h["shaker"], lambda st: perc("shaker", name, st), 0.7)
    return out.buf


def render_stabs(loop: Loop, style: dict, scale: list[int], root: int, name: str) -> np.ndarray:
    base = register(root, PAD_FLOOR_MIDI)
    out = Loop(loop.bpm, loop.bars, 0.0)
    for bar in range(loop.bars):
        chord = chord_degrees(scale, chord_at(style, bar), 3)
        for i, ch in enumerate(BOSS["stab"]):
            if ch != "x":
                continue
            for j, deg in enumerate(chord):
                v = note_voice("saw", degree_midi(scale, base, deg), loop.step_s * 1.5, 0.15, 900.0, 0.8, 2000.0,
                               0.05)
                out.add(drive(v, 2.5), bar * STEPS_PER_BAR + i, 0.5 if j else 0.7)
    return out.buf + space(out.buf, 1.0, True, name + "stab") * 0.5


def render_siren(loop: Loop, style: dict, scale: list[int], root: int) -> np.ndarray:
    base = register(root, ARP_FLOOR_MIDI) - 12
    n = loop.n
    t = np.arange(n) / SR
    bar_s = STEPS_PER_BAR * loop.step_s
    midi = np.zeros(n)
    for bar in range(loop.bars):
        chord = chord_degrees(scale, chord_at(style, bar))
        lo = degree_midi(scale, base, chord[0])
        mask = (t >= bar * bar_s) & (t < (bar + 1) * bar_s)
        local = (t[mask] - bar * bar_s) / bar_s
        midi[mask] = lo + 12.0 * np.clip(local * 1.5, 0.0, 1.0) - (1.0 if bar % 2 else 0.0) * local
    midi = np.convolve(np.concatenate([midi[-400:], midi, midi[:400]]), np.ones(801) / 801.0, "same")[400:-400]
    freq = 440.0 * 2.0 ** ((midi - 69.0) / 12.0)
    beats = loop.bars * BEATS_PER_BAR
    trem = 0.75 + 0.25 * np.sin(2.0 * np.pi * beats * 2 * np.arange(n) / n)
    return osc("saw", freq, n, cutoff=1600.0, reso=0.6) * trem


def boss_bpm(bpm: int) -> int:
    return int(bpm * BOSS_TEMPO_FACTOR + 0.5)


def menu_loop() -> np.ndarray:
    scale = SCALES[MENU["scale"]]
    root = MENU["root_midi"]
    style = {"prog": [0, 6, 3, 4], "chord_bars": 2,
             "arp": {"order": "seeded", "span": 2, "rate": 8}}
    loop = Loop(MENU["bpm"], BARS, 0.0)
    pad = render_pad(loop, {**style, "pad": {"shape": "saw", "detune": 14, "cutoff": 1000, "space": 0.7,
                                             "tremolo": 0.2}}, scale, root, "menu")
    sub = Loop(loop.bpm, loop.bars)
    base = register(root, BASS_FLOOR_MIDI)
    for bar in range(0, BARS, 2):
        midi = degree_midi(scale, base, chord_at(style, bar))
        sub.add(note_voice("sub", midi, 2 * STEPS_PER_BAR * loop.step_s, 8.0, 400.0, release=0.4,
                           attack=0.3), bar * STEPS_PER_BAR)
    plucks = Loop(loop.bpm, loop.bars)
    gate = "x..x..x.x..x...."
    arp_base = register(root, ARP_FLOOR_MIDI)
    for bar in range(BARS):
        seq = arp_sequence(style, scale, bar, 16, "menu")
        for i, ch in enumerate(gate):
            if ch == "x":
                v = note_voice("tri", degree_midi(scale, arp_base, seq[i]), loop.step_s, 0.35, 2500.0)
                plucks.add(v, bar * STEPS_PER_BAR + i, 0.6 if i else 0.85)
    sparkle = plucks.buf + echo(plucks.buf, loop.step_s * 3.0, 0.45, 4, True) + space(plucks.buf, 2.0, True,
                                                                                         "menupl") * 1.2
    for bar in (0, 4):
        sparkle_note = bell(hz(degree_midi(scale, arp_base + 12, 4)), 2.0, 3.5, 0.8, 0.8)
        place(sparkle, sparkle_note, loop.pos(bar * STEPS_PER_BAR), 0.25)
    return finish_loop(pad * 0.5 + sub.buf * 0.55 + sparkle * 0.5)


def stinger(perfect: bool) -> np.ndarray:
    root = STINGER_ROOT_MIDI
    dur = 3.2 if perfect else 2.3
    n = ns(dur)
    out = np.zeros(n)
    if perfect:
        steps = [0, 4, 7, 12, 16, 19, 24]
        for i, s in enumerate(steps):
            v = note_voice("saw", root + s, 0.16, 0.4, 2600.0, 0.4, 1500.0, 0.08, 0.06)
            place(out, v, ns(i * 0.075), 0.55, circular=False)
        hit = ns(0.6)
        for s, lvl in ((0, 0.7), (4, 0.55), (7, 0.55), (12, 0.5), (16, 0.35)):
            v = pad_voice("saw", root + s, 1.6, 12, 2400.0, f"fan{s}", 0.9)
            place(out, v * env_exp(len(v), 0.01, 1.4), hit, lvl, circular=False)
        shimmer = np.zeros(n)
        for i in range(10):
            f = hz(root + 24 + [0, 4, 7, 12, 16][int(hash_unit("fanfare", i) * 5)])
            place(shimmer, bell(f, 0.8, 3.5, 1.0, 0.3), ns(0.6 + i * 0.09), 0.3, circular=False)
        out += shimmer
        place(out, crash("fanfare", 2.4), hit, 0.3, circular=False)
    else:
        steps = [0, 7, 12, 16]
        for i, s in enumerate(steps):
            place(out, bell(hz(root + 12 + s), 0.9, 2.0, 1.2, 0.35), ns(i * 0.09), 0.6, circular=False)
        hit = ns(0.4)
        for s, lvl in ((0, 0.6), (4, 0.5), (7, 0.5), (11, 0.3)):
            v = pad_voice("tri", root + s, 1.2, 8, 3000.0, f"cmp{s}", 0.7)
            place(out, v * env_exp(len(v), 0.02, 1.0), hit, lvl, circular=False)
    out = out + space(out, 1.4, False, "stinger" + str(perfect)) * 0.6
    return finish_oneshot(out)


# ---------------------------------------------------------------------------
# Sound effects
# ---------------------------------------------------------------------------
def sfx_tap() -> np.ndarray:
    n = ns(0.09)
    f = sweep(900.0, 1500.0, n)
    tone = (np.sin(phase_of(f, n)) * 0.7 + osc("square", f, n, cutoff=4000.0) * 0.3) * env_exp(n, 0.001, 0.03)
    click = spectral(noise(n, seed_of("tap")), 3000.0, 8000.0) * env_exp(n, 0.0003, 0.002)
    return tone + click * 0.4


def sfx_phase() -> np.ndarray:
    n = ns(0.2)
    t = t_axis(n)
    a = np.sin(phase_of(sweep(600.0, 900.0, n), n))
    b = np.sin(phase_of(sweep(900.0, 1350.0, n), n))
    trem = 0.6 + 0.4 * np.sin(2.0 * np.pi * 40.0 * t)
    shimmer = fm(1800.0, n, 1.5, 0.8 * env_exp(n, 0.001, 0.05)) * 0.25
    return (a * 0.6 + b * 0.5 + shimmer) * trem * env_exp(n, 0.004, 0.07)


def sfx_dash() -> np.ndarray:
    n = ns(0.32)
    whoosh = svf(noise(n, seed_of("dash")), sweep(600.0, 5000.0, n), 2.5, "bp")
    whoosh *= env_points(n, [(0.0, 0.0), (0.04, 1.0), (0.2, 0.5), (0.32, 0.0)])
    thump = np.sin(phase_of(sweep(90.0, 50.0, n), n)) * env_exp(n, 0.002, 0.08)
    return whoosh * 1.2 + thump * 0.9


def sfx_denied() -> np.ndarray:
    n = ns(0.16)
    t = t_axis(n)
    gate = (((t >= 0.0) & (t < 0.06)) | ((t >= 0.08) & (t < 0.14))).astype(np.float64)
    gate = np.convolve(gate, np.ones(40) / 40.0, "same")
    return osc("square", 140.0, n, cutoff=1200.0) * gate


def sfx_surge() -> np.ndarray:
    n = ns(0.32)
    f = sweep(70.0, 220.0, n)
    body = osc("saw", f, n, cutoff=sweep(300.0, 2500.0, n), reso=0.7)
    sub = np.sin(phase_of(f * 0.5, n))
    env = env_points(n, [(0.0, 0.0), (0.18, 1.0), (0.26, 0.7), (0.32, 0.0)])
    return (body + sub * 0.6) * env


def sfx_collect() -> np.ndarray:
    n = ns(0.26)
    t = t_axis(n)
    f = hz(81)
    return (fm(f, n, 2.0, 1.5 * np.exp(-t / 0.03)) + 0.3 * np.sin(phase_of(f * 2.0, n))) * env_exp(n, 0.001, 0.08)


def sfx_prism() -> np.ndarray:
    n = ns(0.7)
    out = np.zeros(n)
    for i, m in enumerate((81, 85, 88, 93)):
        place(out, bell(hz(m), 0.6, 3.5, 0.9, 0.3), ns(i * 0.025), 0.7 - i * 0.1, circular=False)
    sparkle = spectral(noise(n, seed_of("prism")), 6000.0, 10500.0) * env_exp(n, 0.005, 0.12) * 0.2
    return out + sparkle


def sfx_miss() -> np.ndarray:
    n = ns(0.16)
    return np.sin(phase_of(sweep(520.0, 300.0, n), n)) * env_exp(n, 0.003, 0.06)


def sfx_near_miss() -> np.ndarray:
    n = ns(0.38)
    t = t_axis(n)
    whoosh = svf(noise(n, seed_of("near")), sweep(2000.0, 6000.0, n), 3.0, "bp")
    whoosh *= env_points(n, [(0.0, 0.0), (0.03, 1.0), (0.15, 0.2), (0.38, 0.0)])
    f = sweep(1800.0, 2600.0, n) * (1.0 + 0.01 * np.sin(2.0 * np.pi * 30.0 * t))
    zing = np.sin(phase_of(f, n)) * env_exp(n, 0.004, 0.12)
    return whoosh * 1.3 + zing * 0.6


def glass(n: int, name: str, lo: float, hi: float, count: int, decay: float) -> np.ndarray:
    out = np.zeros(n)
    for i in range(count):
        f = lo + (hi - lo) * hash_unit(name, i)
        d = decay * (0.4 + 0.8 * hash_unit(name, i + 100))
        start = ns(0.03 * hash_unit(name, i + 200))
        tone = np.sin(phase_of(f, n - start)) * env_exp(n - start, 0.0005, d)
        out[start:] += tone / count * 2.0
    return out


def sfx_shatter() -> np.ndarray:
    n = ns(0.55)
    t = t_axis(n)
    out = glass(n, "shatter", 1800.0, 7000.0, 10, 0.12)
    burst = np.zeros(n)
    for start in (0.0, 0.018, 0.04):
        burst += np.where(t >= start, np.exp(-np.maximum(t - start, 0.0) / 0.03), 0.0)
    out += spectral(noise(n, seed_of("shat")), 2000.0, 10000.0) * burst * 0.5
    out += spectral(noise(n, seed_of("crunch")), 60.0, 800.0) * env_exp(n, 0.001, 0.05) * 0.8
    return out


def sfx_chain() -> np.ndarray:
    n = ns(0.26)
    out = glass(n, "chain", 2500.0, 8000.0, 6, 0.06)
    out += spectral(noise(n, seed_of("chain")), 3000.0, 10000.0) * env_exp(n, 0.0005, 0.02) * 0.6
    return out


def sfx_gate() -> np.ndarray:
    n = ns(0.32)
    tone = (np.sin(phase_of(hz(84), n)) + 0.7 * np.sin(phase_of(hz(91), n))) * env_exp(n, 0.005, 0.15)
    air = spectral(noise(n, seed_of("gate")), 4000.0, 8000.0) * env_points(
        n, [(0.0, 0.0), (0.06, 1.0), (0.32, 0.0)])
    return tone * 0.6 + air * 0.5


def sfx_shield_break() -> np.ndarray:
    n = ns(0.65)
    t = t_axis(n)
    impact = spectral(noise(n, seed_of("shield")), 80.0, 3000.0) * env_exp(n, 0.0005, 0.08)
    thump = np.sin(phase_of(sweep(120.0, 40.0, n), n)) * env_exp(n, 0.001, 0.15)
    fall = drive(fm(sweep(900.0, 200.0, n), n, 1.41, 2.0 * np.exp(-t / 0.2)), 2.5) * env_exp(n, 0.003, 0.2)
    return impact * 0.8 + thump + fall * 0.5 + glass(n, "shieldg", 2000.0, 6000.0, 6, 0.1) * 0.5


def sfx_bump() -> np.ndarray:
    n = ns(0.16)
    thud = np.sin(phase_of(sweep(110.0, 60.0, n), n)) * env_exp(n, 0.001, 0.05)
    soft = spectral(noise(n, seed_of("bump")), 40.0, 600.0) * env_exp(n, 0.001, 0.02)
    return thud + soft * 0.6


def sfx_fail() -> np.ndarray:
    n = ns(1.25)
    f = sweep(440.0, 55.0, n)
    fall = drive(osc("saw", f, n, cutoff=sweep(4000.0, 300.0, n), reso=0.5), 2.0) * env_exp(n, 0.003, 0.45)
    boom = np.sin(phase_of(sweep(70.0, 30.0, n), n)) * env_exp(n, 0.002, 0.5)
    crash_n = spectral(noise(n, seed_of("fail")), 100.0, 5000.0) * env_exp(n, 0.001, 0.35)
    return fall * 0.6 + boom + crash_n * 0.5


def sfx_perfect() -> np.ndarray:
    n = ns(1.3)
    out = np.zeros(n)
    for i, m in enumerate((84, 88, 91, 96)):
        place(out, bell(hz(m), 0.9, 2.0, 1.0, 0.3), ns(i * 0.07), 0.6, circular=False)
    chord = np.zeros(n)
    for m in (72, 76, 79, 84):
        place(chord, pad_voice("tri", m, 0.6, 8, 4000.0, f"perf{m}", 0.6), 0, 1.0, circular=False)
    out += chord * env_exp(n, 0.02, 0.6) * 0.35
    out += spectral(noise(n, seed_of("perfect")), 6000.0, 10500.0) * env_exp(n, 0.2, 0.3) * 0.15
    return out


def sfx_complete() -> np.ndarray:
    n = ns(0.95)
    out = np.zeros(n)
    place(out, bell(hz(79), 0.5, 2.0, 1.0, 0.18), 0, 0.6, circular=False)
    place(out, bell(hz(84), 0.8, 2.0, 1.0, 0.3), ns(0.12), 0.7, circular=False)
    chord = np.zeros(n)
    for m in (72, 76, 79):
        v = pad_voice("tri", m, 0.4, 6, 3500.0, f"cmp{m}", 0.4)
        place(chord, v, ns(0.12), 0.3, circular=False)
    return out + chord * env_exp(n, 0.0, 0.5)


def sfx_form() -> np.ndarray:
    n = ns(0.48)
    t = t_axis(n)
    idx = 2.0 + 1.5 * np.sin(2.0 * np.pi * 6.0 * t)
    swirl = fm(sweep(300.0, 900.0, n), n, 1.5, idx) * env_points(n, [(0.0, 0.0), (0.05, 1.0), (0.3, 0.6),
                                                                  (0.48, 0.0)])
    chorus = fm(sweep(303.0, 909.0, n), n, 1.5, idx) * 0.5 * env_points(n, [(0.0, 0.0), (0.08, 1.0), (0.48, 0.0)])
    air = svf(noise(n, seed_of("form")), sweep(800.0, 4000.0, n), 2.0, "bp") * env_exp(n, 0.05, 0.12)
    return swirl * 0.6 + chorus * 0.4 + air * 0.6


def sfx_portal() -> np.ndarray:
    n = ns(0.65)
    t = t_axis(n)
    f = env_points(n, [(0.0, 400.0), (0.3, 1200.0), (0.65, 500.0)])
    vib = 1.0 + (0.01 + 0.04 * t / 0.65) * np.sin(2.0 * np.pi * 14.0 * t)
    a = np.sin(phase_of(f * vib, n))
    b = np.sin(phase_of(f * vib * 1.007, n))
    sparkle = spectral(noise(n, seed_of("portal")), 5000.0, 10000.0) * env_exp(n, 0.1, 0.15) * 0.3
    return (a + b) * 0.5 * env_points(n, [(0.0, 0.0), (0.04, 1.0), (0.5, 0.6), (0.65, 0.0)]) + sparkle


def sfx_current() -> np.ndarray:
    n = ns(0.42)
    t = t_axis(n)
    cut = env_points(n, [(0.0, 800.0), (0.2, 2400.0), (0.42, 1200.0)])
    flow = svf(noise(n, seed_of("current")), cut, 1.8, "bp") * env_points(
        n, [(0.0, 0.0), (0.1, 1.0), (0.3, 0.7), (0.42, 0.0)])
    hum = np.sin(phase_of(160.0, n)) * (0.6 + 0.4 * np.sin(2.0 * np.pi * 9.0 * t)) * env_exp(n, 0.03, 0.15)
    return flow * 1.4 + hum * 0.4


def sfx_pickup() -> np.ndarray:
    n = ns(0.32)
    out = np.zeros(n)
    for i, m in enumerate((79, 83, 88)):
        v = note_voice("pulse25", m, 0.06, 0.1, 5000.0, release=0.04)
        place(out, v, ns(i * 0.07), 0.8, circular=False)
    tail = bell(hz(88), 0.18, 2.0, 0.6, 0.08)
    place(out, tail, ns(0.14), 0.4, circular=False)
    return out


def sfx_overdrive() -> np.ndarray:
    n = ns(1.1)
    rise_n = ns(0.6)
    out = np.zeros(n)
    f = sweep(200.0, 800.0, rise_n)
    riser = sum(osc("saw", f * r, rise_n, cutoff=sweep(400.0, 6000.0, rise_n)) for r in (1.0, 1.005, 0.995))
    riser = riser * env_points(rise_n, [(0.0, 0.0), (0.55, 1.0), (0.6, 0.8)])
    noise_rise = spectral(noise(rise_n, seed_of("od")), 2000.0, 9000.0) * np.linspace(0.0, 0.6, rise_n)
    place(out, riser * 0.35 + noise_rise, 0, 1.0, circular=False)
    stab = np.zeros(n - rise_n)
    for m in (57, 61, 64, 69):
        place(stab, note_voice("saw", m, 0.3, 0.35, 2500.0, 0.5, 2000.0, 0.08, 0.15), 0, 1.0, circular=False)
    boom = np.sin(phase_of(sweep(90.0, 40.0, n - rise_n), n - rise_n)) * env_exp(n - rise_n, 0.001, 0.2)
    place(out, drive(stab * 0.4, 1.8) + boom, rise_n, 1.0, circular=False)
    return out


def sfx_overdrive_end() -> np.ndarray:
    n = ns(0.55)
    f = sweep(600.0, 80.0, n)
    return osc("square", f, n, cutoff=sweep(4000.0, 200.0, n)) * env_exp(n, 0.002, 0.2)


def sfx_combo() -> np.ndarray:
    n = ns(0.16)
    t = t_axis(n)
    f = 1100.0 + 150.0 * np.clip(t / 0.015, 0.0, 1.0)
    return (np.sin(phase_of(f, n)) * 0.7 + osc("tri", f, n) * 0.3) * env_exp(n, 0.001, 0.06)


def sfx_ui_click() -> np.ndarray:
    n = ns(0.06)
    tone = np.sin(phase_of(2200.0, n)) * env_exp(n, 0.0003, 0.008)
    click = spectral(noise(n, seed_of("ui")), 2000.0, 9000.0) * env_exp(n, 0.0002, 0.001)
    return tone + click * 0.5


def sfx_ui_back() -> np.ndarray:
    n = ns(0.09)
    out = np.zeros(n)
    for i, f in enumerate((1600.0, 1100.0)):
        m = ns(0.05)
        place(out, np.sin(phase_of(f, m)) * env_exp(m, 0.0003, 0.012), ns(i * 0.035), 0.8 - 0.2 * i,
              circular=False)
    return out


def sfx_reward() -> np.ndarray:
    n = ns(0.85)
    out = np.zeros(n)
    notes = [84, 86, 88, 91, 93, 96, 98, 100]
    for i in range(8):
        m = notes[int(hash_unit("reward", i) * len(notes))] if i % 2 else notes[i]
        place(out, bell(hz(m), 0.4, 3.5, 0.8, 0.15), ns(i * 0.05), 0.5, circular=False)
    out += spectral(noise(n, seed_of("reward")), 6000.0, 10500.0) * env_exp(n, 0.1, 0.25) * 0.15
    return out


def sfx_star() -> np.ndarray:
    n = ns(0.65)
    ding = bell(hz(93), 0.65, 3.01, 1.2, 0.35)
    octave = np.sin(phase_of(hz(105), n)) * env_exp(n, 0.002, 0.2) * 0.25
    sparkle = spectral(noise(n, seed_of("star")), 7000.0, 10500.0) * env_exp(n, 0.01, 0.1) * 0.2
    return ding + octave + sparkle


def sfx_coin() -> np.ndarray:
    n = ns(0.32)
    out = np.zeros(n)
    first = ns(0.06)
    place(out, osc("square", hz(83), first, cutoff=5000.0), 0, 0.5, circular=False)
    m = n - first
    place(out, osc("square", hz(88), m, cutoff=5000.0) * env_exp(m, 0.0, 0.1), first, 0.5, circular=False)
    return out


def sfx_level_up() -> np.ndarray:
    n = ns(1.25)
    out = np.zeros(n)
    for i, m in enumerate((72, 76, 79, 84, 88, 91)):
        place(out, note_voice("pulse25", m, 0.07, 0.2, 5000.0, release=0.05), ns(i * 0.08), 0.6, circular=False)
    hit = ns(0.5)
    for m in (72, 76, 79, 84):
        v = pad_voice("saw", m, 0.4, 10, 3000.0, f"lvl{m}", 0.3)
        place(out, v * env_exp(len(v), 0.005, 0.35), hit, 0.35, circular=False)
    return out


def sfx_unlock() -> np.ndarray:
    n = ns(0.75)
    out = np.zeros(n)
    clunk_n = ns(0.12)
    clunk = (spectral(noise(clunk_n, seed_of("unlock")), 60.0, 900.0) + np.sin(phase_of(200.0, clunk_n))) \
        * env_exp(clunk_n, 0.0005, 0.04)
    place(out, clunk, 0, 0.9, circular=False)
    click = spectral(noise(ns(0.02), seed_of("unlockc")), 2500.0, 9000.0) * env_exp(ns(0.02), 0.0002, 0.003)
    place(out, click, ns(0.06), 0.6, circular=False)
    place(out, bell(hz(88), 0.6, 2.0, 1.0, 0.25), ns(0.12), 0.5, circular=False)
    place(out, bell(hz(95), 0.55, 2.0, 1.0, 0.22), ns(0.16), 0.4, circular=False)
    return out


def sfx_launch() -> np.ndarray:
    # A pad springs: a rising pneumatic push under a bright upward chirp.
    n = ns(0.38)
    t = t_axis(n)
    push = svf(noise(n, seed_of("launch")), sweep(300.0, 2600.0, n), 1.8, "bp")
    push *= env_points(n, [(0.0, 0.0), (0.03, 1.0), (0.16, 0.45), (0.38, 0.0)])
    chirp = np.sin(phase_of(sweep(220.0, 880.0, n), n)) * np.exp(-t / 0.12)
    thump = np.sin(phase_of(sweep(140.0, 60.0, n), n)) * env_exp(n, 0.001, 0.05)
    return push * 0.9 + chirp * 0.5 + thump * 0.8


def sfx_land() -> np.ndarray:
    # Touch-down: a short, damped floor thud with a little grit.
    n = ns(0.2)
    thud = np.sin(phase_of(sweep(95.0, 48.0, n), n)) * env_exp(n, 0.001, 0.06)
    grit = spectral(noise(n, seed_of("land")), 120.0, 1600.0) * env_exp(n, 0.0005, 0.025)
    return thud + grit * 0.5


def sfx_gravity() -> np.ndarray:
    # Entering a gravity well: a slow pitch bend through a resonant hum.
    n = ns(0.6)
    t = t_axis(n)
    f = 90.0 + 30.0 * np.sin(2.0 * np.pi * 1.6 * t)
    hum = osc("saw", f, n, cutoff=sweep(400.0, 1400.0, n), reso=0.6)
    sub = np.sin(phase_of(f * 0.5, n))
    env = env_points(n, [(0.0, 0.0), (0.12, 1.0), (0.4, 0.6), (0.6, 0.0)])
    return (hum * 0.7 + sub * 0.6) * env


def sfx_plate() -> np.ndarray:
    # A ballast plate settles on the stack: a dull metallic clank.
    n = ns(0.3)
    t = t_axis(n)
    clank = fm(hz(57), n, 2.76, 2.2 * np.exp(-t / 0.03)) * env_exp(n, 0.0005, 0.07)
    body = np.sin(phase_of(hz(45), n)) * env_exp(n, 0.001, 0.05)
    return clank * 0.8 + body * 0.6


def sfx_stack_crash() -> np.ndarray:
    # A full stack drives through glass: heavy impact under the shatter.
    n = ns(0.55)
    impact = np.sin(phase_of(sweep(110.0, 38.0, n), n)) * env_exp(n, 0.0008, 0.14)
    crunch = spectral(noise(n, seed_of("stack_crash")), 200.0, 4000.0) * env_exp(n, 0.0005, 0.06)
    return impact + crunch * 0.6 + glass(n, "stackg", 1800.0, 6500.0, 7, 0.08) * 0.45


SFX: dict[str, Callable[[], np.ndarray]] = {
    "tap": sfx_tap, "phase": sfx_phase, "dash": sfx_dash, "denied": sfx_denied, "surge": sfx_surge,
    "collect": sfx_collect, "prism": sfx_prism, "miss": sfx_miss, "near_miss": sfx_near_miss,
    "shatter": sfx_shatter, "chain": sfx_chain, "gate": sfx_gate, "shield_break": sfx_shield_break,
    "bump": sfx_bump, "fail": sfx_fail, "perfect": sfx_perfect, "complete": sfx_complete, "form": sfx_form,
    "portal": sfx_portal, "current": sfx_current, "pickup": sfx_pickup, "overdrive": sfx_overdrive,
    "overdrive_end": sfx_overdrive_end, "combo": sfx_combo, "ui_click": sfx_ui_click, "ui_back": sfx_ui_back,
    "reward": sfx_reward, "star": sfx_star, "coin": sfx_coin, "level_up": sfx_level_up, "unlock": sfx_unlock,
    "launch": sfx_launch, "land": sfx_land, "gravity": sfx_gravity, "plate": sfx_plate,
    "stack_crash": sfx_stack_crash,
}


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
def wav_bytes(samples: np.ndarray, loop: bool) -> bytes:
    pcm = np.clip(np.round(samples * 32767.0), -32768, 32767).astype("<i2").tobytes()
    chunks = struct.pack("<4sIHHIIHH", b"fmt ", 16, 1, 1, SR, SR * 2, 2, 16)
    if loop:
        frames = len(samples)
        chunks += struct.pack("<4sI9I", b"smpl", 36 + 24, 0, 0, int(round(1e9 / SR)), 60, 0, 0, 0, 1, 0)
        chunks += struct.pack("<6I", 0, 0, 0, frames, 0, 0)
    chunks += struct.pack("<4sI", b"data", len(pcm)) + pcm
    body = b"WAVE" + chunks
    return struct.pack("<4sI", b"RIFF", len(body)) + body


def load_worlds() -> list[dict]:
    index = json.loads((WORLDS_DIR / "index.json").read_text(encoding="utf-8"))
    worlds = []
    for entry in index["worlds"]:
        worlds.append(json.loads((WORLDS_DIR / entry["file"]).read_text(encoding="utf-8")))
    return worlds


def render_sfx() -> dict[Path, bytes]:
    out: dict[Path, bytes] = {}
    for kind, fn in SFX.items():
        x = finish_oneshot(fn())
        dur = len(x) / SR
        if not SFX_MIN_S <= dur <= SFX_MAX_S:
            raise ValueError(f"sfx {kind} has length {dur:.3f}s outside [{SFX_MIN_S}, {SFX_MAX_S}]")
        out[SFX_DIR / f"{kind}.wav"] = wav_bytes(x, False)
    return out


def render_music() -> dict[Path, bytes]:
    out: dict[Path, bytes] = {}
    for world in load_worlds():
        wid = world["id"]
        style = STYLES[wid]
        out[MUSIC_DIR / f"{wid}.wav"] = wav_bytes(world_loop(world, style, "base"), True)
        out[MUSIC_DIR / f"{wid}_hi.wav"] = wav_bytes(world_loop(world, style, "hi"), True)
        out[MUSIC_DIR / f"{wid}_boss.wav"] = wav_bytes(world_loop(world, style, "boss"), True)
    out[MUSIC_DIR / "menu.wav"] = wav_bytes(menu_loop(), True)
    out[MUSIC_DIR / "level_complete.wav"] = wav_bytes(stinger(False), False)
    out[MUSIC_DIR / "perfect_fanfare.wav"] = wav_bytes(stinger(True), False)
    return out


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--only", choices=["sfx", "music"], help="render one group only")
    parser.add_argument("--verify", action="store_true", help="compare with files on disk instead of writing")
    parser.add_argument("--hashes", action="store_true", help="print sha256 of every rendered file")
    args = parser.parse_args(argv)
    files: dict[Path, bytes] = {}
    if args.only in (None, "sfx"):
        files.update(render_sfx())
    if args.only in (None, "music"):
        files.update(render_music())
    mismatches = 0
    total = 0
    for path, data in sorted(files.items()):
        total += len(data)
        rel = path.relative_to(ROOT)
        if args.hashes:
            print(f"{hashlib.sha256(data).hexdigest()}  {rel}")
        if args.verify:
            if not path.exists() or path.read_bytes() != data:
                print(f"differs: {rel}")
                mismatches += 1
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        if not path.exists() or path.read_bytes() != data:
            path.write_bytes(data)
    action = "verified" if args.verify else "rendered"
    print(f"{action} {len(files)} files, {total / 1_000_000:.2f} MB, {mismatches} mismatch(es)")
    return 1 if mismatches else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
