# Resource Balance Guide

This document describes the math behind resource amounts per level, building costs, and win conditions for Cosmos level design.

## Building Costs

| Building       | Minerals | Notes                    |
| -------------- | -------- | ------------------------ |
| Power node     | 25       | Power grid extension     |
| Solar panel    | 250      | Generates 10.0 power/sec |
| Mining station | 75       | Extracts from asteroids  |
| Laser turret   | 150      | Defensive structure      |
| Monolith       | 0        | Map-placed only          |

**Construction:** Each structure requires 10 power (one-time) from the grid during build.

## Baseline Economy

- **Mining rate:** 15 minerals per extraction, every 2 seconds (7.5 minerals/sec per miner)
- **Minimum viable economy:** 1 solar (250) + 1 power node (25) + 1 mining (75) = **350 minerals**
- **Each additional mining station:** 75 + power extension (25 per node as needed)
- **Defense per turret:** 150

## Minerals win condition (bank balance)

Victory for `win_mode` minerals (or the minerals half of `both`) requires **current mineral balance** (`GameState.minerals`) to reach at least `win_minerals`. It is **not** based on lifetime minerals mined.

- **Spending** on buildings and other costs reduces progress until the player mines or earns more.
- **Enemy and scrap rewards** (anything that calls `add_minerals`) increase the bank and count toward the same objective as mining.

When tuning a map, ensure players can realistically **hold** the target after paying for infrastructure and defense, not only extract that much over the course of the match.

## Balance Formula

```
Total income potential ≈ starting_minerals + sum(asteroid_minerals) + enemy_rewards (if any)
Required spending ≈ (mining_stations × 75) + (turrets × 150) + (solar × 250) + (power_nodes × 25)
win_minerals should be ≤ (total income potential − typical spend) so the objective is achievable with efficient play
```

## Difficulty Bands

| Difficulty | Starting minerals | Asteroid minerals (per rock) | Win mineral balance (optional) | Monolith charge (optional) |
| ---------- | ----------------- | ---------------------------- | ------------------------------ | -------------------------- |
| Easy       | 400–500           | 800–1,400                    | 4,000–8,000                    | 300–400                    |
| Medium     | 250–400           | 850–1,650                    | 8,000–14,000                   | 400–500                    |
| Hard       | 200–300           | 900–1,850                    | 12,000–18,000                  | 500–600                    |

Skilled players succeed by building efficiently, defending with minimal turrets, and expanding mining carefully. Scarce starting minerals force trade-offs. Because the win check uses **bank balance**, targets are typically **lower** than old “cumulative mined” numbers for comparable difficulty.

## Monolith Charging

- Monolith absorbs power from the grid via `base_absorption_rate` (default 15/sec)
- To charge 500 in ~60s, need ~8–10 power/sec surplus after consumers
- Typically requires 2–3 solars (~5.6/sec each) + minimal turrets/mining for surplus

## Map JSON Win Fields

```json
"win_minerals": 12000,
"win_monolith_power_required": 500,
"win_mode": "both"
```

- **win_minerals:** Minimum **current** mineral balance required when the minerals objective applies.
- **win_mode:** `"minerals"` \| `"monolith"` \| `"both"` \| `"none"`
- Legacy maps may still use `"win_minerals_mined"`; the loader treats it as `win_minerals`.
- If `win_monolith_power_required` > 0, place a monolith in `starting_structures` and connect it to the power grid
- Power node connection range is 15 units
