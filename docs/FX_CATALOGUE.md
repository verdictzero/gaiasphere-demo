# Effects catalogue

Every effect in `assets/fx/fx_catalogue.json`. Spawn one by name:

```gdscript
Fx.spawn(self, "campfire", Vector3(10, 0, 4))          # stays until freed
Fx.spawn(self, "explosion_large", hit_point, 1.5)     # plays once and frees itself; 1.5 = half as big again
```

Looping effects stay until you free the node they return (or call `Fx.stop(node)`, which lets the smoke
already in the air drift away first). One-shots free themselves. Sizes are in metres at scale 1.
Pictures of all of them: `docs/fx/` (made by `tests/RENDER_fx_gallery.gd`).

This file and the JSON are written by `tools/build_fx_library.py`; edit the effects there.

## Fire: composed effects

| Effect | Kind | Lasts | What it is | Textures |
|---|---|---|---|---|
| `bonfire` | loops | until freed | A big fire: tall flames, a lot of embers, a heavy column of smoke. | ember_bits_01, flame_loop_03, flame_loop_04, flame_loop_06, flame_puff_02, smoke_roll_07, wisp_flame_03 |
| `brazier` | loops | until freed | A bowl of fire: broad low flames, sparks, and a little smoke. | ember_bits_01, flame_loop_06, smoke_roll_05, wisp_flame_03 |
| `campfire` | loops | until freed | A campfire: flames, embers going up, thin smoke, and its light. | ember_bits_01, flame_loop_01, flame_loop_03, smoke_roll_04 |
| `campfire_small` | loops | until freed | A small cooking fire, hardly any smoke. | ember_bits_01, flame_loop_06 |
| `candle` | loops | until freed | A candle flame. | candle_loop_01 |
| `embers` | loops | until freed | Embers alone, drifting up from a hot bed. | ember_bits_01 |
| `fireball` | loops | until freed | A thrown fireball: move the node; it leaves fire and smoke behind it. | fire_burst_06, puff_soft_02, wisp_flame_03 |
| `flare_up` | one-shot | 1.6 s | A sudden gout of flame, as when fat hits a fire. | ember_bits_01, flame_puff_01 |
| `ground_fire` | loops | until freed | Low fire licking over a patch of ground 3 m across. | flame_loop_02, smoke_roll_08, wisp_flame_03 |
| `ignite` | one-shot | 3.3 s | Something catching fire: a line of flame that grows up. | flame_ignite_01 |
| `impact_fire` | one-shot | 1.0 s | A fireball landing: a splash of flame and sparks. | fire_burst_05, glow_warm_02, ring_02 |
| `magic_flame` | loops | until freed | Cold blue-white fire. | flame_loop_05, wisp_flame_04 |
| `torch` | loops | until freed | A torch flame: narrow, restless, a little smoke off the tip. | ember_bits_01, flame_loop_02, wisp_smoke_02 |
| `wall_of_fire` | loops | until freed | A dense line of fire 6 m long (along x), with its smoke. Scale it for more. | ember_bits_01, flame_loop_03, flame_loop_06, flame_puff_02, flame_puff_03, smoke_roll_02, wisp_flame_03 |

## Fire: one per texture

