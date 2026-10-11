#!/usr/bin/env python3
"""Music and sound effects for the SunMemo promo, synthesized from scratch.

Usage: python3 scripts/promo/audio.py <markers.jsonl> <out.wav> [outro seconds]

Everything is generated here with numpy: no samples, no licenses to track.
The music is a warm D major loop whose tempo is stretched slightly so that
the line coming down and the closing logo both land on a downbeat. Sound
effects are placed on the moments the demo wrote to its markers file.
"""
import json
import sys
import wave

import numpy as np

SR = 48000
rng = np.random.default_rng(7)


# ---------------------------------------------------------------- helpers

def t_axis(seconds):
    return np.arange(int(seconds * SR)) / SR


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def env_adsr(n, a, d, s, r, hold=None):
    """Attack, decay to sustain level, hold, release. Times in seconds."""
    a_n, d_n, r_n = int(a * SR), int(d * SR), int(r * SR)
    hold_n = n - a_n - d_n - r_n if hold is None else int(hold * SR)
    hold_n = max(hold_n, 0)
    e = np.concatenate([
        np.linspace(0, 1, max(a_n, 1), endpoint=False) ** 1.5,
        np.linspace(1, s, max(d_n, 1), endpoint=False),
        np.full(hold_n, s),
        np.linspace(s, 0, max(r_n, 1)),
    ])
    out = np.zeros(n)
    out[: min(n, len(e))] = e[:n]
    return out


def band(x, lo, hi, slope=0.0):
    """Band-pass by FFT mask, with soft edges."""
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    w = 1 / (1 + (lo / np.maximum(f, 1)) ** 4) / (1 + (f / hi) ** 4)
    if slope:
        w *= (np.maximum(f, 20) / 1000) ** slope
    return np.fft.irfft(spec * w, len(x))


def norm(x, peak=1.0):
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 0 else x


class Bus:
    """A stereo track that sounds are mixed into."""

    def __init__(self, seconds):
        self.x = np.zeros((int(seconds * SR) + SR, 2))

    def add(self, sound, at, gain=1.0, pan=0.0):
        if sound.ndim == 1:
            left, right = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
            sound = np.stack([sound * left * 1.414, sound * right * 1.414], axis=1)
        i = int(round(at * SR))
        if i < 0:
            sound, i = sound[-i:], 0
        j = min(len(self.x), i + len(sound))
        if j > i:
            self.x[i:j] += sound[: j - i] * gain


