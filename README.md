# ⌚ Timegrapher

A precision **watch rate analyzer** that runs entirely in your browser. Point
your phone or laptop microphone at a mechanical watch, hit Start, and read
**rate (s/day)**, **beat error (ms)**, and **amplitude (°)** — the same three
numbers a Witschi or Weishi machine gives you, computed with the same maths.

No audio leaves your device. No backend. No accounts. Just `run.sh`.

---

## Highlights

- **Sub-second-per-day rate precision** via least-squares linear regression of
  beat times (the same technique used by professional service-grade machines).
- **True beat error** from the regression's odd/even offset coefficient — not
  just the difference of two interval averages.
- **Amplitude from sub-pulse spacing** using the standard escapement physics
  formula `A = lift / (2·sin(π·Δt / T_balance))`, now with **group-delay
  compensation** and an adaptive unlock-pulse threshold so the reading shows up
  reliably (with a `~` confidence flag instead of going blank when the unlock
  pulse is faint).
- **Beta workbench** (experimental, opt-in): a **sub-pulse oscilloscope** of one
  magnified beat, a **positional rosette** plotting rate spread across the six
  positions, an **isochronism plot** (rate vs amplitude as the mainspring winds
  down), **lift-angle auto-calibration** from a known reference amplitude, and an
  **audible beat sonifier** that replays the detected tick/tock so you can *hear*
  beat error.
- **Classic paper-tape trace** (dual scrolling lines, slope = rate, gap = beat
  error) plus a live envelope strip and a **lifetime rate-history chart**.
- **~90 movement presets** across 22 brands (ETA, Sellita, Miyota, Seiko/GS,
  Rolex, Omega, Tudor, Patek, Lange, AP, JLC, Vacheron, IWC, Zenith, GO,
  NOMOS, Seagull, Hangzhou, Vostok, vintage chronos…) that auto-populate BPH
  and lift angle.
- **Six-position testing** (DU / DD / CU / CD / CL / CR) with a session log
  and CSV export.
- **Long-running sessions (days)**: lifetime accumulators with O(1) memory,
  Wake Lock to keep capturing while the screen sleeps, auto-log every 1 min
  to 6 h, and localStorage persistence so a refresh doesn't wipe your log.
- **Mic profiles** for phone, laptop, headset, piezo contact pickup, and
  studio mics — plus input gain, pre-emphasis, threshold-σ slider, and a
  5-second **calibration test** that confirms the system can actually hear
  the watch before you commit to a real reading.
- **Installable PWA** — works offline once loaded.

---

## Running locally

```bash
./run.sh                # serves on http://localhost:8000
PORT=9000 ./run.sh      # custom port
```

The script auto-detects `python3`, `python`, `node`, or `busybox` and binds
to `localhost`. Microphone capture requires a **secure context**; `localhost`
qualifies, so no certificate is needed.

> **On Windows without WSL:** open a terminal in the repo folder and run
> `python -m http.server 8000`, then visit <http://localhost:8000/>.

Once loaded, you can install it as a PWA from your browser's menu (look for
"Install app" / "Add to Home Screen"). After install it works fully offline.

---

## How a timegrapher works — and how this one does it

A mechanical watch's escapement produces a sharp acoustic transient — the
"tick" — each time a pallet jewel locks against an escape-wheel tooth. The
balance wheel oscillates back and forth; each half-cycle produces one tick.
At **BPH = 28 800** there are 8 beats per second, i.e. a tick every **125 ms**.

A timegrapher (Greinker, Vibrograph, Witschi…) listens for those transients
and infers three numbers:

| Quantity         | What it tells you                                          | Good values         |
|------------------|------------------------------------------------------------|---------------------|
| **Rate** (s/day) | How fast/slow the watch runs vs. its nominal beat rate     | ±10 s/d (COSC ≤ +6/−4) |
| **Beat error** (ms) | Asymmetry between "tick" and "tock" half-cycles         | < 0.5 ms ideal      |
| **Amplitude** (°) | Peak swing angle of the balance wheel                     | 270–310° dial up    |

### The DSP pipeline

```
raw mic ── × gain ── pre-emphasis ── band-pass (4-stage biquad)
        ── │x│  ── fast LP (τ≈0.3 ms, "sub-pulse envelope")
                  └─ slow LP (τ≈2.6 ms, "beat envelope")
slow envelope ── adaptive threshold = EMA-median + σ·EMA-MAD
              ── peak picker with refractory ≈ 0.6·T_halfbeat
              ── parabolic interpolation around peak → sub-sample time
              ── push to `beats[]` and lifetime accumulators
```

