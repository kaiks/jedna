"""Integration coverage for the persistent Ruby training bridge."""

import os
from pathlib import Path
import subprocess
import unittest
from unittest.mock import Mock

import numpy as np

from rl_agent.rl_env import JednaVsProcessEnv


EXAMPLES_DIR = Path(__file__).resolve().parent.parent


class PersistentEngineTest(unittest.TestCase):
    def test_reuses_one_engine_and_releases_it_on_close(self):
        env = JednaVsProcessEnv(
            str(EXAMPLES_DIR / "engine_bridge.rb"),
            str(EXAMPLES_DIR / "simple_agent.rb"),
            max_seconds=30.0,
        )
        engine_pids = []

        try:
            for seed in range(3):
                _observation, info = env.reset(seed=50_000 + seed)
                engine_pids.append(env.proc.pid)

                done = False
                while not done:
                    action = int(np.flatnonzero(info["action_mask"])[0])
                    _observation, _reward, terminated, truncated, info = env.step(action)
                    done = terminated or truncated

                self.assertEqual(info.get("reason"), "game_end")
        finally:
            env.close()

        self.assertEqual(len(set(engine_pids)), 1)
        with self.assertRaises(ProcessLookupError):
            os.kill(engine_pids[0], 0)

    def test_runs_three_and_ten_player_games_through_one_persistent_bridge(self):
        env = JednaVsProcessEnv(
            str(EXAMPLES_DIR / "engine_bridge.rb"),
            str(EXAMPLES_DIR / "simple_agent.rb"),
            player_counts=(3, 10),
            max_seconds=30.0,
        )
        seen_counts = set()
        engine_pids = set()
        opponent_pid_sets = set()

        try:
            for seed in range(12):
                _observation, info = env.reset(seed=60_000 + seed)
                seen_counts.add(info["player_count"])
                engine_pids.add(env.proc.pid)
                opponent_pids = subprocess.check_output(
                    ["pgrep", "-P", str(env.proc.pid)], text=True
                ).splitlines()
                self.assertEqual(len(opponent_pids), 9)
                opponent_pid_sets.add(frozenset(opponent_pids))
                self.assertEqual(len(env.current_state["other_players"]), info["player_count"] - 1)

                done = False
                while not done:
                    action = int(np.flatnonzero(info["action_mask"])[0])
                    _observation, _reward, terminated, truncated, info = env.step(action)
                    done = terminated or truncated
                self.assertEqual(info.get("reason"), "game_end")
                if seen_counts == {3, 10}:
                    break
        finally:
            env.close()

        self.assertEqual(seen_counts, {3, 10})
        self.assertEqual(len(engine_pids), 1)
        self.assertEqual(len(opponent_pid_sets), 1)

    def test_reward_tracks_opponents_by_id_and_normalizes_table_size(self):
        env = JednaVsProcessEnv("engine.rb", "opponent", reward_scale=0.05)
        env._previous_own_size = 5
        env._previous_opponent_sizes = {"agent2": 3, "agent3": 4}

        reward = env._shaping_reward(4, {"agent3": 5, "agent2": 4})

        self.assertAlmostEqual(reward, 0.1)
        self.assertEqual(env._previous_opponent_sizes, {"agent3": 5, "agent2": 4})

    def test_wait_for_request_restarts_a_game_that_ends_before_agent1_acts(self):
        env = JednaVsProcessEnv("engine.rb", "opponent", player_counts=(3,))
        messages = iter(
            [
                {"type": "game_end", "winner": "agent2"},
                {
                    "type": "request_action",
                    "state": {
                        "hand": ["r5"],
                        "other_players": [
                            {"id": "agent2", "card_count": 1},
                            {"id": "agent3", "card_count": 2},
                        ],
                    },
                },
            ]
        )
        env._read = lambda: next(messages)
        env._begin_game = Mock()

        observation = env._wait_for_request()

        env._begin_game.assert_called_once_with()
        self.assertEqual(env._discarded_games_before_first_action, 1)
        self.assertEqual(observation["player_count"].tolist(), [3.0])

    def test_rejects_player_counts_outside_two_to_ten(self):
        for counts in ((), (1,), (11,), (2, 10, 11)):
            with self.subTest(counts=counts):
                with self.assertRaises(ValueError):
                    JednaVsProcessEnv("engine.rb", "opponent", player_counts=counts)

    def test_weighted_player_count_sampling(self):
        env = JednaVsProcessEnv(
            "engine.rb",
            "opponent",
            player_counts=(2, 3, 4, 5, 6, 7),
            player_count_weights=(5, 1, 1, 1, 1, 1),
        )
        env._np_random = np.random.default_rng(12_345)

        samples = [env._sample_player_count() for _index in range(20_000)]

        self.assertAlmostEqual(samples.count(2) / len(samples), 0.5, delta=0.015)
        for player_count in range(3, 8):
            self.assertAlmostEqual(
                samples.count(player_count) / len(samples), 0.1, delta=0.015
            )

    def test_rejects_invalid_player_count_weights(self):
        for weights in ((1,), (1, 0), (1, -1), (1, float("inf"))):
            with self.subTest(weights=weights):
                with self.assertRaises(ValueError):
                    JednaVsProcessEnv(
                        "engine.rb",
                        "opponent",
                        player_counts=(2, 3),
                        player_count_weights=weights,
                    )


if __name__ == "__main__":
    unittest.main()
