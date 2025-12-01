"""
Lightweight, modular RL agent scaffold for Jedna tournaments.

Modules:
- io_stream: pluggable message IO (JSON line default)
- encoding: observation + action space + masks
- policy: random masked policy and SB3 adapter stub
- history: pluggable history sinks (noop, JSON lines)
- agent: ties everything together
- main: CLI entrypoint

This package is intentionally dependency-light; optional fast parsers
and RL libs are imported if available.
"""

