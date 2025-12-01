#!/usr/bin/env python3
"""
Jedna RL agent launcher.

Usage examples:
  python3 rl_agent.py --policy random
  python3 rl_agent.py --policy sb3 --model /path/to/model.zip

Optionally log history:
  RL_AGENT_HISTORY_OUT=json:/tmp/rollouts.jsonl python3 rl_agent.py
"""
from rl_agent.main import main


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())