| Effect | Kind | Lasts | What it is | Textures |
|---|---|---|---|---|
| `candle_loop_01` | loops | until freed | Fire burning on the spot. | candle_loop_01 |
| `candle_still_01` | loops | until freed | A single picture of flame, flickering in size. | candle_still_01 |
| `ember_bits_01` | loops | until freed | Embers lifting and winking out. | ember_bits_01 |
| `fire_burst_01` | one-shot | 1.0 s | A burst of fire that swells and breaks up. | fire_burst_01 |
| `fire_burst_02` | one-shot | 1.8 s | A burst of fire that swells and breaks up. | fire_burst_02 |
| `fire_burst_03` | one-shot | 1.8 s | A burst of fire that swells and breaks up. | fire_burst_03 |
| `fire_burst_04` | one-shot | 1.8 s | A burst of fire that swells and breaks up. | fire_burst_04 |
| `fire_burst_05` | one-shot | 1.0 s | A burst of fire that swells and breaks up. | fire_burst_05 |
| `fire_burst_06` | one-shot | 1.4 s | A burst of fire that swells and breaks up. | fire_burst_06 |
| `fireball_trail_01` | loops | until freed | A fireball with its tail, lying along x: turn the node to aim it. | fireball_trail_01 |
| `flame_ignite_01` | one-shot | 3.3 s | Fire that catches or goes up once. | flame_ignite_01 |
| `flame_ignite_02` | one-shot | 4.0 s | Fire that catches or goes up once. | flame_ignite_02 |
| `flame_loop_01` | loops | until freed | Fire burning on the spot. | flame_loop_01 |
| `flame_loop_02` | loops | until freed | Fire burning on the spot. | flame_loop_02 |
| `flame_loop_03` | loops | until freed | Fire burning on the spot. | flame_loop_03 |
| `flame_loop_04` | loops | until freed | Fire burning on the spot. | flame_loop_04 |
| `flame_loop_05` | loops | until freed | Fire burning on the spot. | flame_loop_05 |
| `flame_loop_06` | loops | until freed | Fire burning on the spot. | flame_loop_06 |
| `flame_puff_01` | one-shot | 1.6 s | Fire that catches or goes up once. | flame_puff_01 |
| `flame_puff_02` | one-shot | 1.2 s | Fire that catches or goes up once. | flame_puff_02 |
| `flame_puff_03` | one-shot | 1.7 s | Fire that catches or goes up once. | flame_puff_03 |
| `flame_puff_04` | one-shot | 1.2 s | Fire that catches or goes up once. | flame_puff_04 |
| `flame_still_01` | loops | until freed | A single picture of flame, flickering in size. | flame_still_01 |
| `glow_soft_01` | loops | until freed | A glow that hangs and pulses. | glow_soft_01 |
| `glow_streak_01` | loops | until freed | A glow that hangs and pulses. | glow_streak_01 |
| `glow_warm_01` | loops | until freed | A glow that hangs and pulses. | glow_warm_01 |
| `glow_warm_02` | loops | until freed | A glow that hangs and pulses. | glow_warm_02 |
| `wisp_flame_01` | loops | until freed | Loose licks of flame rising, each a different piece. | wisp_flame_01 |
| `wisp_flame_02` | loops | until freed | Loose licks of flame rising, each a different piece. | wisp_flame_02 |
| `wisp_flame_03` | loops | until freed | Loose licks of flame rising, each a different piece. | wisp_flame_03 |
| `wisp_flame_04` | loops | until freed | Loose licks of flame rising, each a different piece. | wisp_flame_04 |

## Smoke and dust: composed effects

| Effect | Kind | Lasts | What it is | Textures |
|---|---|---|---|---|
| `chimney_smoke` | loops | until freed | Pale smoke leaning with the wind (along +x). | smoke_roll_05 |
| `dust_cloud` | one-shot | 3.0 s | A cloud of dust thrown up and settling. | smoke_burst_05 |
| `footfall_dust` | one-shot | 0.9 s | The scuff a foot or a dropped thing kicks up. | dust_bits_01 |
| `ground_fog` | loops | until freed | Low smoke or mist lying over a patch 8 m across. | puff_soft_07 |
| `smoke_column` | loops | until freed | A tall column of grey smoke, as off a chimney or a wreck. | smoke_roll_02 |
| `smoke_column_black` | loops | until freed | Thick black smoke, as off burning oil. | smoke_dark_01 |
| `smoke_puff` | one-shot | 1.5 s | One puff of smoke, as from a snuffed flame or a shot. | smoke_burst_03 |
| `smoke_thin` | loops | until freed | A thin thread of smoke off something smouldering. | wisp_smoke_03 |
| `smoulder` | loops | until freed | What is left of a fire: faint smoke and a few embers. | ember_bits_01, wisp_smoke_02 |
| `steam_vent` | loops | until freed | Steam forced up out of the ground. | steam_loop_01 |

## Smoke and dust: one per texture

