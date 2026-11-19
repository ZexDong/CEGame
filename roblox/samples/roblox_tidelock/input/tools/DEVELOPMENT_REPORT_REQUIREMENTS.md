# Development and run report requirements

Produce one candidate in one independent development session under the stated 3600-second limit. Keep development reports with the candidate submission.

DEVELOPMENT_TRACE.txt records candidate name, task name/link, framework/model/mode/version when available, start/handoff times with timezone, supplied public-input archive SHA-256, and working-copy path only. Record top-level actions chronologically (read/create/edit/build/open/Play/observe/fix/rebuild/final validation), each with `time | action | target/command | result | related file or Play session`. Do not turn internal thought, per-frame polling or tool-internal retries into separate development steps. If raw task/tool logs or token usage can be exported, return them unchanged as optional candidate artifacts. If unavailable, state N/A and why; do not estimate tokens from file sizes or character counts.

Assign every real Play session a unique ID and record start/stop times, public checklist numbers, actual input summary, state/world observations, whether failures came from candidate/controller/tool/environment, and resulting fixes. Label debugging failures as debugging, not final successful evidence.

Declare whether you accessed reference correct implementations, private evaluator/rubric/traces, fault versions, historical candidates or parent/sibling directories outside the input copy. Normal answers are no. Record accidental access with file, time and impact rather than conceal it.

After edits stop, produce SHA-256 records for final ZIP, place, reports and project inventory. Store hashes in a separate handoff manifest so the report does not need to contain its own self-referential hash; an external ZIP hash necessarily accompanies rather than lives inside that ZIP.

RUN_REPORT.txt includes candidate name, exact Studio/Rojo versions, final build time/timezone and place SHA-256. For public PLAY_CHECKLIST items 1–38 record PASS/FAIL/NOT RUN, Play session, real inputs, observed attributes/events/HUD/physics, fixes and remaining issues or unrun reasons. Conclude with whether full real Play completion, death recovery, failure Retry, R in all three states and Reopen were actually verified, plus a list of unverified items.
