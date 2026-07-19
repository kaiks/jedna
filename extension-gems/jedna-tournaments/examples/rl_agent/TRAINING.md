# Neural Agent Training

## Why the original PPO lost to Crushing

A neural network has enough capacity to represent a strong policy, but that
does not make reinforcement learning automatically stronger than a hand-written
program. The original loop had several concrete disadvantages:

- It received only `+1` or `-1` at the end of a long game.
- Its observation aggregated colors and figures even though its output selected
  exact cards. Different hands therefore looked identical to the network.
- The stacked-card feature read a protocol field that the engine did not emit.
- The action space could not express Jedna's double-play rule.
- Training started from random behavior against one fixed opponent.
- Training and standalone inference used different observation shapes.

The v2 loop fixed those issues. It added exact 54-card hand, playable-card, and
top-card vectors; active wild color, post-draw state, legal double-play actions,
hand-progress reward shaping, deterministic engine seeds, mixed opponents, and
a behavior-cloning warm start from any JSON-lines expert.

The v3 loop generalizes that policy to 2-10 players. Every observation contains
nine opponent-count slots in active turn order, a padding mask, total player
count, and explicit next, second-next, and Reverse-target counts. Reward
bookkeeping follows opponent IDs rather than array positions and normalizes the
opponent component by table size. The bridge owns one process per opponent seat
and safely discards the rare game that ends before the learner receives its
first decision.

The 110-action layout is unchanged, but the v3 observation shape is
intentionally incompatible with both v1 and v2 checkpoints. Retrain rather
than resume those models.

## Engine lifecycle

Each training environment keeps one Ruby engine and prewarms the opponent
processes required by its largest configured table. The bridge creates a new
game for every seeded `reset`, leaves seats outside a smaller table idle, and
sends each active opponent a `game_reset` message. Processes are stopped only
when the environment closes. Use `--per-game-engine` for a third-party opponent
that cannot reset its own cross-game state.

## Recommended curriculum

All commands assume this directory's parent (`examples/`) is the current
working directory.

First collect Crushing demonstrations and behavior-clone them without PPO:

```bash
python3 -m rl_agent.train_sb3 \
  --opponent './crushing_agent.rb' \
  --expert './crushing_agent.rb' \
  --expert-opponent './crushing_agent.rb' \
  --player-counts 2-10 \
  --expert-steps 7500 \
  --bc-epochs 6 \
  --timesteps 0 \
  --envs 1 \
  --model /tmp/jedna_rl_v3
```

This writes `/tmp/jedna_rl_v3_bc.zip`. Fine-tune it against a mixture of easy
and strong opponents:

```bash
python3 -m rl_agent.train_sb3 \
  --opponent './simple_agent.rb' \
  --opponent './crushing_agent.rb' \
  --resume /tmp/jedna_rl_v3_bc.zip \
  --player-counts 2-10 \
  --timesteps 250000 \
  --envs 8 \
  --n-steps 256 \
  --batch-size 256 \
  --ppo-epochs 5 \
  --reward-scale 0.05 \
  --checkpoint-dir /tmp/jedna_rl_v3_checkpoints \
  --checkpoint-every 25000 \
  --eval-freq 25000 \
  --eval-episodes 500 \
  --eval-opponent './crushing_agent.rb' \
  --model /tmp/jedna_rl_v3_finetuned
```

Use fewer Crushing workers if its chain search saturates the machine. The
training command is trusted local configuration: expert and opponent strings
are executed as shell commands.

Table sizes are sampled uniformly per episode unless
`--player-count-weights` supplies explicit relative weights such as
`2:5,3:1,4:1,5:1,6:1,7:1`. In-training evaluation still reports every
configured size and selects `best_model.zip` by the unweighted macro-average,
so the training distribution does not bias checkpoint comparison.

### DAgger warm start