| Effect | Kind | Lasts | What it is | Textures |
|---|---|---|---|---|
| `dust_bits_01` | one-shot | 1.4 s | A scuff of dust. | dust_bits_01 |
| `dust_streak_01` | one-shot | 1.6 s | A low streak of dust thrown along the ground. | dust_streak_01 |
| `puff_soft_01` | loops | until freed | Soft drifting smoke from a single puff picture. | puff_soft_01 |
| `puff_soft_02` | loops | until freed | Soft drifting smoke from a single puff picture. | puff_soft_02 |
| `puff_soft_03` | loops | until freed | Soft drifting smoke from a single puff picture. | puff_soft_03 |
| `puff_soft_04` | loops | until freed | Soft drifting smoke from a single puff picture. | puff_soft_04 |
| `puff_soft_05` | loops | until freed | Soft drifting smoke from a single puff picture. | puff_soft_05 |
| `puff_soft_06` | loops | until freed | Soft drifting smoke from a single puff picture. | puff_soft_06 |
| `puff_soft_07` | loops | until freed | Soft drifting smoke from a single puff picture. | puff_soft_07 |
| `smoke_dark_01` | loops | until freed | A column of rolling smoke. | smoke_dark_01 |
| `smoke_dark_02` | loops | until freed | A column of rolling smoke. | smoke_dark_02 |
| `smoke_dark_03` | loops | until freed | A column of rolling smoke. | smoke_dark_03 |
| `smoke_disc_01` | loops | until freed | A column of rolling smoke. | smoke_disc_01 |
| `smoke_roll_01` | loops | until freed | A column of rolling smoke. | smoke_roll_01 |
| `smoke_roll_02` | loops | until freed | A column of rolling smoke. | smoke_roll_02 |
| `smoke_roll_03` | loops | until freed | A column of rolling smoke. | smoke_roll_03 |
| `smoke_roll_04` | loops | until freed | A column of rolling smoke. | smoke_roll_04 |
| `smoke_roll_05` | loops | until freed | A column of rolling smoke. | smoke_roll_05 |
| `smoke_roll_06` | loops | until freed | A column of rolling smoke. | smoke_roll_06 |
| `smoke_roll_07` | loops | until freed | A column of rolling smoke. | smoke_roll_07 |
| `smoke_roll_08` | loops | until freed | A column of rolling smoke. | smoke_roll_08 |
| `smoke_roll_09` | loops | until freed | A column of rolling smoke. | smoke_roll_09 |
| `steam_loop_01` | loops | until freed | Steam or pale smoke lifting off. | steam_loop_01 |
| `wisp_smoke_01` | one-shot | 2.7 s | A puff of smoke that billows and thins. | wisp_smoke_01 |
| `wisp_smoke_02` | loops | until freed | A column of rolling smoke. | wisp_smoke_02 |
| `wisp_smoke_03` | loops | until freed | A column of rolling smoke. | wisp_smoke_03 |
| `wisp_smoke_04` | loops | until freed | A column of rolling smoke. | wisp_smoke_04 |

## Explosions: composed effects

| Effect | Kind | Lasts | What it is | Textures |
|---|---|---|---|---|
| `airburst` | one-shot | 2.4 s | An explosion in the air: no ring on the ground, no debris. | blast_11, fire_burst_02, glow_warm_02 |
| `debris_burst` | one-shot | 2.4 s | Chunks and dust thrown out, no fire: something breaking. | debris_bits_01, smoke_burst_05 |
| `explosion_fiery` | one-shot | 2.2 s | Mostly fire: fuel, a firebomb. | blast_14, ember_bits_01, fire_burst_01 |
| `explosion_large` | one-shot | 4.0 s | A big one, with a column of smoke left standing after it. | blast_02, debris_bits_01, fire_burst_04, glow_warm_02, ring_02, ring_cloud_01, smoke_dark_01 |
| `explosion_magic` | one-shot | 1.4 s | A blue-white burst, for something unnatural going off. | burst_white_01, ring_02 |
| `explosion_medium` | one-shot | 2.6 s | A barrel going up. | blast_07, debris_bits_01, fire_burst_03, glow_warm_02, ring_02 |
| `explosion_small` | one-shot | 2.2 s | A small explosion: a grenade, a pot of powder. | blast_05, debris_bits_01, glow_warm_02, ring_02 |
| `explosion_smoky` | one-shot | 3.0 s | Mostly smoke and dirt: a charge under earth. | blast_15, blast_18, debris_bits_01, dust_streak_01 |
| `explosion_sparks` | one-shot | 1.4 s | A crack and a shower of sparks, no fireball. | glow_warm_02, ring_02, spark_burst_01 |
| `muzzle_flash` | one-shot | 0.3 s | A short hard flash with a lick of smoke, along x. | glow_streak_01, smoke_burst_06 |
| `shockwave` | one-shot | 0.8 s | The ring alone: a blast felt, not seen. | ring_01, ring_02 |
| `smoke_ring_burst` | one-shot | 2.4 s | Smoke thrown outward in a ring. | puff_soft_03, ring_cloud_01 |

