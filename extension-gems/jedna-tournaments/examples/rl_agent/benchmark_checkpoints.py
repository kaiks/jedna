#!/usr/bin/env python3
"""Select and validate PPO checkpoints on held-out, seeded Jedna games.

The training log chooses only a provisional checkpoint. This program then uses
a separate seed range to score every checkpoint against Crusher, selects the
held-out leader, and uses another seed range to validate that leader against
Crusher and every other checkpoint.
"""

import argparse
import json
import math
from dataclasses import dataclass
from pathlib import Path
import re
import shlex
import sys
import time
from typing import Iterable, Sequence

from sb3_contrib.common.wrappers import ActionMasker
from sb3_contrib.ppo_mask import MaskablePPO

HERE = Path(__file__).resolve().parent
EXAMPLES_DIR = HERE.parent
if str(EXAMPLES_DIR) not in sys.path:
    sys.path.insert(0, str(EXAMPLES_DIR))

from rl_agent.rl_env import JednaVsProcessEnv


EVALUATION_PATTERN = re.compile(
    r"\[Evaluation\]\s+steps=(?P<steps>\d+)\s+"
    r"wins=(?P<wins>\d+)/(?P<games>\d+)\s+rate=(?P<rate>[\d.]+)%"
)
CHECKPOINT_PATTERN = re.compile(r"checkpoint_(?P<steps>\d+)_steps\.zip$")


@dataclass(frozen=True)
class TrainingEvaluation:
    steps: int
    wins: int
    games: int

    @property
    def rate(self) -> float:
        return self.wins / self.games


@dataclass(frozen=True)
class Checkpoint:
    path: Path
    steps: int

    @property
    def label(self) -> str:
        return self.path.name


@dataclass
class MatchResult:
    subject: str
    opponent: str
    wins: int
    games: int
    unresolved: int
    outcomes: list[bool]
    elapsed_seconds: float

    @property
    def rate(self) -> float:
        return self.wins / self.games


def mask_fn(env: JednaVsProcessEnv):
    return env.valid_action_mask()


def parse_training_evaluations(log_text: str) -> list[TrainingEvaluation]:
    """Return the last reported evaluation for each training step."""
    by_step = {}
    for match in EVALUATION_PATTERN.finditer(log_text):
        steps = int(match.group("steps"))
        games = int(match.group("games"))
        if games == 0:
            continue
        by_step[steps] = TrainingEvaluation(
            steps=steps,
            wins=int(match.group("wins")),
            games=games,
        )
    return [by_step[step] for step in sorted(by_step)]


def discover_checkpoints(checkpoint_dir: Path) -> list[Checkpoint]:
    checkpoints = []
    for path in checkpoint_dir.glob("checkpoint_*_steps.zip"):
        match = CHECKPOINT_PATTERN.fullmatch(path.name)
        if match:
            checkpoints.append(Checkpoint(path=path, steps=int(match.group("steps"))))
    return sorted(checkpoints, key=lambda checkpoint: checkpoint.steps)


def wilson_interval(wins: int, games: int, z: float = 1.96) -> tuple[float, float]:
    if games <= 0:
        return 0.0, 1.0
    proportion = wins / games
    denominator = 1 + z * z / games
    center = (proportion + z * z / (2 * games)) / denominator
    half_width = (
        z
        * math.sqrt(
            proportion * (1 - proportion) / games + z * z / (4 * games * games)
        )
        / denominator
    )
    return center - half_width, center + half_width


def mcnemar_p_value(first: Sequence[bool], second: Sequence[bool]) -> float:
    """Two-sided continuity-corrected McNemar p-value for paired outcomes."""
    if len(first) != len(second):
        raise ValueError("Paired outcomes must have the same length")
    first_only = sum(a and not b for a, b in zip(first, second))
    second_only = sum(not a and b for a, b in zip(first, second))
    discordant = first_only + second_only
    if discordant == 0:
        return 1.0
    statistic = (abs(first_only - second_only) - 1) ** 2 / discordant
    return math.erfc(math.sqrt(statistic / 2))


def checkpoint_display(checkpoint: Checkpoint) -> str:
    return f"{checkpoint.label} ({checkpoint.steps / 1_000_000:g}M steps)"


def choose_log_leader(
    checkpoints: Sequence[Checkpoint], evaluations: Sequence[TrainingEvaluation]
) -> tuple[Checkpoint, TrainingEvaluation]:
    checkpoints_by_step = {checkpoint.steps: checkpoint for checkpoint in checkpoints}
    eligible = [
        (checkpoints_by_step[evaluation.steps], evaluation)
        for evaluation in evaluations
        if evaluation.steps in checkpoints_by_step
    ]
    if not eligible:
        raise ValueError(
            "No numbered checkpoint has a matching [Evaluation] entry in the training log"
        )
    return max(eligible, key=lambda item: (item[1].rate, item[1].steps))


