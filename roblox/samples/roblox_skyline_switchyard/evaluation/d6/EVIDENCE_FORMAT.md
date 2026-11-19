# External D6 evidence binding

Numeric `round_scores` and `final_score` alone are rejected. Supply:

- `round_scores`: three actual review scores; `final_score`: their fixed one-decimal mean.
- `binding`: `candidate_sha256`, `prompt_sha256`, `reference_sha256`, `reviewer_model`.
- `screenshots`: four records `{ "path": "relative-image.png", "sha256": "..." }`.
- `responses`: three records `{ "path": "relative-answer.json", "sha256": "..." }`.

Paths resolve relative to the visual JSON. Each answer JSON retains `response_id`, `model`,
the matching `binding`, the ordered four `image_sha256` values,
and the five numeric `criteria` values in [0,2] from the actual response. Their sum must
match its round score. Retain the original provider response and metadata.
File binding verifies local consistency, not provider authenticity.
The validator copies these evidence files into the result directory.

`src/visual_binding.py: candidate_digest` defines the candidate binding: SHA-256 of a
submitted ZIP/place file, or SHA-256 of compact sorted JSON mapping directory-relative
filenames to content hashes (excluding generated engine/cache directories). Prompt,
reference and reviewer are compared against this sample's fixed d6/protocol.json.
