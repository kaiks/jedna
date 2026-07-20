# Repository Guidelines

## Project Structure & Modules
- Root gem: Ruby library in `lib/` with entry `lib/jedna.rb` and submodules under `lib/jedna/` (`core/`, `interfaces/`, serializers, thread-safety helpers).
- Tests: RSpec specs in `spec/`, mirroring `lib/` paths (e.g., `lib/jedna/core/card.rb` → `spec/core/card_spec.rb`).
- Extension gems: under `extension-gems/` (e.g., `extension-gems/jedna-tournaments`) with their own `lib/`, `spec/`, and `README.md`.
- Docs: `README.md`, `automated_play.md`, `game_rules.md`, migration notes in `MIGRATION_NOTES.md`.

## Build, Test, and Development
- Install tools (use `mise`): `mise install` (Ruby `4.0.6`).
- Install deps: `bundle install` (at repo root and inside any extension gem directory if working there).
- Run tests (root): `bundle exec rspec`.
- Run tests (tournaments ext): `cd extension-gems/jedna-tournaments && bundle exec rspec`.
- Lint/format: `bundle exec rubocop`.
- Build gem: `gem build jedna.gemspec`.

## Coding Style & Naming
- Ruby style: 2-space indentation, UTF-8, frozen string literals at top of files.
- Naming: files `snake_case.rb`; classes/modules `CamelCase`; methods/vars `snake_case`.
- Public API: keep modules under `Jedna::...`; extension gems should namespace under their gem module (e.g., `JednaTournaments::...`).
- Linting: follow RuboCop defaults; add local `.rubocop.yml` only when necessary and in small, focused diffs.

## Testing Guidelines
- Framework: RSpec (~> 3). Prefer example-driven specs that reflect gameplay rules.
- Structure: place specs in `spec/` mirroring `lib/` paths; name files `*_spec.rb`.
- Expectations: add specs for new behavior and regressions; keep stdout silent (spec helper already captures it).
- Run subset: `bundle exec rspec spec/core/game_spec.rb:42` (line filtering).

## Commits & Pull Requests
- Commits: short imperative summary, optional scope, e.g., `core: fix skip logic` or `Rubocop fixes`.
- PRs: include context, rationale, and before/after behavior; link issues; add tests; note breaking changes and migration steps.
- CI hygiene: ensure `rspec` and `rubocop` pass locally before opening a PR.

## Agent & Security Notes
- Agent protocol: see `automated_play.md` for stdin/stdout JSON message formats used by automated agents.
- Safety: avoid executing untrusted agent commands; prefer explicit whitelists when wiring `ProcessAgent` in examples.
