# D6 visual protocol 2.0.0

The current canonical scoring guide is `gamecreate/GAME_INDEPENDENT_SCORING_GUIDE.md`, Section 6. Its hash, the exact fixed prompt hash, source capture hashes and the three representative states are bound in `reference-manifest.json`. Only the state-label placeholder is substituted. The image order is always original reference followed by candidate.

The references are actual normal-input client captures of the UE 5.7.4 adapted original's LEVEL_2: initial active room, sword swing and grounded jump. They were captured before the first gold runtime session. The complete 1920x1080 client frames are uniformly resized to 1280x720; no elements are composed, removed or redrawn. Original camera framing and level numbering remain visible. The public task adapts numbering, terminal behavior and the corridor pig; these differences are documented and do not turn the design illustration into runtime evidence.

The reference manifest fixes the judge model. Supply the endpoint and key through the runtime environment. A complete evaluation requires one consistent returned model identity, three full rounds, and all three equal-weight states in every round. Each state has five criteria restricted to 0, 0.5, 1, 1.5 or 2. The parser rejects extra/missing lines and incorrect totals. The scorer re-parses stored raw responses, checks exact prompt/image identities and computes each round mean and their arithmetic mean. It never trusts a caller-supplied total.

The client may retry the same request at most twice after HTTP 500, 502, 503 or 504, with bounded backoff. Other HTTP errors remain infrastructure failures.

Absent candidate state, black frame or a severely broken/uncomparable frame receives zero for that state. A missing or modified private reference, failed VLM request, malformed response, inconsistent returned model within one run, stale run binding, or missing receipt is an infrastructure/protocol fault. Such a run is incomplete and has no score row. No best-round selection, state dropping or missing-value averaging is allowed.

Run `scripts/d6.py` after dynamic collection and the independent runtime picture review. D6 sees no gameplay snapshots, code, pass/fail decisions or score catalog. D1-D5 never call this model.
