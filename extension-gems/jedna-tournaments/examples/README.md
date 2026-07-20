# Jedna Agent Arena

This directory is the supported workspace for playing, comparing, and training
Jedna agents. It intentionally keeps three agent paths:

| Agent | Command | Purpose |
| --- | --- | --- |
| Simple | `./simple_agent.rb` | Small protocol reference and baseline |
| Crushing | `./crushing_agent.rb` | Best hand-written two-player strategy |
| PPO | `python3 rl_agent.py --policy sb3 --model MODEL.zip` | Trainable MaskablePPO agent |

All commands below assume the current directory is
`extension-gems/jedna-tournaments/examples`.

## Setup

Install the Ruby dependencies from the extension gem directory:

```bash
cd extension-gems/jedna-tournaments
bundle install
cd examples
```

The Ruby agents need no additional dependencies. PPO development needs Python
3.10+ and the optional learning stack:

```bash
python3 -m venv .venv
. .venv/bin/activate
python -m pip install stable-baselines3 sb3-contrib gymnasium torch
```

Virtual environments, model archives, logs, and checkpoints are ignored by
Git. Store generated training data outside the source tree or in an ignored
directory.

## Play and benchmark

Run one verbose game through the real JSON-lines process boundary:

```bash
bundle exec ruby run_single_game.rb './simple_agent.rb' './crushing_agent.rb'
```

Run the supported arena matchup. The configuration alternates the starting
player across 1,000 games:

```bash
bundle exec ruby tournament_runner.rb arena.yaml
```

For fast, seeded comparisons between the two Ruby policies:

```bash
bundle exec ruby benchmark_agents.rb crushing simple 5000
```

`benchmark_agents.rb` uses the real game engine in-process, alternates the
requested first player, and seeds game `n` with `12345 + n`. Use the process
tournament as the final integration check because it also tests agent startup,
timeouts, and protocol I/O.

## Agents

### Simple

`simple_agent.rb` plays the first legal card, draws when allowed, and otherwise
passes. It is deliberately small enough to serve as the canonical protocol
example.

### Crushing

`crushing_agent.rb` is the strongest maintained hand-written agent. Its
baseline probability/chain strategy lives in
`crushing_agent/baseline_strategy.rb`; that support file is not a separate
agent. Crushing adds tactics for two-player skip turns, duplicate-card plays,
and pressure when the opponent reaches one card.

In the seeded review benchmark it beat the retired Smart and Smarter agents at
52.10% and 52.42% respectively over 5,000 games per matchup. It also scored
55.67% over 300 games against the latest stochastic PPO checkpoint. Those old
agents and matchup artifacts were removed after establishing Crushing as the
maintained replacement.

Against the maintained Simple baseline, Crushing won 2,853 of 5,000 seeded
games (57.06%, 95% Wilson interval 55.68–58.43%). Reproduce that result with
the benchmark command above.

### PPO scaffold

The PPO path is modular so training and protocol inference share the same
encoding:

- `rl_agent.py`: JSON-lines command-line entry point.
- `rl_agent/encoding.py`: fixed observation/action encoding and action masks.
- `rl_agent/policy.py`: random masked policy and MaskablePPO adapter.
- `rl_agent/agent.py`: engine-message policy loop.
- `rl_agent/rl_env.py`: Gymnasium environment backed by the Ruby engine.
- `rl_agent/train_sb3.py`: behavior cloning, optional DAgger aggregation, PPO training, checkpoints, and evaluation.
- `rl_agent/eval_sb3.py`: deterministic or stochastic checkpoint evaluation.
- `rl_agent/debug_one_game.py`: one-episode watchdog/debug runner.
- `rl_agent/test_encoding.py`: dependency-free encoding and mask regression tests.
- `rl_agent/TRAINING.md`: improved curriculum, reproducible commands, and results.
- `engine_bridge.rb`: clean JSON bridge between Gymnasium and the game engine.

The repository-wide current recommendation and research decision record live
in [`../../../BOT_RESEARCH.md`](../../../BOT_RESEARCH.md). This README describes
the available agents; `rl_agent/TRAINING.md` retains the detailed training
commands and historical tables.

