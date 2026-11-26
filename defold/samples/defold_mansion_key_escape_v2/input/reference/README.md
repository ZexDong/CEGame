# Public reference pages

This directory contains 11 page states captured from frozen Gold running at a `960×540` logical
canvas. They are native desktop Retina window captures sized `1920×1144`, and the top may include the title
bar. GDD game coordinates still use the `960×540` client area with a bottom-left origin.

| File | State |
|---|---|
| `01_menu.png` | Main menu with New Game selected |
| `02_controls.png` | Controls page |
| `03_foyer.png` | Clean New Game foyer |
| `04_study_locked.png` | Study with closed garden door |
| `05_journal.png` | Journal modal |
| `06_key_found.png` | Cabinet solved and key revealed |
| `07_door_open.png` | Key consumed and garden door open |
| `08_courtyard.png` | Garden and right-side exit |
| `09_victory.png` | Success page |
| `10_game_over.png` | Failure page |
| `11_restarted.png` | Foyer after failure restart |

These images are part of the public task specification, not Gold source or private evaluation
journeys. Section 6 of the GDD identifies which spatial relationships, coordinates, and page
hierarchy affect acceptance; unnamed pixel differences do not.

Do not use a whole screenshot as a static background or full-page image to imitate gameplay. The
player, rooms, key, door, shadow, collision, interaction, HUD, and modal UI must change with real
state and respond to normal player input.
