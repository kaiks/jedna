import unittest

from .table_sizes import parse_player_count_weights, parse_player_counts


class PlayerCountParsingTest(unittest.TestCase):
    def test_parses_ranges_lists_and_removes_duplicates(self):
        self.assertEqual(parse_player_counts("2,4,6-8,4"), (2, 4, 6, 7, 8))

    def test_accepts_the_complete_supported_range(self):
        self.assertEqual(parse_player_counts("2-10"), tuple(range(2, 11)))

    def test_rejects_invalid_or_out_of_range_values(self):
        for value in ("", "1", "11", "4-2", "2,,3", "many"):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    parse_player_counts(value)

    def test_parses_explicit_relative_weights(self):
        self.assertEqual(
            parse_player_count_weights("2:5, 3:1,4:0.5"),
            ((2, 5.0), (3, 1.0), (4, 0.5)),
        )

    def test_rejects_invalid_weights(self):
        invalid = (
            "",
            "2",
            "2:x",
            "1:1",
            "11:1",
            "2:0",
            "2:-1",
            "2:nan",
            "2:1,2:2",
        )
        for value in invalid:
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    parse_player_count_weights(value)


if __name__ == "__main__":
    unittest.main()