The observation key `war_cards_to_draw` remains in the model input for
feature-name continuity, but it is populated from the engine protocol's
`stacked_cards` field. The complete v3 observation space is not archive-
compatible with earlier checkpoints.

The v3 neural observation supports one shared policy for 2-10 players. It keeps
nine turn-ordered, padded opponent hand counts plus a mask, total player count,
and explicit next, second-next, and Reverse-target counts. The action layout is
still the same 110 draw/pass/exact-card/double-card choices. Changing the input
shape makes v1/v2 checkpoints incompatible; retrain them. See
[rl_agent/TRAINING.md](rl_agent/TRAINING.md) for the rationale and curriculum.

## PPO workflow

First verify the Python protocol path without a model:

```bash
bundle exec ruby run_single_game.rb \
  'python3 rl_agent.py --policy random' \
  './simple_agent.rb'
```

Run the Python agent tests:

```bash
python3 -m unittest discover -s rl_agent -p 'test_*.py' -t .
```

The trainer keeps one Ruby engine and a prewarmed opponent process for every
seat up to the configured maximum alive in each vectorized environment.
Smaller tables leave extra seats idle instead of restarting them later. Table
size is sampled uniformly per episode from `--player-counts` (default `2-10`). Use
`--player-count-weights '2:5,3:1,4:1,5:1,6:1,7:1'` for relative sampling
weights; when present, that mapping supplies both the table sizes and their
probabilities. This avoids process restarts while retaining independent state
for every seat. Use `--per-game-engine` only for an opponent that requires a
fresh process for every game.

When resuming into the same logical training schedule, add
`--preserve-timestep-count`. Checkpoint names then retain the loaded model's
step count while `--timesteps` specifies how many additional steps to run.

Train against Simple while iterating quickly:

```bash
python3 -m rl_agent.train_sb3 \
  --opponent './simple_agent.rb' \
  --player-counts 2-10 \
  --timesteps 100000 \
  --envs 4 \
  --model /tmp/jedna_maskppo \
  --checkpoint-dir /tmp/jedna-checkpoints \
  --checkpoint-every 50000 \
  --eval-freq 50000 \
  --eval-episodes 200
```

Then train or fine-tune against Crushing for a stronger curriculum:

```bash
python3 -m rl_agent.train_sb3 \
  --opponent './crushing_agent.rb' \
  --player-counts 2-10 \
  --timesteps 1000000 \
  --envs 4 \
  --model /tmp/jedna_maskppo-vs-crushing
```

Evaluate a model deterministically:

```bash
python3 -m rl_agent.eval_sb3 \
  --opponent './crushing_agent.rb' \
  --model /tmp/jedna_maskppo-vs-crushing.zip \
  --player-counts 2-10 \
  --episodes 1000
```

`--episodes` is per table size; output includes each size and the macro-average
win rate. Add `--stochastic` to measure sampled policy behavior. Report the
mode, per-size game and win counts, starting-player policy, and seed policy.

Use a trained PPO agent in a YAML tournament like this:

```yaml
agents:
  Crushing: './crushing_agent.rb'
  PPO: 'python3 rl_agent.py --policy sb3 --model /tmp/model.zip'
```

## Arena protocol and tools

Agents receive one JSON object per line and must emit exactly one action object
for each `request_action`. Diagnostic output belongs on stderr; stdout is
reserved for protocol messages. See
[automated_play.md](../../../automated_play.md) for the complete state and
action contract.

- `run_single_game.rb` is the verbose process-level debugger.
- `tournament_runner.rb` runs YAML round-robin tournaments.
- `benchmark_agents.rb` is the fast deterministic Ruby-policy benchmark.
- `arena.yaml` is the maintained example configuration.

Treat configured commands as trusted input. The process runner executes command
strings and is not a sandbox for untrusted programs.

Keep `turn_timeout` at 10 seconds or higher for PPO agents: importing Torch and
loading a checkpoint makes the first action slower than later predictions.
