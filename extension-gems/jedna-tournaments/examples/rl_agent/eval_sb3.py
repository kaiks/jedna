#!/usr/bin/env python3
"""
Evaluate a trained MaskablePPO model vs a process opponent.

Usage:
  python3 eval_sb3.py --opponent "./crushing_agent.rb" --model /tmp/jedna_maskppo.zip --episodes 200
"""
import argparse
import math
import os
import sys

from sb3_contrib.ppo_mask import MaskablePPO
from sb3_contrib.common.wrappers import ActionMasker

# Ensure the parent examples directory is importable as a package root
HERE = os.path.abspath(os.path.dirname(__file__))
EXAMPLES_DIR = os.path.abspath(os.path.join(HERE, ".."))
if EXAMPLES_DIR not in sys.path:
    sys.path.insert(0, EXAMPLES_DIR)

from rl_agent.rl_env import JednaVsProcessEnv
from rl_agent.table_sizes import parse_player_counts


def mask_fn(env: JednaVsProcessEnv):
    return env.valid_action_mask()


def wilson_interval(wins, total, z=1.96):
    proportion = wins / total
    denominator = 1 + z * z / total
    center = (proportion + z * z / (2 * total)) / denominator
    half_width = (
        z
        * math.sqrt(
            proportion * (1 - proportion) / total + z * z / (4 * total * total)
        )
        / denominator
    )
    return center - half_width, center + half_width


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--opponent", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--episodes", type=int, default=200)
    parser.add_argument("--timeout", type=float, default=60.0)
    parser.add_argument("--seed", type=int, default=1_000_000)
    parser.add_argument(
        "--player-counts",
        type=parse_player_counts,
        default=parse_player_counts("2-10"),
        help="Table sizes to evaluate, e.g. 2-10 or 2,4,6",
    )
    parser.add_argument(
        "--stochastic",
        action="store_true",
        help="Sample from the policy instead of choosing deterministic actions",
    )
    args = parser.parse_args()

    engine_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "engine_bridge.rb"))
    model = MaskablePPO.load(args.model)

    rates = []
    total_wins = 0
    total_episodes = 0
    for player_count in args.player_counts:
        base_env = JednaVsProcessEnv(
            engine_path=engine_path,
            opponent_cmd=args.opponent,
            player_counts=(player_count,),
            max_seconds=args.timeout,
        )
        env = ActionMasker(base_env, mask_fn)
        wins = 0
        try:
            for episode in range(args.episodes):
                obs, info = env.reset(
                    seed=args.seed + (player_count * 1_000_000) + episode
                )
                done = False
                while not done:
                    mask = info.get("action_mask")
                    action, _ = model.predict(
                        obs,
                        action_masks=mask,
                        deterministic=not args.stochastic,
                    )
                    obs, _reward, terminated, truncated, info = env.step(int(action))
                    done = terminated or truncated
                wins += int(info.get("winner") == "agent1")
        finally:
            env.close()
        rate = wins / args.episodes
        low, high = wilson_interval(wins, args.episodes)
        rates.append(rate)
        total_wins += wins
        total_episodes += args.episodes
        print(
            f"Players={player_count} Episodes={args.episodes} Wins={wins} "
            f"WinRate={rate:.2%} Wilson95={low:.2%}-{high:.2%}"
        )

    print(
        f"MacroWinRate={sum(rates) / len(rates):.2%} "
        f"TotalEpisodes={total_episodes} TotalWins={total_wins}"
    )


if __name__ == "__main__":
    main()
