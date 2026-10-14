# Endless difficulty tiers

Endless runs use **four** selectable tiers: **Easy**, **Normal**, **Hard**, and **Impossible**. They only change **how fast and how hard waves scale**—the same map rules and building set apply to every tier.

Authoritative numbers live in [`scripts/data/endless_difficulty_presets.gd`](../scripts/data/endless_difficulty_presets.gd). Extrapolated wave stats are built in [`scripts/data/endless_wave_extrapolation.gd`](../scripts/data/endless_wave_extrapolation.gd) (`build_wave`).

---

## What each tier changes (high level)

| Aspect | Easier tiers | Harder tiers |
|--------|----------------|----------------|
| **Breathing room** | Longer wait before the first wave; more time between waves | Shorter delays; waves arrive faster |
| **Enemy count** | Starts lower and grows more slowly per wave | Higher base count, steeper growth, higher cap |
| **Enemy scaling** | Health and speed gain less per wave index | More health and speed added each wave |
| **Spawning** | More delay between individual spawns in a wave (especially early) | Tighter spawns; lower minimum delay |

---

## Timing (seconds)

These map fields are applied when the endless map is generated (`EndlessMapGenerator` → `MapData`).

| Tier | `initial_wave_delay` | `wave_interval` |
|------|----------------------|-----------------|
| Easy | 40 | 75 |
| Normal | 30 | 60 |
| Hard | 22 | 48 |
| Impossible | 15 | 36 |

- **`initial_wave_delay`** — Time after the run starts before **wave 0** begins.
- **`wave_interval`** — Seconds between the **start** of one wave and the **start** of the next (after the first wave).

---

## Extrapolated waves (`EndlessWaveExtrapolation`)

For endless maps, waves beyond authored data use **wave index** `w` (0-based). Each wave gets:

### Enemy count

- **Formula:** `count = min(ceil(count_base × count_growth^w), count_cap)`, clamped to at least **3** enemies.

| Tier | `count_base` | `count_growth` | `count_cap` |
|------|--------------|----------------|-------------|
| Easy | 2.5 | 1.14 | 500 |
| Normal | 3.0 | 1.2 | 800 |
| Hard | 3.5 | 1.22 | 900 |
| Impossible | 4.0 | 1.24 | 1000 |

Higher tiers start with more enemies and ramp up faster; caps prevent absurd counts.

### Per-wave multipliers

| Tier | `health_add_per_wave` | `speed_add_per_wave` |
|------|-------------------------|-------------------------|
| Easy | 0.14 | 0.035 |
| Normal | 0.22 | 0.05 |
| Hard | 0.28 | 0.065 |
| Impossible | 0.34 | 0.08 |

- **Enemy health multiplier** = `1 + w × health_add_per_wave`
- **Enemy speed multiplier** = `1 + w × speed_add_per_wave`

So later waves are tougher on both stats; harder tiers add more per wave step.

### Spawn delay (within a wave)

| Tier | `spawn_delay_start` | `spawn_delay_per_wave` | `spawn_delay_min` |
|------|---------------------|---------------------------|-------------------|
| Easy | 1.55 | 0.04 | 0.12 |
| Normal | 1.35 | 0.048 | 0.1 |
| Hard | 1.2 | 0.052 | 0.09 |
| Impossible | 1.05 | 0.055 | 0.08 |

- **Formula:** `spawn_delay = max(spawn_delay_min, spawn_delay_start − w × spawn_delay_per_wave)`

So early waves spawn more slowly; as `w` increases, spawns tighten until they hit the floor `spawn_delay_min`. Harder tiers start tighter and end up with a lower minimum delay.

---

## Choosing a tier

- **Easy** — Most forgiving pacing and scaling; good for learning endless or low-pressure runs.
- **Normal** — Default balance; baseline for “intended” difficulty.
- **Hard** — Less time between waves and stronger scaling; demands faster economy and defenses.
- **Impossible** — Shortest breaks, steepest enemy scaling, and the most aggressive spawn cadence.

---

## Related code

- Preset selection: `EndlessDifficultyPresets.get_preset(difficulty_id)`
- Map build: `EndlessMapGenerator.build(seed, difficulty_id)`
- Session: `GameSession.start_endless` stores `endless_difficulty_id` for the main game load
