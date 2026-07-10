from __future__ import annotations

import os
import select
import subprocess
import time
from typing import Any, Dict, Optional

import gymnasium as gym
import numpy as np
from gymnasium import spaces

from .encoding import ActionSpace, encode_action_mask, pack_observation_for_model


class JednaVsProcessEnv(gym.Env):
    """Gymnasium env controlling agent1 vs a process opponent.

    - Reuses a Ruby engine_bridge.rb process and one process opponent per environment.
    - Observations are dict features; action space is Discrete over fixed action set.
    - Rewards: terminal result plus dense hand-progress shaping.
    - info contains 'action_mask' for MaskablePPO.
    """

    metadata = {"render_modes": []}

    def __init__(
        self,
        engine_path: str,
        opponent_cmd: str,
        *,
        max_seconds: float = 60.0,
        reward_scale: float = 0.05,
        persistent_engine: bool = True,
    ):
        super().__init__()
        self.engine_path = engine_path
        self.opponent_cmd = opponent_cmd
        self.proc: Optional[subprocess.Popen] = None
        self.max_seconds = max_seconds
        self.reward_scale = reward_scale
        self.persistent_engine = persistent_engine
        self.space = ActionSpace()

        # Build observation space matching encode_observation keys
        # Fixed-shape arrays packed by pack_observation_for_model.
        self.observation_space = spaces.Dict(
            {
                "color_counts": spaces.Box(low=0, high=50, shape=(4,), dtype=float),
                "figure_counts": spaces.Box(low=0, high=50, shape=(13,), dtype=float),
                "top_color": spaces.Box(low=0, high=3, shape=(1,), dtype=float),  # encoded as index via helper
                "top_figure": spaces.Box(low=0, high=12, shape=(1,), dtype=float),
                "war_cards_to_draw": spaces.Box(low=0, high=100, shape=(1,), dtype=float),
                "opponent_counts": spaces.Box(low=0, high=50, shape=(1,), dtype=float),
                "opponent_min": spaces.Box(low=0, high=50, shape=(1,), dtype=float),
                "opponent_max": spaces.Box(low=0, high=50, shape=(1,), dtype=float),
                "hand_size": spaces.Box(low=0, high=50, shape=(1,), dtype=float),
                "playable_count": spaces.Box(low=0, high=50, shape=(1,), dtype=float),
                "hand_type_counts": spaces.Box(low=0, high=50, shape=(6,), dtype=float),
                "playable_type_counts": spaces.Box(low=0, high=50, shape=(6,), dtype=float),
                "card_counts": spaces.Box(low=0, high=4, shape=(54,), dtype=float),
                "playable_cards": spaces.Box(low=0, high=1, shape=(54,), dtype=float),
                "top_card": spaces.Box(low=0, high=1, shape=(54,), dtype=float),
                "already_picked": spaces.Box(low=0, high=1, shape=(1,), dtype=float),
                "available_actions": spaces.Box(low=0, high=1, shape=(3,), dtype=float),
            }
        )
        self.action_space = spaces.Discrete(self.space.size())

        self._last_state: Optional[Dict[str, Any]] = None
        self._deadline: Optional[float] = None
        self._timed_out = False
        self._engine_seed = 0
        self._previous_sizes = (0, 0)

    def _popen(self) -> subprocess.Popen:
        env = os.environ.copy()
        env["OPPONENT_CMD"] = self.opponent_cmd
        if not self.persistent_engine:
            env["JEDNA_SEED"] = str(self._engine_seed)
        command = ["ruby", self.engine_path]
        if self.persistent_engine:
            command.append("--persistent")
        return subprocess.Popen(
            command,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
            env=env,
        )

    def reset(self, *, seed: Optional[int] = None, options: Optional[Dict[str, Any]] = None):
        super().reset(seed=seed)
        self._engine_seed = int(self.np_random.integers(0, 2**31 - 1))
        self._timed_out = False
        self._deadline = time.monotonic() + self.max_seconds
        self._last_state = None
        self._previous_sizes = (0, 0)

        if self.persistent_engine:
            self._ensure_persistent_engine()
            self._write({"type": "reset", "seed": self._engine_seed})
        else:
            self._terminate_proc()
            self.proc = self._popen()

        obs = self._wait_for_request()
        self._previous_sizes = self._state_sizes(self._last_state or {})
        info = {"action_mask": self.valid_action_mask()}
        return obs, info

    def step(self, action_idx: int):
        assert self.proc is not None
        # If the engine ended or the episode deadline expired, truncate.
        if self._timed_out:
            return self._obs_from_state(self._last_state), 0.0, False, True, {"reason": "timeout"}
        if self.proc.poll() is not None:
            return self._obs_from_state(self._last_state), -1.0, True, False, {"reason": "ended"}

        # Send action
        action = self.space.to_protocol(action_idx, self._last_state or {})
        try:
            self._write(action)
        except BrokenPipeError:
            # Engine ended between last read and now
            return self._obs_from_state(self._last_state), -1.0, True, False, {"reason": "pipe"}

        # Read until next request or game_end
        while True:
            msg = self._read()
            if msg is None:
                # Process ended; determine if timeout or crash
                if self._timed_out:
                    return (
                        self._obs_from_state(self._last_state),
                        0.0,
                        False,
                        True,
                        {"reason": "timeout"},
                    )
                return self._obs_from_state(self._last_state), -1.0, True, False, {"reason": "ended"}
            mtype = msg.get("type")
            if mtype == "request_action":
                self._last_state = msg.get("state", {})
                obs = self._obs_from_state(self._last_state)
                info = {"action_mask": self.valid_action_mask()}
                reward = self._shaping_reward(*self._state_sizes(self._last_state))
                return obs, reward, False, False, info
            if mtype == "game_end":
                winner = msg.get("winner")
                counts = msg.get("card_counts", {})
                own_cards = int(counts.get("agent1", self._previous_sizes[0]))
                opponent_cards = int(counts.get("agent2", self._previous_sizes[1]))
                reward = self._shaping_reward(own_cards, opponent_cards)
                reward += 1.0 if winner == "agent1" else -1.0
                return self._obs_from_state(self._last_state), reward, True, False, {
                    "reason": "game_end",
                    "winner": winner,
                }

    # Mask function for MaskablePPO
    def valid_action_mask(self):
        return encode_action_mask(self.space, self._last_state or {})

    @property
    def current_state(self) -> Dict[str, Any]:
        return self._last_state or {}

    def close(self):
        self._terminate_proc()
        super().close()

    # Helpers
    def _wait_for_request(self):
        while True:
            msg = self._read()
            if msg is None:
                if self._timed_out:
                    return self._zero_obs()
                raise RuntimeError("engine ended before first observation")
            if msg.get("type") == "request_action":
                self._last_state = msg.get("state", {})
                return self._obs_from_state(self._last_state)

    def _read(self) -> Optional[Dict[str, Any]]:
        assert self.proc and self.proc.stdout
        import json as _json

        # Poll-read until the episode deadline expires.
        while True:
            if self._timed_out:
                return None
            if self.proc.poll() is not None:
                return None
            timeout = self._read_timeout()
            if timeout is None:
                self._timed_out = True
                self._terminate_proc()
                return None
            rlist, _, _ = select.select([self.proc.stdout], [], [], timeout)
            if not rlist:
                continue
            line = self.proc.stdout.readline()
            if not line:
                return None
            s = line.strip()
            if not s:
                continue
            # Filter out non-JSON noise; expect objects from engine
            if not s.lstrip().startswith("{"):
                continue
            try:
                return _json.loads(s)
            except Exception:
                # Skip malformed lines while time remains in the episode.
                continue

    def _write(self, obj: Dict[str, Any]) -> None:
        assert self.proc and self.proc.stdin
        import json as _json

        self.proc.stdin.write(_json.dumps(obj) + "\n")
        self.proc.stdin.flush()

    def _obs_from_state(self, state: Optional[Dict[str, Any]]):
        observation = pack_observation_for_model(state or {})
        return {
            key: np.asarray(value, dtype=np.float64)
            for key, value in observation.items()
        }

    def _zero_obs(self):
        return pack_observation_for_model({})

    def _state_sizes(self, state: Dict[str, Any]):
        opponents = state.get("other_players", [])
        opponent_cards = int(opponents[0].get("card_count", 0)) if opponents else 0
        return len(state.get("hand", [])), opponent_cards

    def _shaping_reward(self, own_cards: int, opponent_cards: int) -> float:
        previous_own, previous_opponent = self._previous_sizes
        progress = (previous_own - own_cards) + (opponent_cards - previous_opponent)
        self._previous_sizes = (own_cards, opponent_cards)
        return self.reward_scale * progress

    def _terminate_proc(self):
        if not self.proc:
            return
        proc = self.proc
        try:
            if self.persistent_engine and proc.poll() is None:
                self._write({"type": "shutdown"})
                proc.wait(timeout=1.0)
        except Exception:
            pass
        if proc.poll() is None:
            try:
                proc.kill()
                proc.wait(timeout=1.0)
            except Exception:
                pass
        self._close_streams(proc)
        self.proc = None

    def _ensure_persistent_engine(self):
        if self.proc and self.proc.poll() is None:
            return

        self._terminate_proc()
        self.proc = self._popen()

    def _read_timeout(self) -> Optional[float]:
        if self._deadline is None:
            return 0.1

        remaining = self._deadline - time.monotonic()
        return min(remaining, 0.1) if remaining > 0 else None

    def _close_streams(self, proc: subprocess.Popen) -> None:
        for stream in (proc.stdin, proc.stdout, proc.stderr):
            if stream is None:
                continue
            try:
                stream.close()
            except Exception:
                pass
