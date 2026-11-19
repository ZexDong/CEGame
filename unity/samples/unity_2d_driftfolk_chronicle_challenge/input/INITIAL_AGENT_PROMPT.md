HARD WALL-CLOCK LIMIT: You have at most 3600 seconds for this implementation turn. At that limit the launcher will stop the process and retain the project exactly as it exists; there is no extension or second generation turn.

# Build Driftfolk: Stormbound

Build the complete game described in `GDD.md` and implement the required `GameCreate.Session.IGameSession` service. **The complete game and the public session service are both delivery requirements.** Automated acceptance uses the published service for normal entry, complete legal-state capture and restoration, and real-object queries. Missing or incorrect service behavior can lose the requirements that depend on it; implementing only the interface without the real game is not sufficient.

The current working directory is the supplied Unity project. Read `README.md`, `GDD.md`, `GAME_SESSION_SPEC.md`, `SESSION_MODEL.json`, and `BENCHMARK_MANIFEST.json`. Use the supplied assets and preserve protected content. Make the saved final scene playable through the normal controls in the GDD and suitable for a Windows standalone player. Do not create a nested Unity project.

## Fixed tools

Unity Editor:
`D:\game\engine\unity\6000.0.80f1\Editor\Unity.exe`

Unity CLI:
`D:\game\engine\shared-tools\unity\cli\1.0.0-beta.3\unity.exe`

The tool catalog and `TOOLCHAIN.md` describe optional engine feedback and public development checks. Choose whatever verification is useful within the task; the checks do not implement the game or certify all its requirements.

Finish the complete requested product within this session rather than proposing later work.
