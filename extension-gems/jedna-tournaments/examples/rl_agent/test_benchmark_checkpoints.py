import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from .benchmark_checkpoints import (
    Checkpoint,
    TrainingEvaluation,
    choose_log_leader,
    discover_checkpoints,
    mcnemar_p_value,
    parse_training_evaluations,
    wilson_interval,
)


class BenchmarkCheckpointTest(unittest.TestCase):
    def test_parses_evaluations_and_uses_the_best_matching_checkpoint(self):
        evaluations = parse_training_evaluations(
            "\n".join(
                [
                    "[Evaluation] steps=1000000 wins=508/1000 rate=50.80%",
                    "[Evaluation] steps=2000000 wins=540/1000 rate=54.00%",
                ]
            )
        )
        checkpoints = [
            Checkpoint(Path("checkpoint_1000000_steps.zip"), 1_000_000),
            Checkpoint(Path("checkpoint_2000000_steps.zip"), 2_000_000),
        ]

        checkpoint, evaluation = choose_log_leader(checkpoints, evaluations)

        self.assertEqual(checkpoint.steps, 2_000_000)
        self.assertEqual(evaluation.wins, 540)

    def test_discovers_only_numbered_checkpoint_archives(self):
        with TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "checkpoint_500000_steps.zip").touch()
            (path / "checkpoint_1000000_steps.zip").touch()
            (path / "best_model.zip").touch()

            checkpoints = discover_checkpoints(path)

        self.assertEqual([checkpoint.steps for checkpoint in checkpoints], [500_000, 1_000_000])

    def test_wilson_interval_and_paired_test_have_expected_direction(self):
        low, high = wilson_interval(2_650, 5_000)

        self.assertGreater(low, 0.5)
        self.assertGreater(high, low)
        self.assertLess(
            mcnemar_p_value([True] * 100, [False] * 100),
            0.001,
        )
        self.assertEqual(mcnemar_p_value([True, False], [True, False]), 1.0)


if __name__ == "__main__":
    unittest.main()
