import math
from typing import Tuple

from .encoding import MAX_PLAYERS


def parse_player_counts(value: str) -> Tuple[int, ...]:
    """Parse table sizes such as ``2-10`` or ``2,4,6-8``."""
    counts = []
    for raw_part in value.split(","):
        part = raw_part.strip()
        if not part:
            raise ValueError("player counts cannot contain empty entries")
        if "-" in part:
            bounds = part.split("-", 1)
            try:
                start, finish = (int(bound) for bound in bounds)
            except ValueError as error:
                raise ValueError(f"invalid player-count range: {part!r}") from error
            if start > finish:
                raise ValueError(f"descending player-count range: {part!r}")
            counts.extend(range(start, finish + 1))
        else:
            try:
                counts.append(int(part))
            except ValueError as error:
                raise ValueError(f"invalid player count: {part!r}") from error

    unique = tuple(dict.fromkeys(counts))
    if not unique:
        raise ValueError("at least one player count is required")
    if any(not 2 <= count <= MAX_PLAYERS for count in unique):
        raise ValueError(f"player counts must be between 2 and {MAX_PLAYERS}")
    return unique


def parse_player_count_weights(value: str) -> Tuple[Tuple[int, float], ...]:
    """Parse relative table-size weights such as ``2:5,3:1,4:1``."""
    weighted_counts = []
    seen = set()
    for raw_part in value.split(","):
        part = raw_part.strip()
        if not part or ":" not in part:
            raise ValueError("player-count weights must use COUNT:WEIGHT entries")
        raw_count, raw_weight = (field.strip() for field in part.split(":", 1))
        try:
            count = int(raw_count)
            weight = float(raw_weight)
        except ValueError as error:
            raise ValueError(f"invalid player-count weight: {part!r}") from error
        if not 2 <= count <= MAX_PLAYERS:
            raise ValueError(f"player counts must be between 2 and {MAX_PLAYERS}")
        if count in seen:
            raise ValueError(f"duplicate weighted player count: {count}")
        if not math.isfinite(weight) or weight <= 0:
            raise ValueError("player-count weights must be finite and positive")
        seen.add(count)
        weighted_counts.append((count, weight))

    if not weighted_counts:
        raise ValueError("at least one player-count weight is required")
    return tuple(weighted_counts)
