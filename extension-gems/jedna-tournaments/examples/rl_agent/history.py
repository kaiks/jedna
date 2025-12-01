from typing import Any, Dict, Optional


class HistorySink:
    def open(self) -> None:
        pass

    def write(self, record: Dict[str, Any]) -> None:
        pass

    def close(self) -> None:
        pass


class NoopSink(HistorySink):
    pass


class JSONLineFileSink(HistorySink):
    def __init__(self, path: str) -> None:
        self.path = path
        self._fh = None

    def open(self) -> None:
        self._fh = open(self.path, "a", encoding="utf-8")

    def write(self, record: Dict[str, Any]) -> None:
        if not self._fh:
            return
        try:
            import orjson  # type: ignore

            line = orjson.dumps(record).decode()
        except Exception:
            try:
                import ujson as json  # type: ignore
            except Exception:
                import json
            line = json.dumps(record, separators=(",", ":"))
        self._fh.write(line + "\n")

    def close(self) -> None:
        if self._fh:
            self._fh.close()
            self._fh = None


class HistoryBuffer:
    """Collects (state, action, reward, info) tuples and writes via sink.

    The sink can be swapped for performance (e.g., binary formats) later without
    touching agent logic.
    """

    def __init__(self, sink: Optional[HistorySink] = None) -> None:
        self.sink = sink or NoopSink()
        self.sink.open()

    def push(self, *, state: Dict[str, Any], action: Dict[str, Any], reward: Optional[float] = None, info: Optional[Dict[str, Any]] = None) -> None:
        rec: Dict[str, Any] = {"state": state, "action": action}
        if reward is not None:
            rec["reward"] = float(reward)
        if info is not None:
            rec["info"] = info
        self.sink.write(rec)

    def close(self) -> None:
        self.sink.close()