## Explosions: one per texture

| Effect | Kind | Lasts | What it is | Textures |
|---|---|---|---|---|
| `blast_01` | one-shot | 2.5 s | A whole explosion from one book: flash, fireball, smoke. | blast_01 |
| `blast_02` | one-shot | 2.5 s | A whole explosion from one book: flash, fireball, smoke. | blast_02 |
| `blast_03` | one-shot | 2.5 s | A whole explosion from one book: flash, fireball, smoke. | blast_03 |
| `blast_04` | one-shot | 1.9 s | A whole explosion from one book: flash, fireball, smoke. | blast_04 |
| `blast_05` | one-shot | 2.5 s | A whole explosion from one book: flash, fireball, smoke. | blast_05 |
| `blast_06` | one-shot | 2.5 s | A whole explosion from one book: flash, fireball, smoke. | blast_06 |
| `blast_07` | one-shot | 2.5 s | A whole explosion from one book: flash, fireball, smoke. | blast_07 |
| `blast_08` | one-shot | 2.5 s | A whole explosion from one book: flash, fireball, smoke. | blast_08 |
| `blast_09` | one-shot | 2.5 s | A whole explosion from one book: flash, fireball, smoke. | blast_09 |
| `blast_10` | one-shot | 2.5 s | A whole explosion from one book: flash, fireball, smoke. | blast_10 |
| `blast_11` | one-shot | 2.5 s | A whole explosion from one book: flash, fireball, smoke. | blast_11 |
| `blast_12` | one-shot | 2.5 s | A whole explosion from one book: flash, fireball, smoke. | blast_12 |
| `blast_13` | one-shot | 2.5 s | A whole explosion from one book: flash, fireball, smoke. | blast_13 |
| `blast_14` | one-shot | 2.5 s | A whole explosion from one book: flash, fireball, smoke. | blast_14 |
| `blast_15` | one-shot | 2.5 s | A whole explosion from one book: flash, fireball, smoke. | blast_15 |
| `blast_16` | one-shot | 2.5 s | A whole explosion from one book: flash, fireball, smoke. | blast_16 |
| `blast_17` | one-shot | 1.9 s | A whole explosion from one book: flash, fireball, smoke. | blast_17 |
| `blast_18` | one-shot | 1.9 s | A whole explosion from one book: flash, fireball, smoke. | blast_18 |
| `burst_white_01` | one-shot | 1.0 s | A burst of fire that swells and breaks up. | burst_white_01 |
| `debris_bits_01` | one-shot | 2.2 s | Chunks thrown out and falling. | debris_bits_01 |
| `ring_01` | one-shot | 0.7 s | A shock ring that spreads and fades. | ring_01 |
| `ring_02` | one-shot | 0.7 s | A shock ring that spreads and fades. | ring_02 |
| `ring_cloud_01` | one-shot | 0.7 s | A shock ring that spreads and fades. | ring_cloud_01 |
| `smoke_burst_01` | one-shot | 1.0 s | A puff of smoke that billows and thins. | smoke_burst_01 |
| `smoke_burst_02` | one-shot | 1.5 s | A puff of smoke that billows and thins. | smoke_burst_02 |
| `smoke_burst_03` | one-shot | 1.5 s | A puff of smoke that billows and thins. | smoke_burst_03 |
| `smoke_burst_04` | one-shot | 1.0 s | A puff of smoke that billows and thins. | smoke_burst_04 |
| `smoke_burst_05` | one-shot | 1.0 s | A puff of smoke that billows and thins. | smoke_burst_05 |
| `smoke_burst_06` | one-shot | 1.0 s | A puff of smoke that billows and thins. | smoke_burst_06 |
| `spark_burst_01` | one-shot | 0.6 s | A burst of sparks. | spark_burst_01 |

## Textures

