# Canonical D6 contract

Protocol: canonical_five_criteria_three_rounds. Authority: gamecreate/GAME_INDEPENDENT_SCORING_GUIDE.md section 6, hash-bound in protocol.json.

Three equal-weight visual roles: active arena, bomb explosion feedback and round-result screen. All references use one original-game Blockout map with native AI opponents. The existing candidate capture keys active-duel, chain-reaction and player1-win are retained for compatibility. The original explosion need not be a chain and its result need not be a human victory: D6 judges visible assembly and presentation, not AI behavior, chain timing or winner identity. The original result image displays LOSE; its candidate partner may display PLAYER 1 WINS. These are corresponding round-result screens, not a gameplay correctness assertion.

References come from the original-game UE 5.7.4 baseline, with UI-inclusive UE-native render receipts accepted by Set-BomberOriginalReferences.ps1. All three images are 1280x720, nonblank, bound to Map.Blockout, and captured in InGame/InGame/EndGame phases. An optional original-only read observer records acquisition metadata; the candidate runner never enables it. Gold/candidate images are excluded from the reference package. Missing references invalidate evaluator setup and prohibit D6/Overall publication.

Each pair receives the exact canonical English prompt with only its state label substituted. Five criteria each allow 0, 0.5, 1, 1.5, 2; their sum must equal the parsed total. Three independent rounds use one returned VLM identity: at most nine calls. Missing candidate states receive zero without API calls. Final D6 averages unrounded state scores and rounds only for display; displayed round means are not reused in final averaging.

Each candidate image needs a .semantic.json sidecar binding image SHA-256, candidate identity, before/after states, native render receipt/time, process and round. Both semantic samples must describe the requested state and bracket capture time. Desktop/mistimed images, absent sidecars, stale response/image bindings and parser failures are evaluator faults.

Model and base URL remain configurable. Preserve credential-free request/image hashes, raw responses, criterion scores and per-round results. No D6 judgments participate in D1-D5.

Requests are serial, contain exactly one reference/candidate pair, and may not exceed 8 MiB of UTF-8 JSON. The timeout is bounded to 240 seconds. Missing, black/blank, invalid PNG and wrong-resolution candidate frames have the same health classification in the request stage and aggregation stage; these states receive three automatic zeros without HTTP. Original-reference or semantic-provenance failures remain infrastructure faults.

The completion entry point can finish a valid existing D1-D5 run. An interrupted VLM run may resume only with the same invocation identity, including candidate/reference hashes, prompt, endpoint hash, requested model and parameters. Each accepted call is checkpointed; resume validates its request and raw-response hashes and reparses its response. Incomplete-call evidence and prior faults are preserved before retry. No automatic retries or completed-score overwrites are allowed. Raw bodies are saved before envelope or score parsing, and one returned model identity must hold across resumed calls as well as all three rounds.
