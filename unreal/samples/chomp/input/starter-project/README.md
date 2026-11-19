# Chomp Starter

This C++ Blank project contains an inert welcome screen and an outbound JSON observation transport. It contains no playable pawn, maze, pickups, input mappings, ghost logic, menus, save system, or gameplay timers. Static presentation resources in `Content/Art/` are unassembled and mandatory for the visible roles in GDD ASSET-01..05. Editable source copies are in `SourceArt/Meshes/`, `SourceArt/Textures/` and `SourceArt/UI/`; the life icon is also imported at `Content/Art/UI/T_LifeIcon.uasset`.

The installed engine supplies `/Engine/Maps/Entry`. Replace the welcome screen and set your final default game map in `Config/DefaultEngine.ini`. Keep this project filename and module buildable. All gameplay remains to be implemented from `../GDD.md`.

`UObservationTransport` publishes observations supplied by your implementation without changing its world. See `../contracts/README.md`. The starter publishes `provider_ready=false` and `game_state=null` honestly. Its output is not a gameplay implementation.
