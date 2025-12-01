import argparse
import os
from typing import Optional

from .io_stream import JSONLineStream
from .history import HistoryBuffer, NoopSink, JSONLineFileSink
from .policy import RandomMaskedPolicy, SB3PolicyAdapter
from .agent import RLAgent


def build_history_sink(arg: Optional[str]):
    if not arg:
        return NoopSink()
    # e.g., json:/tmp/rollouts.jsonl
    if arg.startswith("json:"):
        path = arg.split(":", 1)[1]
        return JSONLineFileSink(path)
    # Fallback: treat as file path for jsonl
    return JSONLineFileSink(arg)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Jedna RL agent (modular scaffold)")
    parser.add_argument(
        "--policy",
        default="random",
        choices=["random", "sb3"],
        help="Policy backend (random or sb3)",
    )
    parser.add_argument(
        "--model",
        default=None,
        help="Path to model (for sb3)",
    )
    parser.add_argument(
        "--history",
        default=os.environ.get("RL_AGENT_HISTORY_OUT"),
        help="History sink spec (e.g., json:/tmp/rollouts.jsonl)",
    )
    args = parser.parse_args(argv)

    # Policy
    if args.policy == "random":
        policy = RandomMaskedPolicy()
    else:
        if not args.model:
            raise SystemExit("--model is required for --policy sb3")
        policy = SB3PolicyAdapter(args.model)

    # History
    sink = build_history_sink(args.history)
    history = HistoryBuffer(sink)

    # Stream (JSON lines by default)
    stream = JSONLineStream()

    agent = RLAgent(stream=stream, policy=policy, history=history)
    agent.run()
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())

