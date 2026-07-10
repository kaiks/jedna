import unittest

from .encoding import ActionSpace, encode_action_mask, pack_observation_for_model


class ObservationEncodingTest(unittest.TestCase):
    def test_packs_protocol_state_for_training_and_inference(self):
        observation = pack_observation_for_model(
            {
                "hand": ["r5", "r5", "gs", "wd4"],
                "top_card": "r3",
                "stacked_cards": 6,
                "other_players": [{"card_count": 2}],
                "playable_cards": ["r5", "wd4"],
            }
        )

        self.assertEqual(observation["color_counts"], [2.0, 1.0, 0.0, 0.0])
        self.assertEqual(observation["war_cards_to_draw"], [6.0])
        self.assertEqual(observation["opponent_counts"], [2.0])
        self.assertEqual(len(observation["figure_counts"]), 13)

    def test_masks_every_action_except_currently_legal_ones(self):
        space = ActionSpace()
        mask = encode_action_mask(
            space,
            {
                "available_actions": ["play"],
                "playable_cards": ["r5", "wd4"],
            },
        )

        enabled = [index for index, value in enumerate(mask) if value]
        self.assertEqual(
            enabled,
            [space.action_to_index[("play", "r5")], space.action_to_index[("play", "wd4")]],
        )


if __name__ == "__main__":
    unittest.main()
