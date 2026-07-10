"""Integration coverage for the persistent Ruby training bridge."""

import os
from pathlib import Path
import unittest

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


if __name__ == "__main__":
    unittest.main()
