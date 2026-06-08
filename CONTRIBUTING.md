# Contributing to Harness

## One-way-leak enforcement

The public core must never reference private markers (private repo paths, work GitHub accounts/work-org tokens, hardcoded Claude Code home paths, private bead IDs in private namespaces). This is the ADR-002 D7 one-way rule. The exact marker classes (C1–C6) and their patterns are defined in `scripts/oneway-check.py`.

### Pre-push hook

A pre-push hook in `.githooks/pre-push` enforces this automatically. It runs:
1. `uv run scripts/oneway-check.py` — scans all core-manifest assets for private markers
2. `uv run scripts/test_oneway_check.py` — verifies the engine itself is intact

If either exits non-zero the push is blocked.

**Fresh clones do not inherit `core.hooksPath` from the repo.** After cloning, run once to activate the hook:

```sh
git config core.hooksPath .githooks
```

### CI

The same two checks run in CI on every push and pull request via `.github/workflows/oneway-check.yml`.

### Running the checks manually

```sh
# Check core assets for private markers (exit 0 = green, exit 1 = leak found):
uv run scripts/oneway-check.py

# Run the engine self-test (22 tests):
uv run scripts/test_oneway_check.py
```
