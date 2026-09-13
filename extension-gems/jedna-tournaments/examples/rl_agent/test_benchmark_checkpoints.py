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
    def test_ranks_complete_multiplayer_evaluations_by_macro_rate(self):
        evaluations = parse_training_evaluations("\n".join([
            "[Evaluation] steps=100 players=2 wins=90/100 rate=90.00%",
            "[Evaluation] steps=100 players=3 wins=0/10 rate=0.00%",
            "[Evaluation] steps=100 macro_rate=45.00% table_sizes=2,3",
            "[Evaluation] steps=200 players=2 wins=5/10 rate=50.00%",
            "[Evaluation] steps=200 players=3 wins=50/100 rate=50.00%",
            "[Evaluation] steps=200 macro_rate=50.00% table_sizes=2,3",
        ]))

        checkpoint, evaluation = choose_log_leader(
            [Checkpoint(Path('first.zip'), 100), Checkpoint(Path('second.zip'), 200)],
            evaluations,
        )

        self.assertEqual(checkpoint.steps, 200)
        self.assertEqual(evaluation.rate, 0.5)
        self.assertEqual(evaluations[0].wins, 90)
        self.assertEqual(evaluations[0].games, 110)
        self.assertEqual(evaluations[0].rate, 0.45)

    def test_partial_multiplayer_evaluation_does_not_replace_completed_result(self):
        evaluations = parse_training_evaluations("\n".join([
            "[Evaluation] steps=100 players=2 wins=5/10 rate=50.00%",
            "[Evaluation] steps=100 macro_rate=50.00% table_sizes=2",
            "[Evaluation] steps=100 players=2 wins=10/10 rate=100.00%",
            "[Evaluation] steps=200 players=2 wins=10/10 rate=100.00%",
            "[Evaluation] steps=200 macro_rate=100.00% table_sizes=2,3",
        ]))

        self.assertEqual(len(evaluations), 1)
        self.assertEqual(evaluations[0].steps, 100)
        self.assertEqual(evaluations[0].rate, 0.5)

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
