# Jedna Bot Research

This is the repository-wide status and decision record for automated Jedna
players. It summarizes what is currently recommended, what was tried, and what
the evidence does and does not establish. Implementation commands and full
historical tables remain in
[`extension-gems/jedna-tournaments/examples/rl_agent/TRAINING.md`](extension-gems/jedna-tournaments/examples/rl_agent/TRAINING.md).
The bot protocol is specified in [`automated_play.md`](automated_play.md).

## Current recommendation

As of 2026-07-20 there are two maintained reference strategies:

- **Crushing** is the strongest maintained hand-written agent. It is cheap to
  run, explainable, and remains the fixed training and evaluation opponent.
  Its tactics are especially tailored to two-player games. Against Simple it
  won 2,853/5,000 seeded games (57.06%, Wilson 95% 55.68-58.43%).
- **Multiplayer v3 MaskablePPO at 9.75M steps** is the current neural deployment
  candidate. The canonical local archive is
  `extension-gems/jedna-tournaments/models/jedna_multiplayer_v3.zip`, with
  SHA-256
  `716e687a637632e286e0050b1e013ded46af95033bf5a45901163cc0c141aa15`.
  It is the best observed checkpoint for deterministic play against Crushing
  when 2-, 3-, and 4-player tables are weighted equally.

The neural model is a **best observed deployment candidate, not a proven unique
best policy**. Its finalist lead over the adjacent 10M checkpoints was not
statistically significant. The v3 encoder accepts 2-10 players, but the current
strength promotion covers only 2-4 players. Supporting a topology and having a
strong result on that topology are separate claims.

The old 2026-07-19 v3 model is retained locally as
`jedna_multiplayer_v3_20260719.zip`. Model archives and evaluation directories
are intentionally ignored by Git; the adjacent JSON manifest records the
canonical model's reproducible identity and measured results.

## Current 9.75M result

The 2026-07-20 run resumed a prior multiplayer-v3 checkpoint and fine-tuned
only against Crushing. Its configured training distribution was 50% two-player
games and 10% each for 3-7 players:

```bash
python3 -m rl_agent.train_sb3 \
  --opponent './crushing_agent.rb' \
  --resume "$PREVIOUS" \
  --player-count-weights '2:5,3:1,4:1,5:1,6:1,7:1' \
  --timesteps 10000000 \
  --envs 4 \
  --reward-scale 0.05 \
  --checkpoint-dir "$RUN" \
  --checkpoint-every 250000 \
  --model "$RUN/final_10m"
```

The command omitted `--eval-freq`, so all checkpoint selection happened after
training:

1. Forty numbered checkpoints plus `final_10m` were screened on seed range
   20,000,000 with 50 games at every table size from 2 through 7.
2. The screen was re-ranked for the deployment target of equally weighted
   2-4-player tables.
3. Six finalists were evaluated on a fresh seed range beginning at 30,000,000,
   with 4,000 games per table size and deterministic inference.

| Checkpoint | 2 players | 3 players | 4 players | Macro | Total |
| --- | ---: | ---: | ---: | ---: | ---: |
| 9.75M | 54.45% | 35.38% | 27.10% | **38.98%** | 4,677/12,000 |
| 10M numbered | 53.12% | 35.85% | 26.90% | 38.62% | 4,635/12,000 |
| final 10M (10,000,672 steps) | 52.80% | 35.68% | 26.82% | 38.43% | 4,612/12,000 |
| 2M | 52.30% | 35.25% | 26.17% | 37.91% | 4,549/12,000 |
| 6.5M | 53.08% | 34.85% | 24.85% | 37.59% | 4,511/12,000 |
| 3.5M | 51.98% | 35.17% | 24.70% | 37.28% | 4,474/12,000 |

The 9.75M lead was 0.35 percentage points over numbered 10M and 0.54 points
over final 10M. Unpaired two-proportion checks give p=0.58 and p=0.39
respectively. Even before correcting for multiple comparisons, these are ties.
The current evaluator uses identical seeds but discards per-game outcomes, so
it cannot exploit paired McNemar testing after the run.