def limit_candidates(
    checkpoints: Sequence[Checkpoint],
    evaluations: Sequence[TrainingEvaluation],
    limit: int,
) -> list[Checkpoint]:
    if limit == 0 or len(checkpoints) <= limit:
        return list(checkpoints)

    evaluations_by_step = {evaluation.steps: evaluation for evaluation in evaluations}
    ranked = sorted(
        checkpoints,
        key=lambda checkpoint: (
            evaluations_by_step.get(checkpoint.steps, TrainingEvaluation(0, 0, 1)).rate,
            checkpoint.steps,
        ),
        reverse=True,
    )
    return sorted(ranked[:limit], key=lambda checkpoint: checkpoint.steps)


def build_model_opponent_command(model_path: Path, *, stochastic: bool) -> str:
    command = [
        shlex.quote(sys.executable),
        "-m",
        "rl_agent.sb3_opponent",
        "--model",
        shlex.quote(str(model_path.resolve())),
    ]
    if stochastic:
        command.append("--stochastic")
    return f"cd {shlex.quote(str(EXAMPLES_DIR))} && {' '.join(command)}"


def run_match(
    model_path: Path,
    opponent_command: str,
    *,
    subject: str,
    opponent: str,
    games: int,
    seed: int,
    timeout: float,
    stochastic: bool,
    progress_every: int,
) -> MatchResult:
    engine_path = EXAMPLES_DIR / "engine_bridge.rb"
    base_env = JednaVsProcessEnv(
        engine_path=str(engine_path),
        opponent_cmd=opponent_command,
        max_seconds=timeout,
    )
    env = ActionMasker(base_env, mask_fn)
    model = MaskablePPO.load(model_path)
    wins = 0
    unresolved = 0
    outcomes = []
    started_at = time.monotonic()

    try:
        for episode in range(games):
            observation, info = env.reset(seed=seed + episode)
            done = False
            while not done:
                action, _ = model.predict(
                    observation,
                    action_masks=info["action_mask"],
                    deterministic=not stochastic,
                )
                action_index = action.item() if hasattr(action, "item") else action
                observation, _reward, terminated, truncated, info = env.step(
                    int(action_index)
                )
                done = terminated or truncated

            won = info.get("winner") == "agent1"
            wins += int(won)
            outcomes.append(won)
            unresolved += int(info.get("winner") not in {"agent1", "agent2"})

            completed = episode + 1
            if progress_every and (
                completed % progress_every == 0 or completed == games
            ):
                print(
                    f"  {subject} vs {opponent}: {completed}/{games} games",
                    flush=True,
                )
    finally:
        env.close()

    return MatchResult(
        subject=subject,
        opponent=opponent,
        wins=wins,
        games=games,
        unresolved=unresolved,
        outcomes=outcomes,
        elapsed_seconds=time.monotonic() - started_at,
    )


def format_result(result: MatchResult) -> str:
    lower, upper = wilson_interval(result.wins, result.games)
    suffix = f", unresolved={result.unresolved}" if result.unresolved else ""
    return (
        f"{result.subject} vs {result.opponent}: "
        f"{result.wins}/{result.games} ({result.rate:.2%}), "
        f"Wilson95={lower:.2%}-{upper:.2%}, "
        f"{result.elapsed_seconds:.1f}s{suffix}"
    )


