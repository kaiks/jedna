import unittest
from pathlib import Path

from .benchmark_checkpoints import Checkpoint, MatchResult
from .finalist_round_robin import combine_home_and_away, pair_key


class FinalistRoundRobinTest(unittest.TestCase):
    def test_combines_balanced_home_and_away_results(self):
        first = Checkpoint(Path("checkpoint_6000000_steps.zip"), 6_000_000)
        second = Checkpoint(Path("checkpoint_17500000_steps.zip"), 17_500_000)
        first_home = MatchResult(
            "first", "second", 60, 100, 0, [True] * 60 + [False] * 40, 1.0
        )
        second_home = MatchResult(
            "second", "first", 55, 100, 0, [True] * 55 + [False] * 45, 1.0
        )

        result = combine_home_and_away(first, second, first_home, second_home)

        self.assertEqual(result["first_wins"], 105)
        self.assertEqual(result["second_wins"], 95)
        self.assertEqual(result["games"], 200)
        self.assertEqual(pair_key(17_500_000, 6_000_000), "6000000:17500000")


if __name__ == "__main__":
    unittest.main()
