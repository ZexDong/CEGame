# Room Art Data

`room-layout.json` supplies the original room's static art placement. It is editable source data for import into the writable project. It contains no collision, physics, actor, trigger, navigation, AI, player spawn or gameplay state. `room-art-preview.png` is a visual check of those art layers, not a playable scene or replacement for the tile data.

The canvas is 27 by 20 cells, each 32 by 32 source pixels. Coordinates start at the top-left corner of the canvas, with x increasing rightward and y downward. Empty surrounding cells are intentional; frame the occupied room for play. Uniform scaling is allowed by the GDD.

Each layer contains 20 rows of 27 cells. A null cell is empty. A cell's `tile` is a zero-based row-major index into `tileset_image`; divide that image's width by the tile width to obtain the atlas column count. `flip_diagonal` exchanges the tile's x and y axes, then `flip_x` and `flip_y` reflect the resulting image horizontally and vertically. Draw layers in ascending `draw_order`. There is no prescribed Unreal object or package layout.

Decoration entries reference individual raw images. `center_px` gives the image center in the same canvas coordinates, `scale_xy` gives its scale, and `rotation_degrees` gives its in-plane counterclockwise rotation. Lower `depth` values are in front of higher ones. The decorations are presentation only; their source frame sheets remain available for animated candle and chain presentation.

The key, exit, spring, one-way ledges, spikes, player and pig must be assembled and implemented independently. Their player-visible placement and behavior are specified in `GDD.md` Section 6 and `references/room-reference.png`. The reference is a design illustration assembled from the supplied art, not a runtime capture or a HUD layout specification. ENEMY-01 defines the pig's floor corridor by the short divider, hollow masonry structure and right wall. The pictured pig position illustrates occupancy of that corridor; its exact starting horizontal position is free within the requirement's clearances.

All paths in the JSON are relative to the public input root. Keep this source material unchanged and work on imported or copied material inside `starter-project/`. No importer or generated engine asset is included.
