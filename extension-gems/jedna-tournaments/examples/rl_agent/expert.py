from __future__ import annotations

import json
import subprocess
from typing import Any, Dict, Tuple

import numpy as np
import torch

from .rl_env import JednaVsProcessEnv


class ProcessExpert:
    """Query a stateless JSON-lines agent as a behavior-cloning teacher."""

    def __init__(self, command: str):
        self.process = subprocess.Popen(
            command,
            shell=True,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )

    def action(self, state: Dict[str, Any]) -> Dict[str, Any]:
        if not self.process.stdin or not self.process.stdout:
            raise RuntimeError("expert process has no protocol pipes")

        request = {"type": "request_action", "state": state}
        self.process.stdin.write(json.dumps(request) + "\n")
        self.process.stdin.flush()
        line = self.process.stdout.readline()
        if not line:
            raise RuntimeError("expert process stopped responding")
        return json.loads(line)

    def close(self) -> None:
        if self.process.poll() is None:
            self.process.terminate()
        try:
            self.process.wait(timeout=1.0)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()


def collect_expert_dataset(
    env: JednaVsProcessEnv,
    expert_command: str,
    steps: int,
    seed: int,
) -> Tuple[Dict[str, np.ndarray], np.ndarray, np.ndarray]:
    """Collect expert state/action pairs while playing real engine games."""
    observations: Dict[str, list] = {}
    actions = []
    masks = []
    episode = 0
    expert = ProcessExpert(expert_command)
    observation, info = env.reset(seed=seed)

    try:
        for _ in range(steps):
            protocol_action = expert.action(env.current_state)
            action = env.space.from_protocol(protocol_action)
            mask = np.asarray(info["action_mask"], dtype=np.float32)
            if not mask[action]:
                raise RuntimeError(f"expert selected masked action: {protocol_action!r}")

            for key, value in observation.items():
                observations.setdefault(key, []).append(value)
            actions.append(action)
            masks.append(mask)

            observation, _reward, terminated, truncated, info = env.step(action)
            if terminated or truncated:
                episode += 1
                observation, info = env.reset(seed=seed + episode)
    finally:
        expert.close()

    packed_observations = {
        key: np.asarray(values, dtype=np.float32) for key, values in observations.items()
    }
    return (
        packed_observations,
        np.asarray(actions, dtype=np.int64),
        np.asarray(masks, dtype=np.float32),
    )


def pretrain_policy(
    model,
    observations: Dict[str, np.ndarray],
    actions: np.ndarray,
    masks: np.ndarray,
    *,
    epochs: int,
    batch_size: int,
    seed: int,
) -> float:
    """Warm-start a MaskablePPO policy with masked behavior cloning."""
    rng = np.random.default_rng(seed)
    policy = model.policy
    policy.set_training_mode(True)
    final_loss = 0.0

    for epoch in range(epochs):
        losses = []
        order = rng.permutation(len(actions))
        for start in range(0, len(actions), batch_size):
            indices = order[start : start + batch_size]
            batch = {key: values[indices] for key, values in observations.items()}
            observation_tensor, _ = policy.obs_to_tensor(batch)
            action_tensor = torch.as_tensor(actions[indices], device=policy.device)
            mask_tensor = torch.as_tensor(masks[indices], device=policy.device)

            _values, log_probability, entropy = policy.evaluate_actions(
                observation_tensor,
                action_tensor,
                action_masks=mask_tensor,
            )
            loss = -log_probability.mean() - 0.001 * entropy.mean()
            policy.optimizer.zero_grad()
            loss.backward()
            torch.nn.utils.clip_grad_norm_(policy.parameters(), 0.5)
            policy.optimizer.step()
            losses.append(float(loss.detach().cpu()))

        final_loss = float(np.mean(losses))
        print(f"[Behavior cloning] epoch={epoch + 1}/{epochs} loss={final_loss:.4f}")

    return final_loss