Plain behavior cloning sees only states reached by the expert. DAgger also
queries the expert on states reached by the learner, aggregates those labels,
and retrains on the growing dataset. This targets compounding imitation errors;
it cannot exceed the teacher through supervised learning alone, so PPO remains
the fine-tuning stage. See the original [DAgger
paper](https://proceedings.mlr.press/v15/ross11a.html).

This command matches the 7,500 expert-query and 180 supervised-update budget
used by the comparison below: 1,500 initial labels and six rounds of 1,000
learner-distribution labels.

```bash
python3 -m rl_agent.train_sb3 \
  --opponent './crushing_agent.rb' \
  --expert './crushing_agent.rb' \
  --expert-opponent './crushing_agent.rb' \
  --expert-steps 1500 \
  --bc-epochs 5 \
  --dagger-rounds 6 \
  --dagger-steps 1000 \
  --dagger-beta-schedule 0.75,0.50,0.25,0.10,0,0 \
  --dagger-updates 25 \
  --timesteps 100000 \
  --envs 4 \
  --n-steps 256 \
  --batch-size 256 \
  --ppo-epochs 5 \
  --model /tmp/jedna_dagger
```

Without an explicit beta schedule, `--dagger-beta-start` is linearly annealed
to zero. Beta is the probability of executing the expert action while still
recording the expert label at every visited state.

## Multiplayer v3 checkpoint from 2026-07-19

The first end-to-end v3 run used 7,500 Crushing demonstrations, six
behavior-cloning epochs, and 100,352 PPO steps across four environments. Each
episode sampled a table size uniformly from 2 through 10; the PPO workers were
split evenly between Simple and Crushing. The resulting ignored model archive
is `../../models/jedna_multiplayer_v3.zip`. Its tracked
`../../models/jedna_multiplayer_v3.json` manifest records the full training
configuration, observation/action architecture, byte size, SHA-256 digest,
seeds, and Wilson intervals.

The following deterministic smoke evaluation used 25 held-out games per
opponent and table size. These samples validate the complete 2-10-player path;
their intervals are intentionally broad and are not a strength-promotion
claim.

| Players | vs Simple | vs Crushing |
| ---: | ---: | ---: |
| 2 | 11/25 (44%) | 11/25 (44%) |
| 3 | 10/25 (40%) | 7/25 (28%) |
| 4 | 5/25 (20%) | 3/25 (12%) |
| 5 | 6/25 (24%) | 3/25 (12%) |
| 6 | 5/25 (20%) | 1/25 (4%) |
| 7 | 4/25 (16%) | 5/25 (20%) |
| 8 | 6/25 (24%) | 1/25 (4%) |
| 9 | 3/25 (12%) | 3/25 (12%) |
| 10 | 2/25 (8%) | 1/25 (4%) |
| Macro average | 23.11% | 15.56% |

## Brief-run result from 2026-07-10

The results below are historical v2 two-player measurements. Their checkpoints
cannot be loaded by the v3 environment.

The development run used 7,500 Crushing-vs-Crushing expert decisions, six
behavior-cloning epochs, and 16,384 PPO steps against Crushing. Evaluation used
deterministic engine seeds and randomized starting players.

| Checkpoint | Opponent | Mode | Wins | Win rate | 95% Wilson interval |
| --- | --- | --- | ---: | ---: | ---: |
| Behavior cloned | Simple | deterministic | 270/500 | 54.00% | 49.62–58.32% |
| Behavior cloned | Crushing | deterministic | 212/500 | 42.40% | 38.14–46.77% |
| PPO fine-tuned | Simple | deterministic | 278/500 | 55.60% | 51.22–59.90% |
| PPO fine-tuned | Crushing | deterministic | 214/500 | 42.80% | 38.53–47.18% |
| PPO fine-tuned | Crushing | stochastic | 144/300 | 48.00% | 42.41–53.64% |

The short run improves on Simple and the stochastic policy is statistically
consistent with an even match against Crushing, but it does **not** demonstrate
that the neural policy beats Crushing. Longer mixed-opponent training, repeated
seeds, and checkpoint selection on held-out seeds are still required.

The locally generated fine-tuned model is stored at
`../../models/jedna_rl_v2_finetuned.zip`. Model archives are ignored by Git.

## DAgger experiment from 2026-07-10

A three-seed pilot promoted DAgger to a larger run. The larger comparison used
the same 7,500 expert queries, 180 supervised optimizer updates, and 100,000 PPO
steps per seed for both arms. On a 1,000-game validation range per seed, the
aggregate results were:

| Warm start | Mode | Wins | Win rate |
| --- | --- | ---: | ---: |
| Behavior cloning | deterministic | 1,471/3,000 | 49.03% |
| DAgger | deterministic | 1,521/3,000 | 50.70% |
| Behavior cloning | stochastic | 1,428/3,000 | 47.60% |
| DAgger | stochastic | 1,474/3,000 | 49.13% |

The best validation seed was then frozen and evaluated on a new 10,000-game
range (`--seed 14000000`). It was slightly ahead of the existing PPO, but the
gain did not clear a statistical promotion bar and neither policy beat
Crushing:

| Checkpoint | Mode | Wins | Win rate | 95% Wilson interval |
| --- | --- | ---: | ---: | ---: |
| Existing PPO | deterministic | 4,756/10,000 | 47.56% | 46.58–48.54% |
| DAgger + PPO | deterministic | 4,821/10,000 | 48.21% | 47.23–49.19% |
| Existing PPO | stochastic | 4,594/10,000 | 45.94% | 44.96–46.92% |
| DAgger + PPO | stochastic | 4,639/10,000 | 46.39% | 45.41–47.37% |

The DAgger checkpoint was therefore not promoted; the existing PPO remains in
`../../models/`. The training option is retained because it improved the
matched-budget three-seed aggregate and is useful for future controlled runs.

Two smaller ablations were rejected before the long run. Four public-action
history slots improved deterministic play by only 0.56 points over a same-shape
zero-history control and reduced stochastic play by 1.67 points. Gamma-correct
potential shaping improved deterministic play by 0.56 points but reduced
stochastic play by 1.33 points. Their code is intentionally not retained.

For larger algorithm changes, [NFSP](https://arxiv.org/abs/1603.01121) is a
closer fit to the current online simulator than [Deep
CFR](https://arxiv.org/abs/1811.00164), which needs explicit game-tree
traversal and counterfactual reach values. A recent [imperfect-information RL
benchmark](https://arxiv.org/abs/2502.08938) also supports keeping policy
gradient baselines while evaluation and observation ablations are tightened.

## Evaluation

Use at least 500 held-out games and report the seed, mode, and confidence
interval:

```bash
python3 -m rl_agent.eval_sb3 \
  --opponent './crushing_agent.rb' \
  --model /tmp/jedna_rl_v3_finetuned.zip \
  --player-counts 2-10 \
  --episodes 1000 \
  --seed 6000000
```

`--episodes` applies to each table size. Add `--stochastic` to sample actions.
Do not select a checkpoint and report its final result on the same seeds;
reserve a second seed range for final testing.

### Selecting a long-run checkpoint

Use `benchmark_checkpoints.py` after training has finished. It first reports
the leader from the in-training log, then evaluates every numbered checkpoint
against Crushing on a fresh 5,000-game seed range. It selects the held-out
leader from that screen and validates it on a second fresh range against both
Crushing and every other checkpoint.

This legacy round-robin tooling measures two-player strength only. Use
`eval_sb3 --player-counts 2-10` as the multiplayer promotion gate.

```bash
cd examples
python3 -m rl_agent.benchmark_checkpoints \
  --checkpoint-dir ../checkpoints/overnight-dagger \
  --games 5000 \
  --report ../checkpoints/overnight-dagger/benchmark.json
```

The default examines every `checkpoint_<steps>_steps.zip` archive. For a quick
triage run, use `--candidate-limit 5`; this retains the five highest ranked
log-evaluated checkpoints. `--skip-head-to-head` performs only the Crusher
screen. Do not run the full benchmark beside active training: both use CPU and
the checkpoint directory is still being written.

At a 50% win rate, 5,000 games give a 95% Wilson interval about +/- 1.4
percentage points wide. That is a useful promotion bar, but it does not make a
one-point advantage conclusive, especially when comparing many checkpoints.

### Finalist round robin

After reducing the field, use the separate home-and-away round robin. Its
default finalists are the 6M, 17.5M, 18M, and 18.5M snapshots. Every finalist
plays 20,000 games against Crushing, and every checkpoint pairing plays 20,000
games split evenly between the two agent positions. The script atomically
updates its report after every completed matchup; pass `--resume` after an
interruption.

```bash
cd examples
mise exec ruby@4.0.5 -- python3 -m rl_agent.finalist_round_robin \
  --checkpoint-dir ../checkpoints/overnight-dagger \
  --games-per-pair 20000 \
  --report ../checkpoints/overnight-dagger/finalist_round_robin.json
```
