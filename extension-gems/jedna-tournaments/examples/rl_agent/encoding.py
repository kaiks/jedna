from collections import Counter
from typing import Dict, Any, List, Tuple


COLORS = ["r", "g", "b", "y"]
FIGURES = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "r", "s", "+2"]
WILDS = ["w", "wd4"]
TYPE_KEYS = ["numbers", "skips", "reverses", "draw2", "wild", "wd4"]
COLOR_INDEX = {color: index for index, color in enumerate(COLORS)}
FIGURE_INDEX = {figure: index for index, figure in enumerate(FIGURES)}


def all_colored_cards() -> List[str]:
    return [c + f for c in COLORS for f in FIGURES]


def all_cards() -> List[str]:
    return all_colored_cards() + WILDS


class ActionSpace:
    """Fixed discrete action space mapping indices to concrete protocol actions.

    Ordering:
    [ draw, pass, play:<card>, double_play:<card> ]
    """

    def __init__(self) -> None:
        self.cards = all_cards()
        self.index_to_action: List[Tuple[str, str]] = []
        self.action_to_index: Dict[Tuple[str, str], int] = {}

        # 0: draw, 1: pass
        self.index_to_action.append(("draw", ""))
        self.index_to_action.append(("pass", ""))
        self.action_to_index[("draw", "")] = 0
        self.action_to_index[("pass", "")] = 1

        # Remaining: play card
        for card in self.cards:
            idx = len(self.index_to_action)
            self.index_to_action.append(("play", card))
            self.action_to_index[("play", card)] = idx

        for card in self.cards:
            idx = len(self.index_to_action)
            self.index_to_action.append(("double_play", card))
            self.action_to_index[("double_play", card)] = idx

    def size(self) -> int:
        return len(self.index_to_action)

    def to_protocol(self, idx: int, state: Dict[str, Any]) -> Dict[str, Any]:
        kind, payload = self.index_to_action[idx]
        if kind == "draw":
            return {"action": "draw"}
        if kind == "pass":
            return {"action": "pass"}
        # kind == play or double_play
        action = {"action": "play", "card": payload}
        if kind == "double_play":
            action["double_play"] = True
        if payload in ("w", "wd4"):
            # Choose best color by hand frequency
            color_counts: Dict[str, int] = {c: 0 for c in COLORS}
            for c in state.get("hand", []):
                if c and c[0] in color_counts:
                    color_counts[c[0]] += 1
            # Default to red if empty
            best = max(color_counts.items(), key=lambda kv: kv[1])[0]
            action["wild_color"] = {
                "r": "red",
                "g": "green",
                "b": "blue",
                "y": "yellow",
            }[best]
        return action

    def from_protocol(self, action: Dict[str, Any]) -> int:
        """Map an expert/protocol action back to its discrete index."""
        kind = action.get("action")
        if kind in ("draw", "pass"):
            return self.action_to_index[(kind, "")]
        if kind != "play":
            raise ValueError(f"unsupported action: {action!r}")

        play_kind = "double_play" if action.get("double_play") is True else "play"
        card = canonical_card(action.get("card", ""))
        return self.action_to_index[(play_kind, card)]


def canonical_card(card: str) -> str:
    """Strip the selected color suffix from a played wild card."""
    if card.startswith("wd4"):
        return "wd4"
    if card.startswith("w"):
        return "w"
    return card


def card_color(card: str) -> str:
    """Return the active color, including the selected color of a wild."""
    if card.startswith("wd4"):
        return card[3:4]
    if card.startswith("w"):
        return card[1:2]
    return card[0:1]