An independent confirmation on seed range 40,000,000 reproduced the selected
model's result: 4,669/12,000 (38.91% macro; aggregate Wilson 95%
38.04-39.78%). By table size it won 2,186/4,000 at two players (54.65%),
1,407/4,000 at three players (35.17%), and 1,076/4,000 at four players
(26.90%). This fresh range is the reportable performance estimate. It confirms
the 9.75M policy's measured strength, but does not make its small selection
lead over the unevaluated-on-this-range 10M variants statistically unique.

## Research history

### Hand-written baseline

Simple established the protocol baseline by playing the first legal card.
Crushing added chain search, two-player skip handling, double-play tactics,
wild-color choice, and one-card pressure. It replaced the retired Smart and
Smarter agents after 5,000-game seeded comparisons and remains the stable
opponent used to measure learned policies.

### Original PPO and v2

The first PPO agent had terminal-only rewards, lossy aggregate observations, a
broken stacked-card feature, no double-play action, a single fixed opponent,
and different training/inference shapes. V2 corrected those issues with exact
card vectors, action masks, shaped hand-progress rewards, deterministic engine
seeds, mixed opponents, and behavior cloning.

On 2026-07-10, the short v2 PPO reached 42.80% deterministic and 48.00%
stochastic against Crushing. The latter had only 300 games and was consistent
with an even match; it did not prove that PPO beat Crushing.

### DAgger and observation ablations

DAgger improved the matched-budget three-seed aggregate over plain behavior
cloning, but its selected checkpoint did not clear the independent promotion
bar. On a new 10,000-game range, DAgger+PPO reached 48.21% deterministic versus
47.56% for the existing PPO; the intervals overlapped and neither beat
Crushing.

Two other ideas were rejected after controlled comparisons:

- Four public-action history slots improved deterministic play by 0.56 points
  but reduced stochastic play by 1.67 points.
- Gamma-correct potential shaping improved deterministic play by 0.56 points
  but reduced stochastic play by 1.33 points.

Their code was removed rather than retaining unsupported complexity.

### Multiplayer v3

V3 introduced one shared 2-10-player observation with nine ordered opponent
slots, padding, total player count, and explicit next/second-next/Reverse target
counts. Reward bookkeeping follows player IDs and normalizes the opponent term
by table size. The observation shape is incompatible with v1 and v2 archives.

The first end-to-end v3 checkpoint on 2026-07-19 used 7,500 Crushing
demonstrations, six behavior-cloning epochs, and 100,352 PPO steps against a
Simple/Crushing mixture across uniformly sampled 2-10-player tables. Its
25-game-per-size smoke test validated the whole topology but was intentionally
too small for promotion. The 2026-07-20 weighted Crusher run produced the
current 9.75M deployment candidate.

## Evaluation rules

Use these rules for future promotion decisions:

1. Define the target before looking at results: opponent panel, deterministic
   or stochastic inference, table sizes, and table-size weights.
2. Use fixed seeds across checkpoints so outcomes can be paired.
3. Use one seed range for screening/selection and a fresh range for final
   reporting. Never present selection performance as an unbiased final score.
4. Report wins, games, seed range, policy mode, per-table rates, macro or
   explicitly weighted aggregate, and confidence intervals.
5. Correct significance tests for the number of checkpoint comparisons. If the
   leaders are unresolved, preserve a tied set instead of declaring an
   absolute winner.
6. Treat `benchmark_checkpoints.py` and `finalist_round_robin.py` as legacy
   two-player tools. Multiplayer promotion currently uses `eval_sb3.py`.

## Highest-value next work

- Extend multiplayer evaluation to write atomic JSON containing every seeded
  outcome, then use paired McNemar tests with Holm correction and resumable
  successive-halving screens.
- Add 5-7-player promotion gates before making strength claims beyond 2-4
  players.
- Evaluate a declared opponent panel rather than optimizing only against
  Crushing; include Simple as a regression guard and consider policy-pool or
  self-play opponents.
- Record the resume checkpoint, complete command line, code revision, Python
  dependency lock, and seed ranges automatically for every run.
- Consider NFSP before Deep CFR if moving beyond PPO: NFSP fits the current
  online simulator, while Deep CFR requires explicit game-tree traversal and
  counterfactual reach values.
