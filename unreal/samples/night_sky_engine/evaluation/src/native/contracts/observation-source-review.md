# Source Review of Unresolved Observations

The optional `observation-source-review.json` is a trusted operator review, not
candidate self-attestation. It binds the exact raw run, complete candidate identity
and GDD; each decision cites hash-bound source lines, runtime traces, call-path
reasoning and limitations. The source snapshot must match the candidate manifest.
Only entries explicitly recorded as `gap` by the collector may be resolved. A source
pass never overrides an independent runtime failure. A source failure fails the
existing owner. Absent or incomplete review continues to block score publication.

The same predicates apply to every candidate. No candidate identity is eligible
for an exception, and a non-gap runtime failure cannot be changed to a pass.

`reviewed_boundaries.py` validates and applies this optional review in the canonical
scoring stage. Collected raw files, traces and boundary reports remain immutable.
Results identify the supplemental review and validator hashes. Source-assisted
resolution is limited to explicitly unresolved observations and never substitutes
for a required normal-input gameplay trace.
