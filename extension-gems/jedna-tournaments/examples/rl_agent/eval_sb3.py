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
        "--stochastic",
        action="store_true",
        help="Sample from the policy instead of choosing deterministic actions",
    )
    args = parser.parse_args()

    engine_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "engine_bridge.rb"))
    base_env = JednaVsProcessEnv(engine_path=engine_path, opponent_cmd=args.opponent, max_seconds=args.timeout)
    env = ActionMasker(base_env, mask_fn)

    model = MaskablePPO.load(args.model)

    wins = 0
    total = 0
    try:
        for episode in range(args.episodes):
            obs, info = env.reset(seed=args.seed + episode)
            done = False
            while not done:
                mask = info.get("action_mask")
                action, _ = model.predict(
                    obs,
                    action_masks=mask,
                    deterministic=not args.stochastic,
                )
                obs, reward, terminated, truncated, info = env.step(int(action))
                done = terminated or truncated
            total += 1
            if info.get("winner") == "agent1":
                wins += 1
    finally:
        env.close()
    rate = 100.0 * wins / max(1, total)
    low, high = wilson_interval(wins, total)
    print(
        f"Episodes={total} Wins={wins} WinRate={rate:.2f}% "
        f"Wilson95={low:.2%}-{high:.2%}"
    )


if __name__ == "__main__":
    main()
