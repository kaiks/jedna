#!/usr/bin/env python3
"""Expose a MaskablePPO checkpoint as a persistent JSON-lines opponent."""

import argparse
import json
import sys

from sb3_contrib.ppo_mask import MaskablePPO

from .encoding import ActionSpace, encode_action_mask, pack_observation_for_model


def parse_args():
    parser = argparse.ArgumentParser(
        description="Run a MaskablePPO checkpoint as a JSON-lines opponent"
    )
    parser.add_argument("--model", required=True, help="Path to a PPO checkpoint")
    parser.add_argument(
        "--stochastic",
        action="store_true",
        help="Sample actions instead of choosing the deterministic policy action",
    )
    return parser.parse_args()


def action_for_state(model, action_space, state, *, deterministic):
    observation = pack_observation_for_model(state)
    mask = encode_action_mask(action_space, state)
    action, _ = model.predict(
        observation,
        action_masks=mask,
        deterministic=deterministic,
    )
    action_index = action.item() if hasattr(action, "item") else action
    return action_space.to_protocol(int(action_index), state)


def main():
    args = parse_args()
    model = MaskablePPO.load(args.model)
    action_space = ActionSpace()

    for line in sys.stdin:
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue

        if message.get("type") != "request_action":
            # Persistent engine_bridge processes send game_reset between games.
            # There is no per-game policy state to reset for this feed-forward policy.
            continue

        action = action_for_state(
            model,
            action_space,
            message.get("state", {}),
            deterministic=not args.stochastic,
        )
        sys.stdout.write(json.dumps(action, separators=(",", ":")) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
