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

The v2 loop fixes those issues. It adds exact 54-card hand, playable-card, and
top-card vectors; active wild color, post-draw state, legal double-play actions,
hand-progress reward shaping, deterministic engine seeds, mixed opponents, and
a behavior-cloning warm start from any JSON-lines expert.

The new observation and 110-action layout are intentionally incompatible with
old PPO checkpoints. Retrain models created before this change.

## Engine lifecycle

Each training environment keeps one Ruby engine and one opponent process alive
across games. The bridge creates a new game for every seeded `reset` and sends
the opponent a `game_reset` message, so the standard bundled agents remain
stateless between episodes without paying process startup cost. Use
`--per-game-engine` for a third-party opponent that cannot reset its own
cross-game state.

## Recommended curriculum

All commands assume this directory's parent (`examples/`) is the current
working directory.

First collect Crushing demonstrations and behavior-clone them without PPO:

```bash
python3 -m rl_agent.train_sb3 \
  --opponent './crushing_agent.rb' \
  --expert './crushing_agent.rb' \
  --expert-opponent './crushing_agent.rb' \
  --expert-steps 7500 \
  --bc-epochs 6 \
  --timesteps 0 \
  --envs 1 \
  --model /tmp/jedna_rl_v2
```

This writes `/tmp/jedna_rl_v2_bc.zip`. Fine-tune it against a mixture of easy
and strong opponents:

```bash
python3 -m rl_agent.train_sb3 \
  --opponent './simple_agent.rb' \
  --opponent './crushing_agent.rb' \
  --resume /tmp/jedna_rl_v2_bc.zip \
  --timesteps 250000 \
  --envs 8 \
  --n-steps 256 \
  --batch-size 256 \
  --ppo-epochs 5 \
  --reward-scale 0.05 \
  --checkpoint-dir /tmp/jedna_rl_v2_checkpoints \
  --checkpoint-every 25000 \
  --eval-freq 25000 \
  --eval-episodes 500 \
  --eval-opponent './crushing_agent.rb' \
  --model /tmp/jedna_rl_v2_finetuned
```

Use fewer Crushing workers if its chain search saturates the machine. The
training command is trusted local configuration: expert and opponent strings
are executed as shell commands.

## Brief-run result from 2026-07-10

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

## Evaluation

Use at least 500 held-out games and report the seed, mode, and confidence
interval:

```bash
python3 -m rl_agent.eval_sb3 \
  --opponent './crushing_agent.rb' \
  --model /tmp/jedna_rl_v2_finetuned.zip \
  --episodes 1000 \
  --seed 6000000
```

Add `--stochastic` to sample actions. Do not select a checkpoint and report its
final result on the same seeds; reserve a second seed range for final testing.
