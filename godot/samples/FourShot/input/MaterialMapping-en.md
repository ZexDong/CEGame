# Dungeon Four Shot — Public Asset Mapping

> Version v0.8. This non-normative table is a path, metadata, and license index and creates no independent scoring item. Asset acceptance is defined only by `GDD-en.md` 6.6. SHA-256 values detect accidental replacement of distributed source files. Licensing basis: `LICENSES.md` and `ASSET_AUTHORIZATION.md`.

## 1. Images and font

| Requirement | Path relative to `Asserts/` | Information / SHA-256 | Use |
|---|---|---|---|
| ASSET-01 | `images/Player/Player.png` | 192×320; `ed230a840a2f05046f567b114757f37d1b4b28573511e915c37d20bb318f9f7f` | Player idle/movement |
| ASSET-01 | `images/Player/Player_Actions.png` | 96×576; `9230ed9335ee9582cfed64b8185a8bd5ac63bd4d7bb63af0a98de037d5bf7d4e` | Player action feedback |
| ASSET-02 | `images/Enemies/slime.png` | 224×416; `b01cd4b8ec9ee8ef7dd0ef1da1dcf24fe9f33a0c37ccac1e3b285fa942333f81` | Shared normal/elite slime source |
| ASSET-03 | `images/Enemies/Boss/Golem Idle (Shading).png` | 48×48; `8a84e98653b644c0f7bc84c596ed2bcd63fdf13f8e3021a8025284d67ca0f7b6` | Golem idle |
| ASSET-03 | `images/Enemies/Boss/Golem Heavy Walk (Shading).png` | 64×64; `a71c73f573266b9085e6a9ab78aae46671de34728376e65d0bfe559aceb532e2` | Golem movement |
| ASSET-03 | `images/Enemies/Boss/Golem Dying (Shading).png` | 48×48; `d491ea9ead6d166202642074e96c0d19b041c45b489c46e89204c9e225c12ff7` | Golem death |
| ASSET-03 | `images/Enemies/Boss/Golem (Shading).png` | 16×16; `57d75aa11940be6e85f6492492a6aaf44578671c2cd5f051cab8e1dad5498073` | Boss body, portrait, prompt |
| ASSET-04 | `images/Tileset/atlas_floor-16x16.png` | 112×112; `d7ca51d74cf999f90f31dfe195bdd6bae9593c0be7c107ac4a92d0f07a8711b5` | Floors and door cues |
| ASSET-04 | `images/Tileset/atlas_walls_low-16x16.png` | 192×64; `4595a2fff6f8cff3613875601202a2d4a7ca61f53fda82fb2e1c766ac1828d5c` | Low walls/obstacles |
| ASSET-04 | `images/Tileset/atlas_walls_high-16x32.png` | 384×128; `fb95c702be578609c4715a988d79618cfa281531d50ba9cb3e31e795c75a7780` | High walls/obstacles |
| ASSET-05 | `images/Weapons/ak67/side.png` | 36×16; `7102f44e9599776276e13b91d717d5bc908e69ac2f279b413ae27273587ae2e4` | HK-67 world image |
| ASSET-05 | `images/Weapons/glock21/side.png` | 18×11; `c96af63bc0009e85d17fa14b4b8d6210b58b6e11172b00f6480351d6be760f16` | Glock-21 world image |
| ASSET-05 | `images/Weapons/hotbar/ak67.png` | 48×24; `340dc4fa209609960076f3dc530c38828002f8d23e5c1b1ee5661cc0c25971c9` | Hotbar image |
| ASSET-05 | `images/Weapons/specialsniper/46.png` | 32×16; `2233713f3bb4b5f305e8b73b0c3d1135547d2a6a8926653674afcc94b136dd77` | Single-use special sniper; the visible dropped pickup is the public `special_rifle` dashboard entity/target, while held state is reported by `selected_weapon=3` |
| ASSET-05 | `images/Weapons/16x16 Pixel Shade Bullet Free.png` | 1280×400; `31254c691f165de81581c1bcdb5fd9ef2f6e0334851e6cb7420f9ed81d4251d7` | Player/enemy projectile frames |
| ASSET-05 | `images/Weapons/23.png` | 17×11; `4ea7b67a000792a6cacd32bbd2c7ae9d502717bc47102cefb3bb747540c45f65` | Alternate enemy-projectile marker |
| ASSET-05 | `images/Weapons/muzzle_flash.png` | 16×16; `dc3db951096c6bb2afe59ce1556a0a9f5acebb112903c3bb98ba83d8e21f27e1` | Muzzle flash |
| ASSET-06 | `images/Upgrades/fa1042.png` | 16×16; `d27c11a50f659cb7d2b568aa77ef207d805cd3ee0fe338c5ffcc43f664608298` | Health upgrade |
| ASSET-06 | `images/Upgrades/fa157.png` | 16×16; `834d750f5c5ac92513b7e43e93c048cee4bc7ec53e6991262f5bdf6fd5a8e9bc` | Damage upgrade |
| ASSET-06 | `images/Upgrades/fa1056.png` | 16×16; `617015201cf6f8171c0537c336fee95d972a74c4887f667e12b87436a6b8c2a8` | Speed upgrade |
| ASSET-07 | `fonts/Minecraft.ttf` | TrueType; `bd47314d301e50ff4d109bff28dfcf637cb7eb13945480259878b848875acc65` | Primary UI font |
| ASSET-08 | `images/7gc52d.png` | 600×434; `98eb55d149fc9e854c4c20a21284e47d9f1ddb24e3c001efe91d9c818f20a339` | Defeat-result background |