def write_report(
    report_path: Path,
    *,
    log_leader: Checkpoint,
    held_out_leader: Checkpoint,
    screening: Iterable[MatchResult],
    confirmation_vs_crusher: MatchResult,
    head_to_head: Iterable[MatchResult],
) -> None:
    def serialize(result: MatchResult):
        lower, upper = wilson_interval(result.wins, result.games)
        return {
            "subject": result.subject,
            "opponent": result.opponent,
            "wins": result.wins,
            "games": result.games,
            "win_rate": result.rate,
            "wilson_95": [lower, upper],
            "unresolved": result.unresolved,
            "elapsed_seconds": result.elapsed_seconds,
        }

    report = {
        "log_leader": {"path": str(log_leader.path), "steps": log_leader.steps},
        "held_out_crusher_leader": {
            "path": str(held_out_leader.path),
            "steps": held_out_leader.steps,
        },
        "screening_vs_crusher": [serialize(result) for result in screening],
        "confirmation_vs_crusher": serialize(confirmation_vs_crusher),
        "confirmation_head_to_head": [serialize(result) for result in head_to_head],
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


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


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint-dir", type=Path, required=True)
    parser.add_argument(
        "--training-log",
        type=Path,
        help="Defaults to training.log in --checkpoint-dir",
    )
    parser.add_argument(
        "--crusher",
        default=str(EXAMPLES_DIR / "crushing_agent.rb"),
        help="Trusted command for the fixed benchmark opponent",
    )
    parser.add_argument(
        "--games",
        type=positive_int,
        default=5_000,
        help="Games per matchup and seed range (default: 5000)",
    )
    parser.add_argument(
        "--screening-seed",
        type=int,
        default=20_000_000,
        help="First seed of the held-out checkpoint-selection range",
    )
    parser.add_argument(
        "--confirmation-seed",
        type=int,
        default=30_000_000,
        help="First seed of the independent champion-confirmation range",
    )
    parser.add_argument("--timeout", type=float, default=60.0)
    parser.add_argument(
        "--candidate-limit",
        type=nonnegative_int,
        default=0,
        help="Test only this many log-ranked checkpoints; 0 tests all numbered checkpoints",
    )
    parser.add_argument(
        "--stochastic",
        action="store_true",
        help="Sample actions for every PPO policy instead of using deterministic inference",
    )
    parser.add_argument(
        "--skip-head-to-head",
        action="store_true",
        help="Only score checkpoints against Crusher; do not validate the leader against peers",
    )
    parser.add_argument(
        "--progress-every",
        type=nonnegative_int,
        default=250,
        help="Print a progress update after this many games; 0 disables updates",
    )
    parser.add_argument(
        "--report",
        type=Path,
        help="Optional JSON path for aggregate results",
    )
    return parser.parse_args()


def main():
    args = parse_args()
    checkpoint_dir = args.checkpoint_dir.resolve()
    log_path = (args.training_log or checkpoint_dir / "training.log").resolve()
    if not checkpoint_dir.is_dir():
        raise SystemExit(f"Checkpoint directory does not exist: {checkpoint_dir}")
    if not log_path.is_file():
        raise SystemExit(f"Training log does not exist: {log_path}")

    checkpoints = discover_checkpoints(checkpoint_dir)
    if not checkpoints:
        raise SystemExit(f"No checkpoint_<steps>_steps.zip files in {checkpoint_dir}")
    evaluations = parse_training_evaluations(log_path.read_text(encoding="utf-8"))
    try:
        log_leader, log_evaluation = choose_log_leader(checkpoints, evaluations)
    except ValueError as error:
        raise SystemExit(str(error)) from error

    candidates = limit_candidates(checkpoints, evaluations, args.candidate_limit)
    print(
        "Training-log leader: "
        f"{checkpoint_display(log_leader)} with "
        f"{log_evaluation.wins}/{log_evaluation.games} ({log_evaluation.rate:.2%})"
    )
    print(
        f"Screening {len(candidates)} checkpoints against Crusher with "
        f"{args.games} held-out games each."
    )

    screening = []
    for checkpoint in candidates:
        result = run_match(
            checkpoint.path,
            args.crusher,
            subject=checkpoint.label,
            opponent="Crusher",
            games=args.games,
            seed=args.screening_seed,
            timeout=args.timeout,
            stochastic=args.stochastic,
            progress_every=args.progress_every,
        )
        screening.append(result)
        print(format_result(result), flush=True)

    leader_index, leader_screening = max(
        enumerate(screening), key=lambda item: (item[1].rate, candidates[item[0]].steps)
    )
    held_out_leader = candidates[leader_index]
    print(f"\nHeld-out Crusher leader: {checkpoint_display(held_out_leader)}")
    print("Paired screening comparisons versus that leader (McNemar p-values):")
    for checkpoint, result in zip(candidates, screening):
        p_value = mcnemar_p_value(leader_screening.outcomes, result.outcomes)
        print(f"  {checkpoint.label}: {p_value:.4g}")

    print("\nConfirming the selected leader on an independent seed range.")
    confirmation_vs_crusher = run_match(
        held_out_leader.path,
        args.crusher,
        subject=held_out_leader.label,
        opponent="Crusher",
        games=args.games,
        seed=args.confirmation_seed,
        timeout=args.timeout,
        stochastic=args.stochastic,
        progress_every=args.progress_every,
    )
    print(format_result(confirmation_vs_crusher), flush=True)

    head_to_head = []
    if not args.skip_head_to_head:
        print("\nChampion head-to-head confirmation against the other checkpoints:")
        for challenger in candidates:
            if challenger == held_out_leader:
                continue
            result = run_match(
                held_out_leader.path,
                build_model_opponent_command(challenger.path, stochastic=args.stochastic),
                subject=held_out_leader.label,
                opponent=challenger.label,
                games=args.games,
                seed=args.confirmation_seed,
                timeout=args.timeout,
                stochastic=args.stochastic,
                progress_every=args.progress_every,
            )
            head_to_head.append(result)
            print(format_result(result), flush=True)

    if args.report:
        write_report(
            args.report,
            log_leader=log_leader,
            held_out_leader=held_out_leader,
            screening=screening,
            confirmation_vs_crusher=confirmation_vs_crusher,
            head_to_head=head_to_head,
        )
        print(f"\nWrote report to {args.report}")


if __name__ == "__main__":
    main()
