#!/usr/bin/env python3
"""Run a held-out, home-and-away round robin for PPO checkpoint finalists.

Every model is evaluated against Crusher, then every pair of models plays the
same number of games in each agent position. Results are checkpointed to JSON
after each completed matchup, so an interrupted long run can be resumed.
"""

import argparse
import json
from pathlib import Path
from itertools import combinations
from typing import Any

from .benchmark_checkpoints import (
    Checkpoint,
    EXAMPLES_DIR,
    MatchResult,
    build_model_opponent_command,
    discover_checkpoints,
    format_result,
    run_match,
    wilson_interval,
)


DEFAULT_FINALIST_STEPS = [6_000_000, 17_500_000, 18_000_000, 18_500_000]


def positive_int(value: str) -> int:
    integer = int(value)
    if integer <= 0:
        raise argparse.ArgumentTypeError("must be positive")
    return integer


def nonnegative_int(value: str) -> int:
    integer = int(value)
    if integer < 0:
        raise argparse.ArgumentTypeError("must not be negative")
    return integer


def serialize_match(result: MatchResult) -> dict[str, Any]:
    low, high = wilson_interval(result.wins, result.games)
    return {
        "subject": result.subject,
        "opponent": result.opponent,
        "wins": result.wins,
        "games": result.games,
        "win_rate": result.rate,
        "wilson_95": [low, high],
        "unresolved": result.unresolved,
        "elapsed_seconds": result.elapsed_seconds,
    }


def combine_home_and_away(
    first: Checkpoint,
    second: Checkpoint,
    first_home: MatchResult,
    second_home: MatchResult,
) -> dict[str, Any]:
    """Combine matches where each finalist controls agent1 once."""
    first_decided = first_home.games - first_home.unresolved
    second_decided = second_home.games - second_home.unresolved
    first_wins = first_home.wins + (second_decided - second_home.wins)
    second_wins = second_home.wins + (first_decided - first_home.wins)
    games = first_decided + second_decided
    low, high = wilson_interval(first_wins, games)
    return {
        "first": {"path": str(first.path), "steps": first.steps},
        "second": {"path": str(second.path), "steps": second.steps},
        "first_wins": first_wins,
        "second_wins": second_wins,
        "games": games,
        "first_win_rate": first_wins / games,
        "first_wilson_95": [low, high],
        "unresolved": first_home.unresolved + second_home.unresolved,
        "first_as_agent1": serialize_match(first_home),
        "second_as_agent1": serialize_match(second_home),
    }


def pair_key(first_steps: int, second_steps: int) -> str:
    return ":".join(str(step) for step in sorted((first_steps, second_steps)))


