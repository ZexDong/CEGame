# RollBall Fixed Maze Starter Project

Open `RollBallStarter.uproject` with Unreal Engine 5.7.4.

This answer-free project intentionally contains no playable ball, movement, active trap behavior, completion behavior, or gameplay restart. It loads the immutable public layout for the read-only bridge and presents the supplied board, wall, and sphere meshes in a small inert 3D material and lighting display. It does not render a maze diagram or reveal a route preview.

The final candidate may replace the preview with any reasonable Unreal implementation, but it must keep the supplied layout identity and player-facing results defined in `../GDD.md`. Generated directories are excluded by `.gitignore` and must not be included in the final handoff.
