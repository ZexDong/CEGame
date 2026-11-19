# Public scaffold tests

`RUN_SCAFFOLD_TESTS.ps1` checks only public engine-facing scaffold facts:

- bundled tool files exist and report usable versions;
- every `.luau` file compiles independently;
- Rojo builds the declared project;
- the generated RBXLX is non-empty, parses as XML, and receives a SHA-256.

The script writes a fresh result under `results/<timestamp>/`. It performs no private gameplay trajectory, contains no Gold implementation detail, and does not claim Studio Play or full gameplay success.