| Texture | Grid | Frames | Size | Kind |
|---|---|---|---|---|
| `blast_01` | 12 x 7 | 84 | 3072 x 3072 | blast |
| `blast_02` | 12 x 7 | 84 | 3072 x 3072 | blast |
| `blast_03` | 12 x 7 | 84 | 3072 x 1536 | blast |
| `blast_04` | 8 x 8 | 64 | 2048 x 2048 | blast |
| `blast_05` | 12 x 7 | 84 | 3072 x 1536 | blast |
| `blast_06` | 12 x 7 | 84 | 3072 x 1536 | blast |
| `blast_07` | 12 x 7 | 84 | 3072 x 1536 | blast |
| `blast_08` | 12 x 7 | 84 | 3072 x 1536 | blast |
| `blast_09` | 12 x 7 | 84 | 3072 x 1536 | blast |
| `blast_10` | 12 x 7 | 84 | 3072 x 1536 | blast |
| `blast_11` | 12 x 7 | 84 | 3072 x 1536 | blast |
| `blast_12` | 12 x 7 | 84 | 3072 x 1536 | blast |
| `blast_13` | 12 x 7 | 84 | 3072 x 1536 | blast_smoke |
| `blast_14` | 12 x 7 | 84 | 3072 x 1536 | blast |
| `blast_15` | 12 x 7 | 84 | 3072 x 1536 | blast_smoke |
| `blast_16` | 12 x 7 | 84 | 3072 x 1536 | blast |
| `blast_17` | 8 x 8 | 64 | 2048 x 2048 | blast |
| `blast_18` | 8 x 8 | 64 | 2048 x 2048 | blast |
| `burst_white_01` | 6 x 6 | 36 | 2048 x 2048 | fire_burst_grey |
| `candle_loop_01` | 16 x 8 | 128 | 2048 x 2048 | flame_loop |
| `candle_still_01` | 1 x 1 | 1 | 256 x 256 | still |
| `debris_bits_01` | 2 x 2 | 4 | 256 x 256 | bits_debris |
| `dust_bits_01` | 2 x 2 | 4 | 256 x 256 | bits_dust |
| `dust_streak_01` | 6 x 12 | 72 | 2048 x 1024 | streak |
| `ember_bits_01` | 2 x 2 | 4 | 256 x 256 | bits_ember |
| `fire_burst_01` | 6 x 6 | 36 | 2048 x 2048 | fire_burst |
| `fire_burst_02` | 8 x 8 | 64 | 2048 x 2048 | fire_burst |
| `fire_burst_03` | 8 x 8 | 64 | 2048 x 2048 | fire_burst |
| `fire_burst_04` | 8 x 8 | 64 | 2048 x 2048 | fire_burst |
| `fire_burst_05` | 6 x 6 | 36 | 2048 x 2048 | fire_burst |
| `fire_burst_06` | 7 x 7 | 49 | 2048 x 2048 | fire_burst |
| `fireball_trail_01` | 4 x 16 | 64 | 2048 x 2048 | fireball |
| `flame_ignite_01` | 10 x 10 | 100 | 2048 x 2048 | flame_once |
| `flame_ignite_02` | 11 x 11 | 121 | 2048 x 2048 | flame_once |
| `flame_loop_01` | 8 x 8 | 64 | 2048 x 2048 | flame_loop |
| `flame_loop_02` | 16 x 8 | 128 | 2048 x 2048 | flame_loop |
| `flame_loop_03` | 8 x 8 | 64 | 2048 x 2048 | flame_loop |
| `flame_loop_04` | 8 x 8 | 64 | 1024 x 2048 | flame_loop_grey |
| `flame_loop_05` | 12 x 6 | 72 | 2048 x 2048 | flame_loop_grey |
| `flame_loop_06` | 8 x 8 | 64 | 2048 x 2048 | flame_loop |
| `flame_puff_01` | 7 x 7 | 49 | 2048 x 2048 | flame_once |
| `flame_puff_02` | 6 x 6 | 36 | 2048 x 2048 | flame_once |
| `flame_puff_03` | 10 x 5 | 50 | 2048 x 2048 | flame_once |
| `flame_puff_04` | 6 x 6 | 36 | 2048 x 2048 | flame_once |
| `flame_still_01` | 1 x 1 | 1 | 256 x 256 | still |
| `glow_soft_01` | 1 x 1 | 1 | 512 x 512 | glow |
| `glow_streak_01` | 1 x 1 | 1 | 256 x 256 | glow |
| `glow_warm_01` | 1 x 1 | 1 | 256 x 256 | glow |
| `glow_warm_02` | 1 x 1 | 1 | 256 x 256 | glow |
| `noise_cloud_01` | 1 x 1 | 1 | 1024 x 1024 | tile |
| `noise_cloud_02` | 1 x 1 | 1 | 256 x 256 | tile |
| `noise_fire_01` | 1 x 1 | 1 | 818 x 879 | tile |
| `puff_soft_01` | 1 x 1 | 1 | 256 x 256 | puff |
| `puff_soft_02` | 1 x 1 | 1 | 256 x 256 | puff |
| `puff_soft_03` | 1 x 1 | 1 | 1024 x 1024 | puff |
| `puff_soft_04` | 1 x 1 | 1 | 256 x 256 | puff |
| `puff_soft_05` | 1 x 1 | 1 | 512 x 512 | puff |
| `puff_soft_06` | 1 x 1 | 1 | 256 x 256 | puff |
| `puff_soft_07` | 1 x 1 | 1 | 1024 x 1024 | puff |
| `ring_01` | 1 x 1 | 1 | 512 x 512 | ring |
| `ring_02` | 1 x 1 | 1 | 512 x 512 | ring |
| `ring_cloud_01` | 1 x 1 | 1 | 512 x 512 | ring |
| `smoke_burst_01` | 5 x 5 | 25 | 1024 x 1024 | smoke_once |
| `smoke_burst_02` | 6 x 6 | 36 | 2048 x 2048 | smoke_once |
| `smoke_burst_03` | 6 x 6 | 36 | 2048 x 2048 | smoke_once |
| `smoke_burst_04` | 5 x 5 | 25 | 2048 x 2048 | smoke_once |
| `smoke_burst_05` | 5 x 5 | 25 | 2048 x 2048 | smoke_once |
| `smoke_burst_06` | 5 x 5 | 25 | 2048 x 2048 | smoke_once |
| `smoke_dark_01` | 8 x 8 | 64 | 1024 x 1024 | smoke_loop |
| `smoke_dark_02` | 6 x 6 | 36 | 2048 x 2048 | smoke_loop |
| `smoke_dark_03` | 6 x 6 | 36 | 2048 x 2048 | smoke_loop |
| `smoke_disc_01` | 16 x 4 | 64 | 2048 x 1024 | smoke_loop |
| `smoke_roll_01` | 8 x 8 | 64 | 1024 x 1024 | smoke_loop |
| `smoke_roll_02` | 8 x 8 | 64 | 1024 x 1024 | smoke_loop |
| `smoke_roll_03` | 8 x 8 | 64 | 1024 x 1024 | smoke_loop |
| `smoke_roll_04` | 8 x 8 | 64 | 1024 x 1024 | smoke_loop |
| `smoke_roll_05` | 8 x 8 | 64 | 1024 x 1024 | smoke_loop |
| `smoke_roll_06` | 8 x 8 | 64 | 1024 x 1024 | smoke_loop |
| `smoke_roll_07` | 8 x 8 | 64 | 2048 x 2048 | smoke_loop |
| `smoke_roll_08` | 8 x 8 | 64 | 2048 x 2048 | smoke_loop |
| `smoke_roll_09` | 8 x 8 | 64 | 2048 x 2048 | smoke_loop |
| `spark_burst_01` | 3 x 3 | 9 | 1024 x 1024 | spark |
| `steam_loop_01` | 8 x 8 | 64 | 2048 x 2048 | steam |
| `wisp_flame_01` | 2 x 2 | 4 | 1024 x 1024 | bits_fire |
| `wisp_flame_02` | 2 x 2 | 4 | 128 x 128 | bits_fire |
| `wisp_flame_03` | 4 x 4 | 16 | 1024 x 1024 | bits_fire |
| `wisp_flame_04` | 2 x 2 | 4 | 512 x 512 | bits_fire |
| `wisp_smoke_01` | 8 x 8 | 64 | 2048 x 2048 | smoke_once |
| `wisp_smoke_02` | 8 x 8 | 64 | 1024 x 1024 | smoke_loop |
| `wisp_smoke_03` | 8 x 8 | 64 | 1024 x 1024 | smoke_loop |
| `wisp_smoke_04` | 8 x 8 | 64 | 1024 x 2048 | smoke_loop |