## 2. Audio

| Requirement | Relative path | SHA-256 | Use |
|---|---|---|---|
| ASSET-08 | `audio/lobby.mp3` | `16999c12c7c8ad0e6591d90398890f5e6e61d1e6b176fa5114b0e7348245eeae` | Menus |
| ASSET-08 | `audio/dungeon.mp3` | `d39843fb97bc53e2c33195651848ff54fc6a3356bca8207d469b556b8d9b5a5b` | Normal dungeon |
| ASSET-08 | `audio/boss.mp3` | `70e292c00e74a51fd8050594067e1941d5ed3f192f6da4e29c5bc69a78fc39e5` | Boss room |
| ASSET-08 | `audio/laser.mp3` | `2d9e3b72c4884c6c1e54deeaf0c56a41060ed4337468332d24c9015653a558e4` | Firing sound |
| ASSET-08 | `audio/silent-partner.mp3` | `47f612233ea8aeb1b7424e9fda8df9c2083d493b477794b6fe96b3a97cb5cf0f` | Victory result |
| ASSET-08 | `audio/somebody-that-i-used_to_know-trap-by-velvetcasca-extended-version.mp3` | `4fe625bed62e278fbf3c1cd35a5524c8216ff2ed86180af9e07d4abb7f9933e0` | Defeat-result music |

## 3. Runtime-generated bomb presentation

No dedicated bomb bitmap is distributed. The bomb body, visible fuse, and circular explosion are therefore runtime-drawn materials rather than substitutions from the weapon, enemy, upgrade, or tileset rows above. The explosion is 96 pixels across on the 1280×720 canvas (48-pixel radius), visually matches the gameplay collision area, and remains visually distinct from projectiles and muzzle flash. This mapping corresponds to `BOMB-01*`, `UI-03i`, `UI-04w`–`04x`, and `ASSET-09a`–`09b`.

Level 6 retains the existing mappings: its two normal slimes and elite slime use `images/Enemies/slime.png`; the final Spire Golem uses the mapped Golem sheets; rooms use the floor/wall tilesets; its first three rooms use `audio/dungeon.mp3`, and its boss room uses `audio/boss.mp3`. These identities must not be interchanged.

## 4. Projectile presentation mapping

`images/Weapons/16x16 Pixel Shade Bullet Free.png` supplies frames for player, slime, boss, and any boss-summoned-minion projectiles. `images/Weapons/23.png` may instead be used as the enemy-projectile marker. Player projectiles must remain visually distinct from enemy projectiles as required by `UI-05c`; the player weapon and muzzle flash orient with the persistent shooting direction established by the last nonzero WASD movement input, including after movement stops, while the left mouse button supplies the firing trigger. The gameplay values remain solely normative in `GDD-en.md`: normal-slime bullets deal 1 damage (`RULE-06d`), elite-slime bullets deal 2 damage (`RULE-06j`), and every bullet fired by the boss or its summoned minions deals 3 damage (`RULE-11ac`). Lesser and elite golems retain their mapped contact-attack presentation; this mapping does not require them to acquire a new projectile attack.

## 5. Processing freedom (Non-Normative)

Implementers may crop frames, disable interpolation, scale proportionally, flip horizontally, animate, change volume, and fade audio. This section explains common processing and creates no new “must,” “must not,” or hidden deduction. Slime distinction, icon/weapon/music semantics, and defeat-background use are judged only by the corresponding atomic IDs in `GDD-en.md` 6.6.

`.import`, Godot cache, and reference scenes are not source assets. Unmapped `fa1055.png`, `fa272.png`, and the test checkerboard are non-task files; nonconformance is determined only by `GDD-en.md` 6.6, not by this table.