def reverb(x, seconds=2.2, wet=0.25, predelay=0.02, tone=5000):
    """Convolution with decaying, decorrelated noise: a soft room."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    out = np.zeros_like(x)
    for ch in range(2):
        ir = rng.standard_normal(n) * np.exp(-t * 6.9 / seconds)
        ir = band(ir, 200, tone)
        ir = np.concatenate([np.zeros(int(predelay * SR)), ir])
        ir /= np.sqrt(np.sum(ir ** 2))
        size = len(x) + len(ir)
        nfft = 1 << (size - 1).bit_length()
        y = np.fft.irfft(np.fft.rfft(x[:, ch], nfft) * np.fft.rfft(ir, nfft), nfft)[: len(x)]
        out[:, ch] = y
    return x * (1 - wet) + out * wet * 2.2


# ---------------------------------------------------------------- instruments

def epiano(note, dur, vel=0.6):
    f = midi(note)
    t = t_axis(dur + 1.6)
    idx = 1.6 * vel * np.exp(-t * 3.0)
    tine = 0.25 * vel * np.exp(-t * 18) * np.sin(2 * np.pi * f * 14.0 * t)
    body = np.sin(2 * np.pi * f * t + idx * np.sin(2 * np.pi * f * t) + tine)
    amp = np.exp(-t * 1.1) * env_adsr(len(t), 0.004, 0.0, 1, 0.3, hold=dur + 1.0)
    trem = 1 + 0.06 * np.sin(2 * np.pi * 4.5 * t)
    return body * amp * trem * vel


def pluck(note, vel=0.5, decay=2.4, bright=1.0):
    """Modal pluck: upper partials die faster, like a nylon string."""
    f = midi(note)
    t = t_axis(decay)
    x = np.zeros_like(t)
    for k in range(1, 12):
        if f * k > 14000:
            break
        a = (1 / k ** 1.25) * np.exp(-t * (1.6 + 0.9 * k / bright) * (2.4 / decay))
        x += a * np.sin(2 * np.pi * f * k * t * (1 + 0.0004 * k * k) + k * 0.7)
    att = np.minimum(1, t / 0.002)
    return x * att * vel * 0.5


def bell(note, vel=0.5, dur=3.5):
    f = midi(note)
    t = t_axis(dur)
    x = (np.sin(2 * np.pi * f * t) * np.exp(-t * 1.3)
         + 0.45 * np.sin(2 * np.pi * f * 2.756 * t) * np.exp(-t * 2.6)
         + 0.25 * np.sin(2 * np.pi * f * 5.404 * t) * np.exp(-t * 4.5)
         + 0.12 * np.sin(2 * np.pi * f * 8.933 * t) * np.exp(-t * 7))
    return x * np.minimum(1, t / 0.0015) * vel * 0.5


def pad(notes, dur, vel=0.18):
    t = t_axis(dur + 1.5)
    out = np.zeros((len(t), 2))
    for note in notes:
        f = midi(note)
        for ch, cents in ((0, -5), (1, 5)):
            g = f * 2 ** (cents / 1200)
            x = np.zeros_like(t)
            for k in range(1, 7):
                x += np.sin(2 * np.pi * g * k * t + rng.uniform(0, 6.28)) / k ** 1.8
            out[:, ch] += x
    e = env_adsr(len(t), 0.9, 0.4, 0.8, 1.4, hold=max(dur - 1.3, 0))
    out *= e[:, None] * vel / len(notes)
    return out


def bass(note, dur, vel=0.55):
    f = midi(note)
    t = t_axis(dur + 0.2)
    x = np.sin(2 * np.pi * f * t) + 0.25 * np.sin(4 * np.pi * f * t) + 0.08 * np.sin(6 * np.pi * f * t)
    e = env_adsr(len(t), 0.01, 0.25, 0.65, 0.18, hold=max(dur - 0.3, 0))
    return x * e * vel


def kick(vel=0.8):
    t = t_axis(0.45)
    f = 48 + 90 * np.exp(-t * 28)
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = np.sin(ph) * np.exp(-t * 7.5)
    click = band(rng.standard_normal(len(t)), 1500, 6000) * np.exp(-t * 250) * 0.15
    return (x + click) * vel


def snap(vel=0.45):
    t = t_axis(0.25)
    n = rng.standard_normal(len(t))
    e = np.zeros_like(t)
    for d in (0.0, 0.009, 0.017):
        e += np.exp(-np.maximum(t - d, 0) * 70) * (t >= d)
    x = band(n * e, 900, 3800) + 0.25 * band(n, 300, 900) * np.exp(-t * 30)
    return norm(x, vel)


def shaker(vel=0.12):
    t = t_axis(0.09)
    e = np.minimum(1, t / 0.012) * np.exp(-t * 55)
    return norm(band(rng.standard_normal(len(t)) * e, 5000, 14000), vel)


# ---------------------------------------------------------------- sound effects

def whoosh(dur=0.5, lo=300, hi=3000, vel=0.35, rise=True):
    t = t_axis(dur)
    n = rng.standard_normal(len(t))
    out = np.zeros_like(t)
    steps = 12
    for i in range(steps):
        k = i / (steps - 1)
        k = k if rise else 1 - k
        c = lo * (hi / lo) ** k
        seg = band(n, c * 0.6, c * 1.6)
        w = np.exp(-((t / dur - i / (steps - 1)) ** 2) / 0.012)
        out += seg * w
    shape = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 1.6
    return norm(out * shape, vel)


def peg(vel=0.5):
    """A wooden peg biting the rope: two quick knocks with a woody body."""
    t = t_axis(0.18)
    x = np.zeros_like(t)
    for d, g in ((0.0, 0.55), (0.022, 1.0)):
        tt = np.maximum(t - d, 0)
        on = t >= d
        body = (np.sin(2 * np.pi * 1850 * tt) * 0.7 + np.sin(2 * np.pi * 3100 * tt) * 0.4
                + np.sin(2 * np.pi * 820 * tt) * 0.5) * np.exp(-tt * 95)
        crack = band(rng.standard_normal(len(t)), 1500, 7000) * np.exp(-tt * 400)
        x += (body + crack * 0.6) * on * g
    return norm(x, vel)


def key(vel=0.22, heavy=False):
    t = t_axis(0.08)
    tt = t
    click = band(rng.standard_normal(len(t)), 2200, 7000) * np.exp(-tt * (300 if not heavy else 200))
    thump = np.sin(2 * np.pi * (180 if not heavy else 130) * tt) * np.exp(-tt * 60)
    x = click + thump * (0.5 if not heavy else 0.8)
    return norm(x, vel * rng.uniform(0.8, 1.15))


def tick(vel=0.35):
    t = t_axis(0.6)
    click = band(rng.standard_normal(len(t)), 2500, 9000) * np.exp(-t * 500)
    ding = (np.sin(2 * np.pi * 2093 * t) + 0.3 * np.sin(2 * np.pi * 4186 * t)) * np.exp(-t * 9) * 0.35
    return norm(click * 0.8 + ding, vel)


def shutter(vel=0.3):
    t = t_axis(0.2)
    x = np.zeros_like(t)
    for d in (0.0, 0.07):
        tt = np.maximum(t - d, 0)
        x += band(rng.standard_normal(len(t)), 1200, 8000) * np.exp(-tt * 160) * (t >= d)
        x += np.sin(2 * np.pi * 520 * tt) * np.exp(-tt * 80) * (t >= d) * 0.4
    return norm(x, vel)


def rip(dur=0.42, vel=0.4):
    t = t_axis(dur)
    n = rng.standard_normal(len(t))
    crackle = np.repeat(rng.uniform(0.2, 1.0, len(t) // 120 + 1), 120)[: len(t)]
    crackle *= (rng.uniform(0, 1, len(t)) > 0.3)
    e = np.minimum(1, t / 0.02) * np.exp(-t * 4) * np.sin(np.pi * t / dur) ** 0.3
    x = band(n * crackle, 900, 7000) * e
    return norm(x, vel)


def flick(vel=0.18):
    """One card riffling past the thumb."""
    t = t_axis(0.07)
    x = band(rng.standard_normal(len(t)), 1800, 9000) * np.exp(-t * 90) * np.minimum(1, t / 0.004)
    x += np.sin(2 * np.pi * rng.uniform(380, 520) * t) * np.exp(-t * 120) * 0.3
    return norm(x, vel)


def twang(vel=0.4):
    """The clothesline settling: a low, loose string."""
    t = t_axis(1.6)
    f = 82.0
    x = np.zeros_like(t)
    for k in range(1, 9):
        x += (1 / k) * np.sin(2 * np.pi * f * k * (1 + 0.003 * k) * t) * np.exp(-t * (2.5 + k * 0.9))
    x *= np.minimum(1, t / 0.01) * (1 + 0.15 * np.sin(2 * np.pi * 5.5 * t))
    return norm(x, vel)


def pop(vel=0.3):
    t = t_axis(0.12)
    f = 300 + 900 * np.exp(-t * 60)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 40)
    return norm(x, vel)


# ---------------------------------------------------------------- score

def main():
    markers_path, out_path = sys.argv[1], sys.argv[2]
    outro = float(sys.argv[3]) if len(sys.argv) > 3 else 5.5
    marks = [json.loads(l) for l in open(markers_path) if l.strip()]

    def times(name):
        return [m["t"] for m in marks if m["event"] == name]

    def first(name):
        return times(name)[0]

    end = first("end")
    total = end + outro
    line_downs = times("line_down")
    t_down = line_downs[0]

    # Tempo: whole bars from the line coming down to the closing logo.
    span = end - t_down
    bars = max(1, round(span / (4 * 60 / 90)))
    bar = span / bars
    beat = bar / 4
    bpm = 240 / bar
    bar0 = t_down - bar  # one bar of intro before the line comes down

    def bar_at(t):
        return int(np.floor((t - bar0) / bar + 0.5))

    climax = (bar_at(first("cascade_start")), bar_at(first("sweep_end")) + 1)
    hush = (bar_at(first("line_up")), bar_at(line_downs[-1]))
    last_bar = bar_at(end)  # the outro chord's downbeat

    print(f"tempo {bpm:.1f} bpm, {bars} bars, climax bars {climax}, hush {hush}")

    music = Bus(total)
    drums = Bus(total)

    chords = [  # (bass, pad voicing, arpeggio tones)
        (38, [62, 66, 69, 73, 76], [74, 78, 81, 85, 81, 78]),        # Dmaj9
        (35, [59, 62, 66, 69, 73], [71, 74, 78, 81, 78, 74]),        # Bm9
        (31, [55, 59, 62, 66, 69], [67, 71, 74, 78, 74, 71]),        # Gmaj9
        (33, [57, 62, 64, 66, 71], [69, 74, 76, 78, 76, 74]),        # A6/9sus
    ]

    # The pad swells in under the title.
    music.add(pad(chords[0][1], bar0 + bar * 0.95 - 0.3, vel=0.16), 0.3)
    for b in range(0, last_bar):
        t = bar0 + b * bar
        root, voicing, arp = chords[b % 4]
        in_climax = climax[0] <= b < climax[1]
        hushed = hush[0] <= b < hush[1]
        if b >= 1:
            music.add(pad(voicing, bar * 0.98, vel=0.14 if not in_climax else 0.17), t)
        # Electric piano: on the one and the and-of-two.
        if b >= 1 and not hushed:
            for off, v in ((0, 0.32), (1.5 * beat, 0.22)):
                for n_i, n in enumerate(voicing[1:]):
                    music.add(epiano(n, beat * 1.2, vel=v), t + off + n_i * 0.008, pan=(n_i - 1.5) * 0.2)
        # Plucked arpeggio: eighths, sixteenths at the climax.
        step = beat / (4 if in_climax else 2)
        count = 16 if in_climax else 8
        if b == 0:
            count, step = 4, beat
        for i in range(count):
            n = arp[i % len(arp)] + (12 if in_climax and i % 4 == 3 else 0)
            v = 0.42 if i % 2 == 0 else 0.3
            if hushed:
                v *= 0.6
            music.add(pluck(n, vel=v, decay=1.8), t + i * step, pan=0.35 * np.sin(i * 1.3))
        # Bass and drums once the line is down.
        if b >= 1 and not hushed:
            music.add(bass(root, beat * 1.6), t)
            music.add(bass(root + (7 if b % 2 else 12), beat * 0.9, vel=0.4), t + 2.5 * beat)
            for q in range(4):
                if q in (0, 2) or (in_climax and q == 3):
                    drums.add(kick(0.75 if q == 0 else 0.6), t + q * beat + (0.5 * beat if q == 3 else 0))
                if q in (1, 3):
                    drums.add(snap(0.32 if not in_climax else 0.4), t + q * beat, pan=0.1)
            for e in range(8 if not in_climax else 16):
                s = beat / (2 if not in_climax else 4)
                drums.add(shaker(0.09 if e % 2 else 0.13), t + e * s + 0.012, pan=0.4)

    # Bell motif over the title, and again with the logo.
    motif = [(81, 0), (78, 0.5), (85, 1.0), (86, 2.0)]
    for n, b in motif:
        music.add(bell(n, 0.22), 0.5 + b * beat, pan=0.2)

    t_end = bar0 + last_bar * bar
    music.add(pad(chords[0][1] + [81], outro, vel=0.2), t_end - 0.05)
    music.add(bass(26, 3.0, vel=0.6), t_end)
    for i, n in enumerate([62, 69, 74, 78, 81, 85, 88]):
        music.add(pluck(n, vel=0.38, decay=3.5), t_end + i * 0.06, pan=(i - 3) * 0.12)
    for n, d in ((86, 0.0), (93, 0.33), (90, 0.66), (98, 1.0)):
        music.add(bell(n, 0.2, dur=4), t_end + d * beat * 2, pan=0.25)
    drums.add(kick(0.7), t_end)

    # ------------------------------------------------------------ effects
    fx = Bus(total)
    land = 0.69
    for t in line_downs:
        fx.add(whoosh(0.55, 2500, 300, 0.22, rise=False), t - 0.05)
        fx.add(twang(0.32), t + 0.28)
    for t in times("line_up"):
        fx.add(whoosh(0.4, 300, 2500, 0.2), t - 0.02)
    for t in times("shot_fly"):
        fx.add(shutter(0.28), t - 0.12)
        fx.add(whoosh(0.7, 400, 3500, 0.26), t + 0.02)
        fx.add(peg(0.42), t + land)
    for t in times("editor_open"):
        fx.add(pop(0.22), t + 0.05)
        fx.add(whoosh(0.3, 800, 2500, 0.1), t)
    for t in times("key"):
        fx.add(key(0.16), t, pan=rng.uniform(-0.2, 0.2))
    for t in times("key_return"):
        fx.add(key(0.2, heavy=True), t)
    for t in times("memo_commit") + times("memo_fly"):
        fx.add(whoosh(0.7, 400, 3500, 0.24), t + 0.02)
        fx.add(peg(0.42), t + land + 0.01)
    for t in times("tick"):
        fx.add(tick(0.32), t)
    for t in times("preview_open"):
        fx.add(whoosh(0.45, 600, 2200, 0.2, rise=False), t)
    for t in times("preview_close"):
        fx.add(whoosh(0.4, 600, 2600, 0.16), t)
    for m in marks:
        if m["event"] == "tear":
            fx.add(rip(0.42, 0.38), m["at"])
            fx.add(whoosh(1.1, 1800, 250, 0.14, rise=False), m["at"] + 0.2)
    for i, m in enumerate(m for m in marks if m["event"] == "cascade_fly"):
        pan = 0.5 * np.sin(i * 2.1)
        fx.add(whoosh(0.5, 500, 3800, 0.12), m["at"], pan=pan)
        fx.add(peg(0.26), m["at"] + land, pan=pan)
    sweep0, sweep1 = first("sweep_start"), first("sweep_end")
    n = max(1, round((sweep1 - sweep0) / 0.17))
    for i in range(n):
        fx.add(flick(0.16), sweep0 + i * (sweep1 - sweep0) / n, pan=-0.6 + 1.2 * i / n)

    # ------------------------------------------------------------ mix
    m = reverb(music.x, 2.4, 0.3)
    d = reverb(drums.x, 0.9, 0.12, tone=7000)
    f = reverb(fx.x, 0.8, 0.12)
    mix = norm(m, 0.5) + norm(d, 0.32) + norm(f, 0.55)
    # Fade in and out.
    n_total = int(total * SR)
    mix = mix[:n_total]
    fade_in = np.minimum(1, np.arange(n_total) / (0.25 * SR))
    fade_out = np.clip((n_total - np.arange(n_total)) / (1.2 * SR), 0, 1)
    mix *= (fade_in * fade_out)[:, None]
    # Gentle limiter.
    mix = np.tanh(mix * 1.4) / np.tanh(1.4)
    mix = norm(mix, 0.89)

    pcm = (mix * 32767).astype(np.int16)
    with wave.open(out_path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(f"wrote {out_path}, {total:.2f}s")


if __name__ == "__main__":
    main()