def encode_observation(state: Dict[str, Any]) -> Dict[str, Any]:
    """A simple dict observation; you can wrap this for Gym/SB3 if needed.

    - color/figure counts of hand
    - top card split into (color, figure)
    - war_cards_to_draw, opponent card counts
    """
    hand: List[str] = state.get("hand", [])
    color_counts = {c: 0 for c in COLORS}
    figure_counts = {f: 0 for f in FIGURES}
    numbers_count = 0
    skip_count = 0
    reverse_count = 0
    draw2_count = 0
    wild_count = 0
    wd4_count = 0

    for card in hand:
        if not card:
            continue
        col, fig = card[0], card[1:]
        if col in color_counts:
            color_counts[col] += 1
        if fig in figure_counts:
            figure_counts[fig] += 1
        # type counts
        if fig in [str(i) for i in range(10)]:
            numbers_count += 1
        elif fig == 's':
            skip_count += 1
        elif fig == 'r':
            reverse_count += 1
        elif fig == '+2':
            draw2_count += 1
        elif card == 'w':
            wild_count += 1
        elif card == 'wd4':
            wd4_count += 1

    top = state.get("top_card") or ""
    canonical_top = canonical_card(top)
    top_color = card_color(top)
    top_figure = canonical_top if canonical_top in WILDS else canonical_top[1:]

    opponents = state.get("other_players", [])
    opp_sizes = [int(p.get("card_count", 0)) for p in opponents]
    opp_min = min(opp_sizes) if opp_sizes else 0
    opp_max = max(opp_sizes) if opp_sizes else 0

    playable: List[str] = state.get("playable_cards", []) or []
    p_numbers = p_skips = p_reverses = p_draw2 = p_wild = p_wd4 = 0
    for c in playable:
        fig = c[1:] if c not in ("w", "wd4") else c
        if fig in [str(i) for i in range(10)]:
            p_numbers += 1
        elif fig == 's':
            p_skips += 1
        elif fig == 'r':
            p_reverses += 1
        elif fig == '+2':
            p_draw2 += 1
        elif fig == 'w':
            p_wild += 1
        elif fig == 'wd4':
            p_wd4 += 1

    return {
        "color_counts": color_counts,
        "figure_counts": figure_counts,
        "top_color": top_color,
        "top_figure": top_figure,
        # Keep the feature name for compatibility with existing PPO models,
        # while reading the field emitted by GameStateSerializer.
        "war_cards_to_draw": int(
            state.get("stacked_cards", state.get("war_cards_to_draw", 0))
        ),
        "opponent_counts": opp_sizes,
        "opponent_min": opp_min,
        "opponent_max": opp_max,
        "hand_size": len(hand),
        "playable_count": len(playable),
        "hand_type_counts": {
            "numbers": numbers_count,
            "skips": skip_count,
            "reverses": reverse_count,
            "draw2": draw2_count,
            "wild": wild_count,
            "wd4": wd4_count,
        },
        "playable_type_counts": {
            "numbers": p_numbers,
            "skips": p_skips,
            "reverses": p_reverses,
            "draw2": p_draw2,
            "wild": p_wild,
            "wd4": p_wd4,
        },
        "card_counts": Counter(canonical_card(card) for card in hand),
        "playable_card_counts": Counter(canonical_card(card) for card in playable),
        "top_card": canonical_top,
        "already_picked": bool(state.get("already_picked", False)),
        "available_actions": list(state.get("available_actions", []) or []),
    }


def pack_observation_for_model(state: Dict[str, Any]) -> Dict[str, Any]:
    """Pack protocol state into the fixed array-shaped Dict used by SB3."""
    raw = encode_observation(state)
    opponents = raw["opponent_counts"]

    return {
        "color_counts": [float(raw["color_counts"][color]) for color in COLORS],
        "figure_counts": [float(raw["figure_counts"][figure]) for figure in FIGURES],
        "top_color": [float(COLOR_INDEX.get(raw["top_color"], 0))],
        "top_figure": [float(FIGURE_INDEX.get(raw["top_figure"], 0))],
        "war_cards_to_draw": [float(raw["war_cards_to_draw"])],
        "opponent_counts": [float(opponents[0] if opponents else 0)],
        "opponent_min": [float(raw["opponent_min"])],
        "opponent_max": [float(raw["opponent_max"])],
        "hand_size": [float(raw["hand_size"])],
        "playable_count": [float(raw["playable_count"])],
        "hand_type_counts": [
            float(raw["hand_type_counts"][key]) for key in TYPE_KEYS
        ],
        "playable_type_counts": [
            float(raw["playable_type_counts"][key]) for key in TYPE_KEYS
        ],
        "card_counts": [float(raw["card_counts"][card]) for card in all_cards()],
        "playable_cards": [
            float(raw["playable_card_counts"][card] > 0) for card in all_cards()
        ],
        "top_card": [float(raw["top_card"] == card) for card in all_cards()],
        "already_picked": [float(raw["already_picked"])],
        "available_actions": [
            float(action in raw["available_actions"])
            for action in ("play", "draw", "pass")
        ],
    }


def encode_action_mask(space: ActionSpace, state: Dict[str, Any]) -> List[int]:
    """Binary mask for valid actions by index."""
    available = set(state.get("available_actions", []) or [])
    playable = set(state.get("playable_cards", []) or [])
    hand_counts = Counter(canonical_card(card) for card in state.get("hand", []))

    size = space.size()
    mask = [0] * size

    # draw
    mask[0] = 1 if "draw" in available else 0
    # pass
    mask[1] = 1 if "pass" in available else 0

    # plays
    for card in space.cards:
        idx = space.action_to_index[("play", card)]
        mask[idx] = 1 if ("play" in available and card in playable) else 0

        double_idx = space.action_to_index[("double_play", card)]
        double_allowed = (
            "play" in available
            and card in playable
            and hand_counts[card] >= 2
            and not state.get("already_picked", False)
        )
        mask[double_idx] = 1 if double_allowed else 0

    return mask
