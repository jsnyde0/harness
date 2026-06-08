# Pi Package Design and Trust Review

Use this reference when designing, publishing, installing, or recommending Pi packages.

## Package shape

Pi packages can bundle:

```text
extensions/
skills/
prompts/
themes/
README.md
package.json
```

Package only after local/global usage has stabilized:

- config schema is stable
- tools and commands have clear descriptions and model-facing metadata
- failure behavior is documented
- README includes install, usage, config, and uninstall notes
- tests or manual validation exist
- security/trust review is complete

## `package.json` guidance

- Add `"pi-package"` to `keywords` for discoverability/gallery support.
- Put runtime libraries in `dependencies`.
- Put Pi core packages in `peerDependencies` with `"*"` and do not bundle them:
  - `@mariozechner/pi-ai`
  - `@mariozechner/pi-agent-core`
  - `@mariozechner/pi-coding-agent`
  - `@mariozechner/pi-tui`
  - `typebox`
- Keep build output deterministic and avoid publishing private artifacts.

## Install forms

Common install forms:

```bash
pi install npm:<package>
pi install git:github.com/<owner>/<repo>
pi install /path/to/local/package
```

Use local path installs while developing. Prefer pinned npm versions or git commit SHAs for sensitive workflows.

## Package filters

If a package contains multiple resources, design for selective enablement where appropriate:

- split unrelated features into separate resources
- document resource names
- make optional skills/prompts/extensions independently understandable
- avoid forcing broad tool surfaces for one small feature

## Trust review before installing/recommending

Pi packages can include extensions that execute with local process privileges. Before installing or recommending:

- inspect extension source
- identify install-time and runtime dependencies
- check network calls and credential access
- check file read/write locations
- check subprocess execution and shell quoting
- check package provenance, maintenance, and version history
- understand which extensions, skills, prompts, and themes are enabled
- prefer pinned versions/commits for sensitive workflows
- verify uninstall/disable path

## README contract

A good package README states:

- what gets installed
- commands/tools/hooks registered
- config file locations and schema
- state/artifact locations
- network and credential behavior
- safety/failure behavior
- examples for interactive and non-interactive use
- known compatibility issues with other extensions

## Release checklist

Before publishing:

- run tests and a Pi smoke test
- verify no secrets, auth files, session logs, or personal caches are included
- verify built files match source
- verify peer dependencies and `pi-package` keyword
- update README examples
- tag release or document exact version
