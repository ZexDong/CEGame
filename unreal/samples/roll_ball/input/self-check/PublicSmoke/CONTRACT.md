# Public Smoke

`Invoke-PublicSmoke.ps1` verifies release and starter health only. It does not evaluate any gameplay requirement.

The caller supplies:

- the public input root;
- a matching Unreal Engine 5.7.4 root;
- a repository root containing `engine/unreal-5.7.4/` public modules;
- a new, empty run root outside the input.

The script runs the static package gate, builds the source starter, starts a real 1280x720 game window, waits for the answer-free bridge, captures a stable frame, performs a true new-process reopen, captures again, and verifies cleanup. Results and generated files remain under the caller-owned run root or the writable project copy.