This runs in an `AudioWorklet` (falls back to `ScriptProcessor`) at the audio
sample rate (48 kHz). The adaptive median+MAD threshold tracks the noise
floor on the order of seconds, so the detector keeps working even if the
ambient noise drifts.

### Rate — linear regression on beat times

If beat *i* happens at session time *tᵢ* with global beat-index *kᵢ*, the
model is

> *tᵢ ≈ a + b·kᵢ + (kᵢ mod 2)·c*

We fit `[a, b, c]` by least squares (3-column design matrix, closed-form
solve, one round of MAD-based outlier rejection). Then

- **b** is the measured half-period (s).
- **rate (s/day) = (T_exp − b) / T_exp × 86400** where T_exp = 3600 / BPH.
- **c** is the odd/even offset → **beat error (ms) = |c| × 1000 / 2**.

This is dramatically more precise than averaging intervals, because the
standard error of the slope grows only as **1 / (N^(3/2) · σ_jitter)**. With
240 beats in 30 s and ≈1 ms detector jitter, rate precision is already on
the order of **±0.5 s/day** — and it gets tighter the longer you record.

The **Lifetime** card runs the same regression over **every** beat since you
hit Start (using O(1) running sums, so it handles multi-day sessions without
allocating). Lifetime rate ± 1σ is shown live.

### Amplitude — sub-pulse spacing

Each beat consists of three sub-impulses: **unlocking** (pallet jewel
released), **impulse** (escape-wheel tooth pushes pallet), and **drop**
(tooth locks against the next pallet). Between unlock and drop, the balance
wheel sweeps through its *lift angle*. By SHM,

> θ(t) = A · sin(2π t / T_balance)

The balance crosses ±(lift / 2) at *t = ±(T_balance / 2π) · arcsin(lift /
(2A))*, so the time between unlock and drop is

> Δt = (T_balance / π) · arcsin(lift / (2A))

Inverting:

> **A = lift / (2 · sin(π · Δt / T_balance))**, &nbsp; T_balance = 2 · T_halfbeat

We search ~9 ms before each main peak in the high-resolution fast-envelope
ring buffer for a smaller transient above the local noise floor, refine its
location with parabolic interpolation, and take the **robust mean** of Δt
across the last ~30 beats. The result is rejected as unreliable if it falls
outside 140°–340°.

### Why this is "professional-grade"

- Beat times are **timestamped at the audio sample rate** (~21 µs at 48 kHz)
  with parabolic interpolation for **sub-sample** precision.
- Detector jitter is the limiting factor, **not** clock drift — the browser's
  `AudioContext.currentTime` is monotonic and accurate to the audio frame.
- The linear-regression rate uses **all** detected beats with one round of
  3·MAD outlier rejection — equivalent to the algorithms in Witschi
  "ChronoMaster" / TG-Timer.
- Amplitude is derived from **physics** (lift angle + SHM) — not estimated
  from peak energy.

---

## UI tour

### Controls (left column)

- **Start / Stop / Reset** — session lifecycle.
- **Mic profile** — sensible defaults for phone, laptop, headset, piezo
  contact pickup, or studio condenser. Auto-applies band-pass, gain,
  sensitivity, and pre-emphasis. You can still adjust anything afterwards.
- **Input gain** (0–40 dB) — software pre-amp for quiet mics.
- **Threshold σ** (2–9) — number of MAD above the running median that an
  envelope peak must exceed to count as a beat. Higher = stricter.
- **Band-pass** — frequency window for the biquad cascade. Defaults work for
  most watches; piezo pickups like 200–5000 Hz, sharp tick-y watches like
  3–12 kHz.
- **Pre-emphasis** — first-order high-shelf-like filter that boosts tick
  transients. On by default; turn off for piezo pickups.
