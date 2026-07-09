# Crushing Agent Benchmark Results

`crushing_agent.rb` extends the existing Smart/Smarter logic with three focused
changes:

- Always use a playable skip in two-player games to retain the turn.
- Double-play identical non-wild cards when legal.
- Prefer WD4 or +2 when the opponent has exactly one card.

## Seeded in-process benchmark

The harness alternates the requested first player and uses seed `12345 + game`
so policy variants see reproducible game sequences.

```bash
bundle exec ruby examples/benchmark_agents.rb crushing smart 5000
bundle exec ruby examples/benchmark_agents.rb crushing smarter 5000
```

| Matchup | Crushing wins | Opponent wins | Win rate | 95% Wilson interval |
| --- | ---: | ---: | ---: | ---: |
| vs Smart | 2,605 | 2,395 | 52.10% | 50.71–53.48% |
| vs Smarter | 2,621 | 2,379 | 52.42% | 51.03–53.80% |

## Subprocess tournament confirmation

These runs use the normal JSON-lines process boundary and alternate who starts.

```bash
bundle exec ruby tournament_runner.rb crushing_vs_smart.yaml
bundle exec ruby tournament_runner.rb crushing_vs_smarter.yaml
```

| Matchup | Crushing wins | Opponent wins | Win rate | 95% Wilson interval |
| --- | ---: | ---: | ---: | ---: |
| vs Smart | 545 | 455 | 54.50% | 51.40–57.56% |
| vs Smarter | 512 | 488 | 51.20% | 48.10–54.29% |

The subprocess Smarter sample is directionally positive but not independently
significant at 1,000 games; the larger seeded benchmark is.

## PPO checkpoint

Evaluated against `best_1000000.zip` with the existing `eval_sb3.py` harness:

| PPO mode | Crushing wins | PPO wins | Crushing win rate | 95% Wilson interval |
| --- | ---: | ---: | ---: | ---: |
| Stochastic (tournament default) | 167 | 133 | 55.67% | 50.01–61.18% |
| Deterministic | 152 | 148 | 50.67% | 45.04–56.28% |

The stochastic result demonstrates an advantage over the mode used by
`SB3PolicyAdapter`; deterministic PPO is effectively tied at this sample size.