def build_standings(
    finalists: list[Checkpoint],
    crusher_results: list[dict[str, Any]],
    pair_results: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    crusher_by_steps = {
        result["steps"]: result for result in crusher_results
    }
    standings = []
    for finalist in finalists:
        h2h_wins = 0
        h2h_games = 0
        for result in pair_results:
            if result["first"]["steps"] == finalist.steps:
                h2h_wins += result["first_wins"]
                h2h_games += result["games"]
            elif result["second"]["steps"] == finalist.steps:
                h2h_wins += result["second_wins"]
                h2h_games += result["games"]
        crusher = crusher_by_steps.get(finalist.steps)
        standings.append(
            {
                "path": str(finalist.path),
                "steps": finalist.steps,
                "crusher_win_rate": crusher["win_rate"] if crusher else None,
                "crusher_games": crusher["games"] if crusher else 0,
                "head_to_head_wins": h2h_wins,
                "head_to_head_games": h2h_games,
                "head_to_head_win_rate": h2h_wins / h2h_games if h2h_games else None,
            }
        )
    return sorted(
        standings,
        key=lambda result: (
            result["crusher_win_rate"] is not None,
            result["crusher_win_rate"] or 0.0,
            result["head_to_head_win_rate"] or 0.0,
        ),
        reverse=True,
    )


def write_report(report_path: Path, report: dict[str, Any]) -> None:
    report_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = report_path.with_suffix(report_path.suffix + ".tmp")
    temporary_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    temporary_path.replace(report_path)


def load_or_initialize_report(
    report_path: Path,
    *,
    finalists: list[Checkpoint],
    games_per_pair: int,
    crusher_games: int,
    crusher_seed: int,
    round_robin_seed: int,
    stochastic: bool,
    resume: bool,
) -> dict[str, Any]:
    metadata = {
        "finalists": [
            {"path": str(finalist.path), "steps": finalist.steps}
            for finalist in finalists
        ],
        "games_per_pair": games_per_pair,
        "games_per_side": games_per_pair // 2,
        "crusher_games": crusher_games,
        "crusher_seed": crusher_seed,
        "round_robin_seed": round_robin_seed,
        "stochastic": stochastic,
    }
    if not resume or not report_path.exists():
        return {
            "metadata": metadata,
            "vs_crusher": [],
            "head_to_head": [],
            "standings": [],
        }

    report = json.loads(report_path.read_text(encoding="utf-8"))
    if report.get("metadata") != metadata:
        raise SystemExit(
            "Existing report metadata does not match this invocation; "
            "use a new --report path or omit --resume."
        )
    return report


def checkpoint_for_steps(
    checkpoints: list[Checkpoint], steps: list[int]
) -> list[Checkpoint]:
    by_steps = {checkpoint.steps: checkpoint for checkpoint in checkpoints}
    missing = [step for step in steps if step not in by_steps]
    if missing:
        rendered = ", ".join(str(step) for step in missing)
        raise SystemExit(f"Missing finalist checkpoint(s): {rendered}")
    return [by_steps[step] for step in steps]


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint-dir", type=Path, required=True)
    parser.add_argument(
        "--steps",
        type=int,
        action="append",
        help=(
            "Finalist checkpoint step; repeat four times. Defaults to "
            "6M, 17.5M, 18M, and 18.5M."
        ),
    )
    parser.add_argument(
        "--crusher",
        default=str(EXAMPLES_DIR / "crushing_agent.rb"),
        help="Trusted command for the fixed benchmark opponent",
    )
    parser.add_argument(
        "--games-per-pair",
        type=positive_int,
        default=20_000,
        help="Total games per model pairing, split evenly by agent position",
    )
    parser.add_argument(
        "--crusher-games",
        type=positive_int,
        help="Games for each finalist against Crusher (default: --games-per-pair)",
    )
    parser.add_argument("--crusher-seed", type=int, default=40_000_000)
    parser.add_argument("--round-robin-seed", type=int, default=50_000_000)
    parser.add_argument("--timeout", type=float, default=60.0)
    parser.add_argument("--stochastic", action="store_true")
    parser.add_argument("--progress-every", type=nonnegative_int, default=500)
    parser.add_argument(
        "--report",
        type=Path,
        help="Defaults to finalist_round_robin.json in --checkpoint-dir",
    )
    parser.add_argument(
        "--resume",
        action="store_true",
        help="Reuse completed matchups from an existing matching report",
    )
    return parser.parse_args()


def main():
    args = parse_args()
    if args.games_per_pair % 2:
        raise SystemExit("--games-per-pair must be even so positions are balanced")

    checkpoint_dir = args.checkpoint_dir.resolve()
    if not checkpoint_dir.is_dir():
        raise SystemExit(f"Checkpoint directory does not exist: {checkpoint_dir}")
    finalists = checkpoint_for_steps(
        discover_checkpoints(checkpoint_dir),
        args.steps or DEFAULT_FINALIST_STEPS,
    )
    if len(set(finalist.steps for finalist in finalists)) != len(finalists):
        raise SystemExit("Each finalist step must be supplied only once")
    if len(finalists) < 2:
        raise SystemExit("At least two finalists are required")

    crusher_games = args.crusher_games or args.games_per_pair
    report_path = (args.report or checkpoint_dir / "finalist_round_robin.json").resolve()
    report = load_or_initialize_report(
        report_path,
        finalists=finalists,
        games_per_pair=args.games_per_pair,
        crusher_games=crusher_games,
        crusher_seed=args.crusher_seed,
        round_robin_seed=args.round_robin_seed,
        stochastic=args.stochastic,
        resume=args.resume,
    )
    completed_crusher = {result["steps"] for result in report["vs_crusher"]}
    completed_pairs = {
        pair_key(result["first"]["steps"], result["second"]["steps"])
        for result in report["head_to_head"]
    }

    print(
        f"Finalists: {', '.join(str(finalist.steps) for finalist in finalists)}\n"
        f"Crusher: {crusher_games} games per finalist\n"
        f"Round robin: {args.games_per_pair} games per pairing "
        f"({args.games_per_pair // 2} in each agent position)\n"
        f"Report: {report_path}",
        flush=True,
    )

    for finalist in finalists:
        if finalist.steps in completed_crusher:
            print(f"Skipping completed Crusher match: {finalist.path.name}", flush=True)
            continue
        result = run_match(
            finalist.path,
            args.crusher,
            subject=finalist.path.name,
            opponent="Crusher",
            games=crusher_games,
            seed=args.crusher_seed,
            timeout=args.timeout,
            stochastic=args.stochastic,
            progress_every=args.progress_every,
        )
        entry = serialize_match(result)
        entry["steps"] = finalist.steps
        report["vs_crusher"].append(entry)
        report["standings"] = build_standings(
            finalists, report["vs_crusher"], report["head_to_head"]
        )
        write_report(report_path, report)
        print(format_result(result), flush=True)

    side_games = args.games_per_pair // 2
    for pair_index, (first, second) in enumerate(combinations(finalists, 2)):
        key = pair_key(first.steps, second.steps)
        if key in completed_pairs:
            print(
                f"Skipping completed head-to-head: {first.path.name} vs {second.path.name}",
                flush=True,
            )
            continue
        pair_seed = args.round_robin_seed + pair_index * args.games_per_pair
        print(f"\n{first.path.name} vs {second.path.name}", flush=True)
        first_home = run_match(
            first.path,
            build_model_opponent_command(second.path, stochastic=args.stochastic),
            subject=first.path.name,
            opponent=second.path.name,
            games=side_games,
            seed=pair_seed,
            timeout=args.timeout,
            stochastic=args.stochastic,
            progress_every=args.progress_every,
        )
        second_home = run_match(
            second.path,
            build_model_opponent_command(first.path, stochastic=args.stochastic),
            subject=second.path.name,
            opponent=first.path.name,
            games=side_games,
            seed=pair_seed + side_games,
            timeout=args.timeout,
            stochastic=args.stochastic,
            progress_every=args.progress_every,
        )
        result = combine_home_and_away(first, second, first_home, second_home)
        report["head_to_head"].append(result)
        report["standings"] = build_standings(
            finalists, report["vs_crusher"], report["head_to_head"]
        )
        write_report(report_path, report)
        low, high = result["first_wilson_95"]
        print(
            f"{first.path.name}: {result['first_wins']}/{result['games']} "
            f"({result['first_win_rate']:.2%}; Wilson95={low:.2%}-{high:.2%})",
            flush=True,
        )

    report["standings"] = build_standings(
        finalists, report["vs_crusher"], report["head_to_head"]
    )
    write_report(report_path, report)
    print("\nFinal standings (ranked by Crusher score, then head-to-head score):")
    for index, standing in enumerate(report["standings"], start=1):
        crusher_rate = standing["crusher_win_rate"]
        h2h_rate = standing["head_to_head_win_rate"]
        print(
            f"{index}. {standing['steps']}: Crusher="
            f"{crusher_rate:.2%} H2H={h2h_rate:.2%}",
            flush=True,
        )


if __name__ == "__main__":
    main()