- **Calibration test (5 s)** — a pre-flight check that verifies the system
  can actually hear the watch *before* you start a real reading. It runs in
  two phases:
    1. Listens for 1.5 s to your noise floor and auto-picks a threshold σ.
    2. Listens for 3.5 s with the watch on the mic, counts the beats it
       detects, and compares against what's expected from the configured BPH.
  You get a clear **PASS / WARN / FAIL** verdict with coverage %, tick SNR,
  detector jitter, and specific suggestions ("raise gain by 6 dB", "tighten
  the band-pass", "press the watch closer", etc.) if anything is off. Run
  it once at the start of every session — once it passes, the timegraph
  readings will be trustworthy.
- **Movement preset** — search-friendly dropdown of ~90 movements grouped by
  brand. Selecting one fills BPH and lift angle.
- **BPH / Lift angle / Window** — manual overrides.
- **Position** — DU / DD / CU / CD / CL / CR. Logged with each reading so you
  can build the full six-position picture.
- **Long-running session** — Wake Lock toggle, auto-log interval (1 min … 6 h),
  and the localStorage persistence checkbox.

### Results (right column)

- **Live metrics** — rate, beat error, amplitude, detected BPH, beats in the
  current window, and a quality score (0–100). Colour-coded green / amber /
  red against typical horological tolerances.
- **Paper-tape trace** — classic dual-line view (one per parity). A vertical
  line means an on-rate watch; the slope of the lines is the rate; the
  horizontal gap between them is the beat error.
- **Envelope strip** — last ~4 s of band-filtered audio with each detected
  beat marked.
- **Lifetime metrics** — same numbers but computed over the whole session
  since Start. Run for an hour and you get ±0.1 s/day precision; run
  overnight and you can see thermal drift in the rate-history chart.
- **Rate history** — 1 sample/min for up to 14 days. The green line is the
  current windowed rate (noisy), the blue line is the lifetime rate (smooth).
- **Session log** — every "Log" press (manual or auto) is added with
  timestamp, position, and all metrics. **Export CSV** to dump for Excel /
  Pandas; persists across browser refreshes.

### Header

- **Uptime pill** — how long the current session has been running.
- **Status pill** — listening / stopped / mic denied.

---

## Tips for accurate readings

1. **Quiet environment.** The tick is around −40 dBFS. Background HVAC noise
   is the #1 cause of bad amplitude readings.
2. **Mechanical coupling matters.** A phone bottom mic pressed flat against
   the case back is shockingly good. A piezo / contact mic glued to a small
   wood block (then pressed against the case) is even better.
3. **Let the watch settle** for ~10 s after handling — friction in the
   pivots dies away.
4. **Test each position separately** for at least 30 s, and use the position
   buttons + Log so you can see the positional spread.
5. **For overnight runs**: plug the device in, set **Auto-log = 5 min**,
   enable **Wake Lock**, and leave the tab visible. The lifetime rate will
   converge to a number more precise than most service centres quote.
6. **Pick the right BPH.** Auto-detect snaps to the nearest standard BPH;
   for unusual movements (Vostok 19 800, Patek 215 PS at 21 600, El Primero
   at 36 000) use the **Movement preset** dropdown or set it manually.
7. **Set the correct lift angle.** Default 52° is right for many Swiss
   movements but **wrong by a lot** for many others (Omega co-axial = 38°,
   Patek 240 = 44°, Seiko = 53°). Use a preset, or look it up.

---

## Files

| File                    | What it is                                       |
|-------------------------|--------------------------------------------------|
| `index.html`            | The whole app — UI, DSP, analysis, rendering.    |
| `manifest.webmanifest`  | PWA install manifest.                            |
| `sw.js`                 | Service worker — cache-first offline shell.      |
| `assets/`               | Brand icon, PWA icons, and social/OG share image.|
| `robots.txt`            | Crawler directives + sitemap pointer.            |
| `sitemap.xml`           | Sitemap for search engines.                      |
| `run.sh`                | Local HTTP launcher (Linux / WSL / macOS).       |
| `README.md`             | This file.                                       |

---

## Limitations & honest disclaimers

- **Amplitude is a *timing* measurement, not a loudness one.** It comes from the
  unlock→impulse gap (Δt) within each beat — not from how loud the tick is — so
  the microphone's absolute sensitivity is irrelevant and a phone mic does *not*
  need to be a calibrated transducer to read it. (There is also no practical way
  to do it in a browser: absolute SPL calibration needs a traceable reference
  source the mic doesn't have, and the OS keeps changing gain on you.) What
  amplitude *does*
  depend on is the **lift angle** (it scales linearly with it) and how cleanly
  the unlock pulse clears the noise floor. Both are addressable: set the right
  lift angle, and use **Tools → Lift-angle auto-calibration** to snap it against
  one trusted reference position — every other position then reads correctly.
  Treat the absolute number as ±10–20° unless you've done that; the **trend**
  (DU vs. DD, before vs. after service) is reliable regardless.
- Beat error and rate, by contrast, depend almost entirely on **timing** —
  these are accurate to the limits of the audio clock and detector jitter.
- The lift-angle table is a best-effort compilation from manufacturer specs
  and the Witschi reference. If your reference disagrees, override it.
- The browser audio clock has its own quartz tolerance (typically <10 ppm =
  <0.9 s/day). Unlike absolute amplitude, this *is* calibratable — it's a single
  constant scale factor. Measure a reference timepiece of known rate and use
  **Tools → Clock-rate calibration** to snap the ppm trim; the offset is stored
  on that device and applied to every subsequent reading.

---

## License

Do whatever you want with this. Attribution is appreciated. No warranty —
don't use this to certify chronometers for sale.

---

Built for horology nerds. Pull requests welcome.
