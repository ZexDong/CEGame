# Defold task tools

Use Defold 1.13.0, its bundled JDK 25+36 and native Bob builder. Build and
launch commands are in RUNNING.md; engine inspection tools are documented in
DEFOLD_ENGINE_INTERFACE_GUIDE.md. The intended client area is 960 x 720.

The task uses the Dashboard v3 contract. Every target rectangle and
client_width/client_height use the same complete client coordinate space.
World and grid coordinates are separate. The starter handles only normal
window/input setup; implement the campaign described by the design.

Keep the root and starter_project/benchmark copies of campaign.json and
naming-tables.json identical. Load the packaged data with sys.load_resource.

BENCHMARK_PROFILE_DIR optionally selects a pre-created absolute save directory.
Only campaign-v2.json may be read or written there. Without that variable, use
the task-specific application data directory defined in CAMPAIGN_RULES.md.
Use separate profile directories for independent runs.

The process writes dashboard.jsonl in its working directory and truncates it
at a fresh start. From input/, check a real trace using:

```text
python3 tools/dashboard_self_check.py starter_project/dashboard.jsonl naming-tables.json
```

A valid not_ready snapshot verifies the observation structure only.
