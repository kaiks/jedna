from typing import Any, Dict

from .io_stream import MessageStream
from .encoding import ActionSpace, encode_action_mask, pack_observation_for_model


class RLAgent:
    """Bridges engine messages with a policy, via modular IO/encoding/history."""

    def __init__(self, stream: MessageStream, policy, history) -> None:
        self.stream = stream
        self.policy = policy
        self.history = history
        self.space = ActionSpace()

    def run(self) -> None:
        while True:
            msg = self.stream.read()
            if msg is None:
                break

            msg_type = msg.get("type")
            if msg_type == "request_action":
                state: Dict[str, Any] = msg.get("state", {})

                # Keep inference input consistent with training (array-shaped Dict).
                obs = pack_observation_for_model(state)
                mask = encode_action_mask(self.space, state)
                act_idx = self.policy.select(obs, mask)
                action = self.space.to_protocol(act_idx, state)

                self.stream.write(action)
                self.history.push(state=state, action=action)

            elif msg_type == "game_end":
                # Optionally: extract results from msg and log a terminal reward
                self.history.close()
                break
