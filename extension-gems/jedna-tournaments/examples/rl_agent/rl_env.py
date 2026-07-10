from __future__ import annotations

import os
import subprocess
import threading
import time
import select
from typing import Any, Dict, Optional, Tuple

import gymnasium as gym
from gymnasium import spaces

from .encoding import ActionSpace, encode_action_mask, pack_observation_for_model


class JednaVsProcessEnv(gym.Env):
    """Gymnasium env controlling agent1 vs a process opponent.

    - Spawns Ruby engine_bridge.rb with OPPONENT_CMD env set.
    - Observations are dict features; action space is Discrete over fixed action set.
    - Rewards: +1 on win, -1 on loss, 0 otherwise.
    - info contains 'action_mask' for MaskablePPO.
    """

    metadata = {"render_modes": []}

    def __init__(self, engine_path: str, opponent_cmd: str, *, max_seconds: float = 60.0):
        super().__init__()
        self.engine_path = engine_path
        self.opponent_cmd = opponent_cmd
        self.proc: Optional[subprocess.Popen] = None
        self.max_seconds = max_seconds
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
            }
        )
        self.action_space = spaces.Discrete(self.space.size())

        self._last_state: Optional[Dict[str, Any]] = None
        self._watchdog: Optional[threading.Thread] = None
        self._timed_out = False

    def _popen(self) -> subprocess.Popen:
        env = os.environ.copy()
        env["OPPONENT_CMD"] = self.opponent_cmd
        return subprocess.Popen(
            ["ruby", self.engine_path],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
            env=env,
        )

    def reset(self, *, seed: Optional[int] = None, options: Optional[Dict[str, Any]] = None):
        super().reset(seed=seed)

        # Clean up any existing process/watchdog before starting a new episode
        self._stop_watchdog()
        self._terminate_proc()
        self._timed_out = False

        self.proc = self._popen()
        self._watchdog = threading.Thread(target=self._watch, args=(self.proc,), daemon=True)
        self._watchdog.start()

        obs = self._wait_for_request()
        info = {"action_mask": self.valid_action_mask()}
        return obs, info

    def step(self, action_idx: int):
        assert self.proc is not None
        # If engine already ended or watchdog fired, truncate
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
                return obs, 0.0, False, False, info
            if mtype == "game_end":
                winner = msg.get("winner")
                reward = 1.0 if winner == "agent1" else -1.0
                return self._obs_from_state(self._last_state), reward, True, False, {"reason": "game_end"}

    # Mask function for MaskablePPO
    def valid_action_mask(self):
        return encode_action_mask(self.space, self._last_state or {})

    def close(self):
        self._stop_watchdog()
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

        # Poll-read with timeout so we can honor watchdog timeouts
        while True:
            if self._timed_out:
                return None
            if self.proc.poll() is not None:
                return None
            rlist, _, _ = select.select([self.proc.stdout], [], [], 0.1)
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
                # Skip malformed line; keep reading until timeout/watchdog
                continue

    def _write(self, obj: Dict[str, Any]) -> None:
        assert self.proc and self.proc.stdin
        import json as _json

        self.proc.stdin.write(_json.dumps(obj) + "\n")
        self.proc.stdin.flush()

    def _obs_from_state(self, state: Optional[Dict[str, Any]]):
        return pack_observation_for_model(state or {})

    def _zero_obs(self):
        return pack_observation_for_model({})

    def _terminate_proc(self):
        if not self.proc:
            return
        try:
            self.proc.kill()
        except Exception:
            pass
        try:
            self.proc.wait(timeout=1.0)
        except Exception:
            pass
        self.proc = None

    def _stop_watchdog(self):
        if self._watchdog and self._watchdog.is_alive():
            try:
                self._watchdog.join(timeout=1.0)
            except Exception:
                pass
        self._watchdog = None

    def _watch(self, proc: subprocess.Popen):
        start = time.time()
        while True:
            time.sleep(0.1)
            if time.time() - start > self.max_seconds:
                if proc is self.proc:
                    self._timed_out = True
                try:
                    proc.kill()
                    proc.wait(timeout=1.0)
                except Exception:
                    pass
                return
            if proc.poll() is not None:
                return
