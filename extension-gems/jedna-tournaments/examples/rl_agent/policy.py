from typing import Any, Dict, List
import random


class RandomMaskedPolicy:
    """Selects a random valid action using the mask.

    Uses Python's random by default; if numpy is available, can be adapted.
    """

    def __init__(self, seed: int = 0) -> None:
        self.rng = random.Random(seed)

    def select(self, obs: Dict[str, Any], mask: List[int]) -> int:
        valid = [i for i, m in enumerate(mask) if m]
        if not valid:
            # Shouldn't happen; fall back to draw (0) or pass (1)
            return 0 if (len(mask) > 0 and mask[0]) else 1
        return self.rng.choice(valid)


class SB3PolicyAdapter:
    """Optional adapter for Stable-Baselines3 (MaskablePPO).

    Expects a model with predict(obs, action_masks=mask) -> (action_idx, _).
    """

    def __init__(self, model_path: str):
        try:
            from sb3_contrib import MaskablePPO  # type: ignore
        except Exception as e:  # pragma: no cover
            raise RuntimeError(
                "SB3 not available. Install sb3-contrib and stable-baselines3"
            ) from e

        self.Model = MaskablePPO
        # Lazy load model to avoid large imports during help/inspection
        self.model = self.Model.load(model_path)

    def select(self, obs: Dict[str, Any], mask: List[int]) -> int:  # pragma: no cover
        # SB3 typically expects vectorized obs; adapt if needed in your wrapper
        action, _ = self.model.predict(obs, action_masks=mask, deterministic=False)
        if isinstance(action, (list, tuple)):
            return int(action[0])
        return int(action)

