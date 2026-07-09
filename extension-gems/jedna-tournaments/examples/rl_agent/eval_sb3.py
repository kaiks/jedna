#!/usr/bin/env python3
"""
Evaluate a trained MaskablePPO model vs a process opponent.

Usage:
  python3 eval_sb3.py --opponent "ruby .../smarter_agent.rb" --model /tmp/jedna_maskppo.zip --episodes 200
"""
import argparse
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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--opponent", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--episodes", type=int, default=200)
    parser.add_argument("--timeout", type=float, default=60.0)
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
    for _ in range(args.episodes):
        obs, info = env.reset()
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
        if reward > 0:
            wins += 1
    rate = 100.0 * wins / max(1, total)
    print(f"Episodes={total} Wins={wins} WinRate={rate:.2f}%")


if __name__ == "__main__":
    main()
