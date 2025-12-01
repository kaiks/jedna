import sys
from typing import Any, Dict, Optional


class MessageStream:
    """Abstract IO for agent<->engine messages."""

    def read(self) -> Optional[Dict[str, Any]]:
        raise NotImplementedError

    def write(self, obj: Dict[str, Any]) -> None:
        raise NotImplementedError


class JSONLineStream(MessageStream):
    """JSON-over-stdin/stdout line protocol (default).

    Pluggable parser: tries orjson, then ujson, then stdlib json.
    """

    def __init__(self, infile=None, outfile=None) -> None:
        self.infile = infile or sys.stdin
        self.outfile = outfile or sys.stdout

        self._loads, self._dumps = self._select_json_impl()

    @staticmethod
    def _select_json_impl():
        try:  # Fast-path
            import orjson

            def _loads(s: str):
                return orjson.loads(s)

            def _dumps(obj: Dict[str, Any]) -> str:
                return orjson.dumps(obj).decode()

            return _loads, _dumps
        except Exception:
            pass
        try:
            import ujson as json  # type: ignore
        except Exception:
            import json  # type: ignore

        return json.loads, lambda o: json.dumps(o, separators=(",", ":"))

    def read(self) -> Optional[Dict[str, Any]]:
        line = self.infile.readline()
        if not line:
            return None
        return self._loads(line)

    def write(self, obj: Dict[str, Any]) -> None:
        self.outfile.write(self._dumps(obj) + "\n")
        self.outfile.flush()

