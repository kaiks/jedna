import unittest
from types import SimpleNamespace
from unittest.mock import patch

import numpy as np

from .expert import collect_dagger_dataset, merge_expert_datasets
from .train_sb3 import build_dagger_beta_schedule


class FakeExpert:
    def __init__(self, _command):
        self.closed = False

    def action(self, _state):
        return {"index": 0}

    def close(self):
        self.closed = True


class FakeModel:
    def predict(self, _observation, *, action_masks, deterministic):
        assert action_masks.tolist() == [1.0, 1.0]
        assert deterministic is False
        return np.asarray(1), None


class FakeEnv:
    def __init__(self):
        self.space = SimpleNamespace(from_protocol=lambda action: action["index"])
        self.current_state = {"turn": 0}
        self.executed_actions = []

    def reset(self, *, seed):
        self.current_state = {"turn": seed}
        return {"feature": np.asarray([seed], dtype=np.float32)}, {
            "action_mask": [1.0, 1.0]
        }

    def step(self, action):
        self.executed_actions.append(action)
        self.current_state = {"turn": len(self.executed_actions)}
        observation = {
            "feature": np.asarray([len(self.executed_actions)], dtype=np.float32)
        }
        return observation, 0.0, len(self.executed_actions) % 2 == 0, False, {
            "action_mask": [1.0, 1.0]
        }


class DaggerDatasetTest(unittest.TestCase):
    @patch("rl_agent.expert.ProcessExpert", FakeExpert)
    def test_labels_learner_visited_states_with_expert_actions(self):
        env = FakeEnv()

        observations, actions, masks = collect_dagger_dataset(
            env,
            "expert",
            FakeModel(),
            steps=4,
            seed=100,
            beta=0.0,
        )

        self.assertEqual(env.executed_actions, [1, 1, 1, 1])
        self.assertEqual(actions.tolist(), [0, 0, 0, 0])
        self.assertEqual(observations["feature"].shape, (4, 1))
        self.assertEqual(masks.shape, (4, 2))

    def test_merges_each_observation_and_label_array(self):
        first = (
            {"feature": np.asarray([[1.0]])},
            np.asarray([0]),
            np.asarray([[1.0, 0.0]]),
        )
        second = (
            {"feature": np.asarray([[2.0]])},
            np.asarray([1]),
            np.asarray([[0.0, 1.0]]),
        )

        observations, actions, masks = merge_expert_datasets(first, second)

        self.assertEqual(observations["feature"].ravel().tolist(), [1.0, 2.0])
        self.assertEqual(actions.tolist(), [0, 1])
        self.assertEqual(masks.tolist(), [[1.0, 0.0], [0.0, 1.0]])


class DaggerScheduleTest(unittest.TestCase):
    def test_default_schedule_anneals_to_learner_only(self):
        self.assertEqual(build_dagger_beta_schedule(3, 0.6), [0.6, 0.3, 0.0])

    def test_explicit_schedule_must_match_rounds_and_probability_range(self):
        with self.assertRaisesRegex(ValueError, "one value per round"):
            build_dagger_beta_schedule(2, 0.5, "0.5")
        with self.assertRaisesRegex(ValueError, "between 0 and 1"):
            build_dagger_beta_schedule(2, 0.5, "0.5,1.1")


if __name__ == "__main__":
    unittest.main()
