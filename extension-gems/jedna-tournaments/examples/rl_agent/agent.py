from typing import Any, Dict

from .io_stream import MessageStream
from .encoding import ActionSpace, encode_action_mask, encode_observation


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

                obs = encode_observation(state)
                mask = encode_action_mask(self.space, state)
                act_idx = self.policy.select(obs, mask)
                action = self.space.to_protocol(act_idx, state)

                self.stream.write(action)
                self.history.push(state=state, action=action)

            elif msg_type == "game_end":
                # Optionally: extract results from msg and log a terminal reward
                self.history.close()
                break

