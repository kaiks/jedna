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
        self.assertEqual(sum(observation["card_counts"]), 4.0)
        self.assertEqual(sum(observation["playable_cards"]), 2.0)

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

    def test_enables_and_round_trips_a_legal_double_play(self):
        space = ActionSpace()
        state = {
            "hand": ["r5", "r5", "b2"],
            "available_actions": ["play", "draw"],
            "playable_cards": ["r5"],
            "already_picked": False,
        }

        mask = encode_action_mask(space, state)
        index = space.action_to_index[("double_play", "r5")]

        self.assertEqual(mask[index], 1)
        self.assertEqual(
            space.to_protocol(index, state),
            {"action": "play", "card": "r5", "double_play": True},
        )
        self.assertEqual(
            space.from_protocol({"action": "play", "card": "r5", "double_play": True}),
            index,
        )

    def test_preserves_the_selected_color_and_identity_of_a_wild_top_card(self):
        observation = pack_observation_for_model({"top_card": "wd4g"})
        space = ActionSpace()

        self.assertEqual(observation["top_color"], [1.0])
        self.assertEqual(observation["top_card"][space.cards.index("wd4")], 1.0)


if __name__ == "__main__":
    unittest.main()
