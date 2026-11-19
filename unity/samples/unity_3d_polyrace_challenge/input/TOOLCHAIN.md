# Technical delivery
- Fixed Unity6000.0.80f1, Input System1.19.0, Test Framework1.6.0, uGUI2.0.0;
  installed engine/CLI documentation is UNITY_BENCHMARK_TOOL_GUIDE.md.
- Actual final scene: Assets/Game/Scenes/Game.unity, first enabled Build Settings
  entry. All new implementation/helpers/scenes/materials under Assets/Game/.
- Use the ordinary Input System keyboard/mouse path and genuine uGUI controls.
  World actors may use SpriteRenderer/Renderer and normal physics or spatial
  simulation; grid target roots are real board cells, not reporting proxies.
  No reflection-based special action API, editor-only game or host-global input.
- Target1280x720, sensible Canvas scaling. Built-in renderer is initially active;
  no additional render-pipeline package is needed. Do not change packages.
- Implement GameCreate.Session.IGameSession from the supplied package.
  Assets/Resources/session-model.json and content.json duplicate the protected
  root data for runtime use; keep them unchanged. No other observation interface.
- Only this project is task input/workspace. Do not inspect parent directories,
  other projects, previous results or external game source. Installed engine,
  CLI, normal package loading and their normal operation are allowed. Do not
  modify engine/tool installation or download additional tools/packages/assets.
- Writable: Assets/Game/**, ProjectSettings/EditorBuildSettings.asset,
  ProjectSettings/ProjectSettings.asset, GraphicsSettings.asset,QualitySettings.asset,
  Logs/**. All task documents, supplied art, public service/self-check packages,
  package versions and starter are protected.
- Optional public PlayMode checks: filter GameCreate.Session.PublicChecks,
  four service-only tests. Their code is supplied and does not implement or
  certify game rules/content. Other validation strategies remain your choice.

Required service: GAME_SESSION_SPEC.md; authoritative state/edit rules: SESSION_MODEL.json.

The inactive, script-free Assets/Resources/UIRenderDependencies.prefab retains standard uGUI/font render dependencies for standalone builds. It is not a game screen; keep it unchanged.
