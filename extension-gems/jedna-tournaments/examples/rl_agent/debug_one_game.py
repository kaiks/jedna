#!/usr/bin/env python3
"""
Run a single game with a watchdog timeout for debugging.

Example:
  python3 extension-gems/jedna-tournaments/examples/rl_agent/debug_one_game.py \
    --opponent "./crushing_agent.rb" \
    --timeout 60
"""
import argparse
import os
import random
import sys


def ensure_path():
    # Add examples dir to sys.path so 'rl_agent' package is importable
    here = os.path.abspath(os.path.dirname(__file__))
    examples_dir = here  # this file sits inside .../examples/rl_agent/
    parent_examples = os.path.dirname(examples_dir)  # .../examples
    if parent_examples not in sys.path:
        sys.path.insert(0, parent_examples)


def main():
    ensure_path()
    from rl_agent.rl_env import JednaVsProcessEnv
    from rl_agent.encoding import ActionSpace, encode_action_mask

    parser = argparse.ArgumentParser()
    parser.add_argument("--opponent", required=True)
    parser.add_argument("--timeout", type=float, default=60.0)
    args = parser.parse_args()

    engine_path = os.path.abspath(
        os.path.join(os.path.dirname(__file__), "..", "engine_bridge.rb")
    )
    env = JednaVsProcessEnv(engine_path=engine_path, opponent_cmd=args.opponent, max_seconds=args.timeout)

    obs, info = env.reset()
    space = ActionSpace()
    steps = 0
    while True:
        mask = info.get("action_mask") or encode_action_mask(space, {})
        valid = [i for i, m in enumerate(mask) if m]
        a = random.choice(valid) if valid else 0
        obs, reward, terminated, truncated, info = env.step(a)
        steps += 1
        if terminated or truncated:
            reason = info.get("reason") if isinstance(info, dict) else None
            print(f"done steps={steps} reward={reward} reason={reason}")
            break


if __name__ == "__main__":
    main()
