# Supplied Asset Catalog

Catalog revision: `v2.6-docv2-session-gate-20260912`

Only the files under `Assets/UndercookedStarter/**` are supplied task content. Paths, bytes, and SHA-256 values below are the machine-readable inventory in `ASSET_CATALOG.json`.

## Roles
- **Characters:** Chef model, head, animation clips and animator assets.
- **Ingredients:** Tomato raw/chopped models and food textures; onion models are included source material but tomato soup is the only task recipe.
- **Stations:** Crate, countertop, chopping board, pot, hob, plate, delivery, trash and supporting appliance assets.
- **Environment:** Floor, wall, materials, shaders and textures.
- **Audio:** Ambience, interaction, cooking, success and warning clips.
- **Input:** `Assets/InputSystem/UndercookedBenchmark.inputactions`.

## Import notes

- `Chef.fbx` supplies the rigged body and hat; `Chef_Model_Head.fbx` is the separately supplied head model. Both are shown as distinct source assets, not a required assembled pose.
- One dangling material remap in the supplied delivery-counter FBX importer was repaired to point to the already-supplied `Materials/Appliances/DeliverCounterTopMat.mat`. The FBX mesh and source material bytes are unchanged.
- Thumbnail scales are normalized independently. Model rendering dimensions and transparent texture margins are not collision or interaction dimensions.

## Boundary
Use supplied content for the primary presentation. Do not copy `Assets/3rdParty/Lean/**`, upstream gameplay code/scenes, Asset Store media, or files outside the published writable/protected boundary.

## Import facts and preview interpretation

`ASSET_CATALOG.json` records every supplied file's bytes/SHA-256, importer GUID and metadata hash, available image dimensions/alpha content bounds, importer scale/PPU/sprite settings, and actual isolated FBX render bounds for the principal models. These are asset facts rather than gameplay dimensions. The model uses its own gameplay collision/interaction rules and reports their truthful spatial description through the public session service.

No original gameplay Prefab is included, so there is no hidden gameplay script or missing-gameplay-script repair to recover from a supplied Prefab. Chef body and head remain separate source models. Supplied animation clips, animator controllers, audio events, shader graphs and texture layers can be inspected directly in the catalog paths.

## Inventory
Total non-meta supplied files: **150**.

| Path | Role | Bytes | SHA-256 |
|---|---|---:|---|
| `Assets/UndercookedStarter/Art/Animations/BodyExceptHandsAvatarMask.mask` | animation | 591 | `2c4308a6e6961163ec102b71c06c086c013a654cf43155efebe8ba58dca01fb4` |
| `Assets/UndercookedStarter/Art/Animations/Chef@Chop.fbx` | animation | 186880 | `7a230bbdb32064bfc16abd344d4cb91108cc01870a47bb381b3620be58e0a68f` |
| `Assets/UndercookedStarter/Art/Animations/Chef@Idle.fbx` | animation | 198896 | `eb588138b38fb9735233d123b0fa4b1ba9e1a3d1b0e04230db6b5650f299a80f` |
| `Assets/UndercookedStarter/Art/Animations/Chef@Pick.fbx` | animation | 205536 | `c124fc538c239c463ac3f756883a8bba65bdd9902afae0141b5e130ec1ed86f7` |
| `Assets/UndercookedStarter/Art/Animations/Chef@Release.fbx` | animation | 205552 | `a9065da01ba97c622dd0ac4f857fb042847297238253ceee7f196aeedee0c93b` |
| `Assets/UndercookedStarter/Art/Animations/Chef@Walk.fbx` | animation | 218144 | `c2554f1143bd20aded7d40a6f296dab5576660b77731c136e84c9e2301869267` |
| `Assets/UndercookedStarter/Art/Animations/Chef@Wash.fbx` | animation | 186864 | `333c856564fdf9f88e35e7a0178e0aa2bb9fc79e21d692d5e410aca605978afd` |
| `Assets/UndercookedStarter/Art/Animations/HandsAvatarMask.mask` | animation | 581 | `752aa67dfca34abdb179dca1aa3f977421fcd218dc0979d16b4a526de07f0598` |
| `Assets/UndercookedStarter/Art/Animators/ChefAnimController.controller` | animator | 28849 | `92db8d048dd4c6db2db90d94a8efc2431acf14b9167b5fc61e0f99f8e65f9fa1` |
| `Assets/UndercookedStarter/Art/Animators/IngredientCrateAnimController.controller` | animator | 4925 | `797b701cb883a39c17799a38c0417bb8aad7a73c7ad57cd4dac935a4241c2b45` |
| `Assets/UndercookedStarter/Art/FBX/Chef.fbx` | model | 156688 | `6a61805043d573dfffd00cf34706f7df35b4741c9da338dd5ead18a3b04db6ed` |
| `Assets/UndercookedStarter/Art/FBX/Chef_Model_Head.fbx` | model | 64000 | `b73a1591c21a8c2968f48650aaad713581234180a76838dd7d234e1ff8e18ea6` |
| `Assets/UndercookedStarter/Art/FBX/ChoppingBoard.fbx` | model | 27360 | `e9372fdd6506f33408fdae4cdccd3b819f5a7c8e3b5c773b622b1a52c05a215d` |
| `Assets/UndercookedStarter/Art/FBX/CookingPot.fbx` | model | 43408 | `5d16e562ad003d7e52712ac9f54d84ed54ede5298612607d3a568ac4840e395f` |
| `Assets/UndercookedStarter/Art/FBX/Countertop.fbx` | model | 32160 | `e7682f4f2d4d87a282bfb75022c3bd68fb2ae309c84008e618544ee6ad6d9f1d` |
| `Assets/UndercookedStarter/Art/FBX/DeliverCountertop.fbx` | model | 35536 | `bac2f4899550a96cd15e4d2ab5ff8714f987160afbcb6906c8575788b93a6375` |
| `Assets/UndercookedStarter/Art/FBX/DustParticle.fbx` | model | 39248 | `8c5fe8be0b0d87f06cc76bf1a39a93f8e17830518b7ddcb32e2239ce96679ff6` |
| `Assets/UndercookedStarter/Art/FBX/Extinguisher.fbx` | model | 33216 | `c5cce8d90a3e177e7fb5175c04bd2c882434d50db6cf94ec9910b0d46a5f5219` |
| `Assets/UndercookedStarter/Art/FBX/Floor30x30.fbx` | model | 39184 | `d9f5fe080817425375fbdd6566491914009a6d7046569e7ae24992b3bf4fa1db` |
| `Assets/UndercookedStarter/Art/FBX/Hob.fbx` | model | 94128 | `ba2025a18681301f351b6a6a174036727de3b708cb9cc9356edfdd27fe5d0a73` |
| `Assets/UndercookedStarter/Art/FBX/IngredientCrate.fbx` | model | 45312 | `ac72ca3f6760ccf188e1299f1c0ef007fe674f7fc107265a81799cda35c8111b` |
| `Assets/UndercookedStarter/Art/FBX/IngreditentCrate@Open.fbx` | model | 22256 | `ab8505472d34b5c933efa6a35d4aead2917e5ef084b28cd89ce51f0860903d2b` |
| `Assets/UndercookedStarter/Art/FBX/Knife.fbx` | model | 33744 | `657ae3b5fbbf92b3a138766a5c23d46f100a3597573f36c40bda8f60cd040616` |
| `Assets/UndercookedStarter/Art/FBX/Onion_Chopped.fbx` | model | 47136 | `800f73f2f45f7c1c3dd3191c1321b64e568a5a234151d5317dbde962777f36f4` |
| `Assets/UndercookedStarter/Art/FBX/Onion_Raw.fbx` | model | 30432 | `59f08f50fce425c0c5d76dc001819d36369482db8cc137dbcd4ee24c01f7ac5a` |
| `Assets/UndercookedStarter/Art/FBX/Plate.fbx` | model | 34896 | `acff6918e60f2cc04a67fd210901d1991d7f163e5c01e47abbd87b719bd2221b` |
| `Assets/UndercookedStarter/Art/FBX/Sink.fbx` | model | 48736 | `ead20443fdc33fff560f68c9a0ff9b2f048a374bf4f2dc7a544816c1bd2d6574` |
| `Assets/UndercookedStarter/Art/FBX/Tomato_Chopped.fbx` | model | 29440 | `ba8badb0fab0339ca846a5d70811400f62993287fb3b5c94117c863d165f196c` |
| `Assets/UndercookedStarter/Art/FBX/Tomato_Raw.fbx` | model | 42384 | `b517a94a56d1b05c29b164367e5356ee5f424ab5c2e833745ad4df450e7d3802` |
| `Assets/UndercookedStarter/Art/FBX/Trash.fbx` | model | 47520 | `fd9651ce3578eb4c639c8fbcbabda2180539c38b9f8af459626ecb53d1fd4112` |
| `Assets/UndercookedStarter/Art/FBX/Wall_100cm.fbx` | model | 26768 | `a85274b6f92aa12e0dd3b351cfdef8f63bed68f645bc23521d374b6f4503f81d` |
| `Assets/UndercookedStarter/Art/FBX/Wall_100cmWindow.fbx` | model | 28016 | `06451c7c97bf403708ad99e7b45af8b94137123d6ba8517bf1faa100fd02a189` |
| `Assets/UndercookedStarter/Art/FBX/Wall_60cm.fbx` | model | 26976 | `03af36639abc5a765b5b2ce2b5b23ebe19b730033580f05eb19fe8e9c9b598ba` |
| `Assets/UndercookedStarter/Art/Textures/CharacterSelector.psd` | texture | 946113 | `a5ae575773e70298ede37f2657777226f87a0f28e18c3f2d3dba5ab852b003d3` |
| `Assets/UndercookedStarter/Art/Textures/Chef_Model_HeadTexture.psd` | texture | 2430240 | `4baed5f93b3681483bbd689a79e35773a9ea13bacf7b2e34d0016a97543ab7cb` |
| `Assets/UndercookedStarter/Art/Textures/Chef_Texture.psd` | texture | 5862265 | `6cbfe6d912c9968d96188a48dfa235890da1904d415900ffbdc7c4a3e7c59522` |
| `Assets/UndercookedStarter/Art/Textures/ChoppingBoardTexture.png` | texture | 194182 | `8d98c78df1976611750445e1e9ec72c4c5ed8fd2952052cd896256ed51a19333` |
| `Assets/UndercookedStarter/Art/Textures/CountertopTexturing.png` | texture | 6879 | `976043a05f8040d99c64fa83a656244c63e94df345f91a012c1ce309c9ddf67d` |
| `Assets/UndercookedStarter/Art/Textures/DarkMetalTexture.psd` | texture | 148560 | `a726f00329c657536b1ea9dc182ec15581f0304d614d3354fba6c4b531bc79bd` |
| `Assets/UndercookedStarter/Art/Textures/DeliverCounteropTexture.psd` | texture | 193692 | `6b4f3b949535e570b438872383818f43aa6b38c6d7a2348f834725e121dab3c0` |
| `Assets/UndercookedStarter/Art/Textures/DishTray_Texture.png` | texture | 6857 | `9cfa18a9f823d30c06f076469afa64ee566e7877500f524e7984caff08f49541` |
| `Assets/UndercookedStarter/Art/Textures/ExtinguisherTexture.psd` | texture | 1596944 | `3099177cfd53effa62dfde1f0060a7bba580c8cf4d625e580795e8a9b5967c57` |
| `Assets/UndercookedStarter/Art/Textures/Flames1Texture.png` | texture | 231922 | `15327930980134eda1bcc003ac67787eade66db23aecc858e31b5999abcc335b` |
| `Assets/UndercookedStarter/Art/Textures/FloorTile1.png` | texture | 9463 | `4b00c8ec47e3fd27a066d2693d29f5c1726756c4363c758dc387d5af30609c3d` |
| `Assets/UndercookedStarter/Art/Textures/FloorTile2.png` | texture | 9606 | `d3aeb110473970d6b87697844bd0e4eb0bd6beead7afee281c0e26c7d8bde57d` |
| `Assets/UndercookedStarter/Art/Textures/HobTexture.png` | texture | 2555 | `1436b097be90acc518f7e059784d4bb2e446b657d01a4a2f4a367f783d9f492f` |
| `Assets/UndercookedStarter/Art/Textures/IngredientCrate_Texture.png` | texture | 1193408 | `2c42f5a1e55341bfbb31739081ea351f6d53a6e8138ef52a9d80d6ec365792c4` |
| `Assets/UndercookedStarter/Art/Textures/KnifeTexture.png` | texture | 199862 | `135177ad9833cc26cfa68b514b0b1200740571dba7e99d763004d3cfdbc298b4` |
| `Assets/UndercookedStarter/Art/Textures/OnionTexture.png` | texture | 122538 | `b3ad4c690644a1e9c3694f360efba7be04a147824544110be21406512544d426` |
| `Assets/UndercookedStarter/Art/Textures/PlateCleanTexture.psd` | texture | 539894 | `a988b3c714c8161d42576d3695d0a33d96eb297eecf166302fea31b4babe967e` |
| `Assets/UndercookedStarter/Art/Textures/PlateDirtyTexture.psd` | texture | 4373543 | `6fb5aa1dc8b09031cf28fb2256824a59485a808ea7e2659f84bcd55360f9fe66` |
| `Assets/UndercookedStarter/Art/Textures/SinkTexture.psd` | texture | 696675 | `096e16b62f68d0fa01c9b92d97a993e4459388ebef26e26f7649910b6b4be3c0` |
| `Assets/UndercookedStarter/Art/Textures/Star.png` | texture | 14535 | `44083eb3ef620bdabe1d6dedc2322e552154c8e3c3d311360b3fca3ff5281b39` |
| `Assets/UndercookedStarter/Art/Textures/StarBackground.png` | texture | 22187 | `e25be79c3566c0cc345777b1fea5a2fc7d24f31e19400d1fe854078be8a5ec62` |
| `Assets/UndercookedStarter/Art/Textures/StarGlowParticle.psd` | texture | 1466372 | `adb6eb2498447d8c9c8b439f47f7e1599e8df4902848baa7613fce02c4bd53dd` |
| `Assets/UndercookedStarter/Art/Textures/StarParticle.psd` | texture | 101502 | `b7fdd8d2eeee3299f99c9f30ff5c812e54e096e7477a77e8d15a10e5fa489b24` |
| `Assets/UndercookedStarter/Art/Textures/SteamTexture.psd` | texture | 996202 | `15b42170d9df4766b6676f7045c675a74aa3a2e2a27cb7794d03641bfe012ce2` |
| `Assets/UndercookedStarter/Art/Textures/TomatoTexture.png` | texture | 16987 | `1cbbc1b8b4a4b60ec20c63a1534d2e1d550125df9fc6200c56b8cc093357b83a` |
| `Assets/UndercookedStarter/Art/Textures/TrashTexture.psd` | texture | 1109578 | `ccca78b6eb5db83460ed19daea39014b850b89bdf12b5cb2ece311938f5c6a97` |
| `Assets/UndercookedStarter/Art/Textures/WallTexture.psd` | texture | 841417 | `ce0b715ff40e76e98f87ceed1d839780b3e60e82534b7a632d08ce587c5e2474` |
| `Assets/UndercookedStarter/Art/UI/CrateDecals/CrateDecalBun.png` | ui texture | 25169 | `145f05fe65e79b274dbea962e77340742f9909296a071b4aeeaa11c8bba16f30` |
| `Assets/UndercookedStarter/Art/UI/CrateDecals/CrateDecalLettuce.png` | ui texture | 25425 | `9eee2bef7c9be17f11ecdf9ce7c27eb292641d7bfe446529ecfb2a7a8b3034ab` |
| `Assets/UndercookedStarter/Art/UI/CrateDecals/CrateDecalMeat.png` | ui texture | 20283 | `49c52c310c16506d8b51d08f49efafb66536a4dd702dda036fddcabc963cfd34` |
| `Assets/UndercookedStarter/Art/UI/CrateDecals/CrateDecalOnion.png` | ui texture | 21912 | `faae507cbe7530de1a564a50222d463fd9193983b7a3b00cfabda40f695fd6d2` |
| `Assets/UndercookedStarter/Art/UI/CrateDecals/CrateDecalTomato.png` | ui texture | 25858 | `6b465bad9c423b1f4bde0e59980fa93f01364f16a61e0074346ef0f7ed27e067` |
| `Assets/UndercookedStarter/Art/UI/UndercookedIcons1.png` | ui texture | 345165 | `74090c28716a9d5ea6830e564113fec1b75f5780264cc0d3d481f17221644c0c` |
| `Assets/UndercookedStarter/Art/UI/WhitePixel.png` | ui texture | 782 | `ae7ec23805634f454dc08f4e924c79f9eb649205243f872e1e4fa14e0ffd3c2f` |
| `Assets/UndercookedStarter/Audio/backgroundTalkmp3.mp3` | audio | 595541 | `2b77ca1b6ab7af3a3c67c5a6c6b1de3bdc54a70a84d703d4717d404aeedc01e3` |
| `Assets/UndercookedStarter/Audio/buzzer_1_lower.mp3` | audio | 17009 | `f66210bf9b990bf7f6c8fc5b2ced81a9653a8b0e9233db77ecc6cc53c4bd8491` |
| `Assets/UndercookedStarter/Audio/chopHit1.mp3` | audio | 13248 | `63a4f2a37c7d3cf31f1cffc2b565c28445c801d799e1f4c490eb41ad619b29ce` |
| `Assets/UndercookedStarter/Audio/chopHit2.mp3` | audio | 14832 | `504ebb1ddc9f402c2991ab5c640a0d4cc8b639cc46e63b40bd32dc0621c8f721` |
| `Assets/UndercookedStarter/Audio/chopHit3.mp3` | audio | 36624 | `648191ff61aeb5b0103a312db1da23d4f05db33530e3cef263b908892f6406ef` |
| `Assets/UndercookedStarter/Audio/chopHit4.mp3` | audio | 17664 | `a50fda204490ddfb9566912508146d1c7905a8c2dedc5d4a8f1165eeb55de517` |
| `Assets/UndercookedStarter/Audio/fireFlames.mp3` | audio | 187968 | `e36e467923fae8ca43d38cd30209ca774223447843639cf4ed6db6e7f7e68e9f` |
| `Assets/UndercookedStarter/Audio/fireWosh.mp3` | audio | 11377 | `6368577f39d06ef45942ceaf8b5e4e31a63204ab6280137c8146f401cee5d7d3` |
| `Assets/UndercookedStarter/Audio/guitarChord.mp3` | audio | 70237 | `38b8222224d81e65b06ff80dbb8c95a19dc48fdfb4c18ec8f2a6a6aeb42bbc87` |
| `Assets/UndercookedStarter/Audio/ItemDrop.mp3` | audio | 6159 | `13afa69018029dab86f077319ef35a6c511226eae93a14c9f091bcf68d9b3838` |
| `Assets/UndercookedStarter/Audio/ItemPick.mp3` | audio | 5845 | `0abe641ab61d80018a0b150146efc3cc1928e3c887a0d9b0a65a76e00dcda836` |
| `Assets/UndercookedStarter/Audio/menuNote1.mp3` | audio | 44817 | `3eec9fcb4902ddc62f0efb9df261434068711f62ae3f42ac0a3cd55a86f565f3` |
| `Assets/UndercookedStarter/Audio/menuNote2.mp3` | audio | 41713 | `59b98c6d3d9a0e1a9d6fdbf04328df3e16dd0ad8f8c735e06617c44260fb99ad` |
| `Assets/UndercookedStarter/Audio/menuNote3.mp3` | audio | 43303 | `c6a6ad855aa5e1e47f662dfd9c1dfb7bb8291305c4077fef5ad0765c7ecb0a93` |
| `Assets/UndercookedStarter/Audio/menuSelection.mp3` | audio | 7411 | `175ce8237a7c88c25709a835f41be3d053677360896f40b2534b7fda565b0481` |
| `Assets/UndercookedStarter/Audio/notification-01.wav` | audio | 121348 | `d668591851a3589e9a8e27308b4b341d2ef01b20917a965babd6ce6abc12c727` |
| `Assets/UndercookedStarter/Audio/notification-02.wav` | audio | 247340 | `6d430b17dbdf6c4e5f47ad6e3d9e03c6d0ae8a9bcd9ca03c0102a1452ff3b8d2` |
| `Assets/UndercookedStarter/Audio/pop01.mp3` | audio | 3168 | `9b63cb7a70876aaf34968ad5a860e8cb2d1ad8c438d7d92ac6c9bf10d4cbb934` |
| `Assets/UndercookedStarter/Audio/pop02.mp3` | audio | 2784 | `becdcd746bae0990b5c44a8da6558d355baf016aa11816265b83e5ad8158a563` |
| `Assets/UndercookedStarter/Audio/pop03.mp3` | audio | 3840 | `7e28397bfc751f07e5607c143e1e528c2a80b5321d35906f7fe3bbec023c83eb` |
| `Assets/UndercookedStarter/Audio/pop04.mp3` | audio | 3888 | `3a5ddf436ba59b6a64b8c8fa523cdee2ee1d341779c125edef90f5be076f8b60` |
| `Assets/UndercookedStarter/Audio/restaurant-kitchen-ambience_01.mp3` | audio | 1060896 | `a04df82d8e265e9a309d9289c8a1c6b6b241afa992231e8bdd16993024e0e5c3` |
| `Assets/UndercookedStarter/Audio/restaurant-kitchen-ambience_NoiseReducted.mp3` | audio | 1079616 | `86004d69c9fccdbae4e443447fa1cb8135250f9ff2274d1de051fc88c7782b87` |
| `Assets/UndercookedStarter/Audio/success-03.wav` | audio | 247340 | `51aadc7b6e4534d7709d72f5f53c272508e9b6a62fea8db965571881e4995c40` |
| `Assets/UndercookedStarter/Audio/success-04.wav` | audio | 354920 | `e028ab43287388211bce0a4780d629e4ebacf19cd3b1231f188be6adc9d9b351` |
| `Assets/UndercookedStarter/Audio/success.wav` | audio | 163026 | `0661b7b6f30b4d1b2b567533741f985b35050753c15c2e4dfa583125fda52616` |
| `Assets/UndercookedStarter/Audio/warnBurnBeep.mp3` | audio | 4071 | `4e764af1d872d52598125d8ed4fd0c2de6748cd486ba3771e1bc75796a0cf92f` |
| `Assets/UndercookedStarter/Audio/warnBurnCountdown.mp3` | audio | 212699 | `bcb3bec0aa83e0cbb53cf93727aa159bdd8038630762a358b2e50c5b6c39ff8e` |
| `Assets/UndercookedStarter/Audio/wosh.mp3` | audio | 8324 | `1d7a208bfa8578558991713dad979e0a0f2f7309dbfe7a08952be47f79879b58` |
| `Assets/UndercookedStarter/Materials/Appliances/ChoppingBoardMat.mat` | material | 3513 | `2f274ca39fccf6b09a4b257e58e70ee6ea80a0283737f8318a4fd94b0bb90264` |
| `Assets/UndercookedStarter/Materials/Appliances/CookingPotMat.mat` | material | 3510 | `acf1995e19b4afd6906a05a4cb725ace9e882d3d4d88af71acc5e35f7b99f138` |
| `Assets/UndercookedStarter/Materials/Appliances/CountertopMat.mat` | material | 3551 | `18bca81afd34df1b8e5efae8559a6de3573a94a089762e341abc89421497db76` |
| `Assets/UndercookedStarter/Materials/Appliances/CrateDecalBunMat.mat` | material | 4156 | `b99a84ca9d89a506950c66b7b3a848a99d89a04eb0b1bc931450b98b64ce0f82` |
| `Assets/UndercookedStarter/Materials/Appliances/CrateDecalLettuceMat.mat` | material | 4160 | `9e7f96875713c31dd3f62f813a701ba06bfb3e8da11879744c7a42491c9276fd` |
| `Assets/UndercookedStarter/Materials/Appliances/CrateDecalMeatMat.mat` | material | 4157 | `4831c181e416f8ddda642c27cdfee8320e5f2bffaa7f81d213fb3159726f98b0` |
| `Assets/UndercookedStarter/Materials/Appliances/CrateDecalOnionMat.mat` | material | 4192 | `c5f3c2bf6f027be56295f44f7124a889a4473e9c79574a614853e831e968e8c9` |
| `Assets/UndercookedStarter/Materials/Appliances/CrateDecalTomatoMat.mat` | material | 4193 | `71e9498f70bf53d734e247587f0eefb41fcc013b9ceb0b1442c661fa993ab0ec` |
| `Assets/UndercookedStarter/Materials/Appliances/DeliverCounterTopMat.mat` | material | 1904 | `d83dac4b96c5ff4156e66c346f949413efaf850f0af7673c7c5ceb3a2c9add94` |
| `Assets/UndercookedStarter/Materials/Appliances/DishTrayMat.mat` | material | 3532 | `5a435474e511bfe578b369db210bbfe5fc6d2d5edd9329b74bc438502c204cd3` |
| `Assets/UndercookedStarter/Materials/Appliances/ExtinguisherMat.mat` | material | 3513 | `e1e7075182db37635b9f828b88ad7bff78ce76dafc62bef91ed1d4f90a322e66` |
| `Assets/UndercookedStarter/Materials/Appliances/HobFlameMat.mat` | material | 3549 | `b95a2dee21d6ad5272d8666bf7ab37a11d44d3613eca9ca24701dcbc9dea7ca3` |
| `Assets/UndercookedStarter/Materials/Appliances/HobMat.mat` | material | 3544 | `f6ecd9a10c65c5b826fe1121c21e6aa1e5a39619bfad674cd5cc0af322402990` |
| `Assets/UndercookedStarter/Materials/Appliances/IngredientCrate_highlightable.mat` | material | 3527 | `63544af5cd4b185459e1ac795edcea1ecd57c1dd3c5fbc4f8e1069996e093359` |
| `Assets/UndercookedStarter/Materials/Appliances/KnifeMat.mat` | material | 3505 | `c3bc120d6e9ec867b6b85b8d7d96ee195415417b490377e0eeef74ebc690b004` |
| `Assets/UndercookedStarter/Materials/Appliances/LiquidCookMat.mat` | material | 4019 | `6a97d58252f845beb36b09bf977dff09fe096b564ca1600eb6427872ed40f9bc` |
| `Assets/UndercookedStarter/Materials/Appliances/MetalMat.mat` | material | 3546 | `4dc6dac3f1662663c7e431d5d04efa6a93dc864457b0aaffafa7757aa5a6ec0c` |
| `Assets/UndercookedStarter/Materials/Appliances/PlateCleanMat.mat` | material | 3511 | `3507076b4d3391e5b6b6d594e7cba83fa0da520758b556072310888b5d33a504` |
| `Assets/UndercookedStarter/Materials/Appliances/PlateDirtyMat.mat` | material | 3511 | `dd20520701243e0a528195d86fcf6e55835fa36ab10a6c211f2c4ab11c979c32` |
| `Assets/UndercookedStarter/Materials/Appliances/SinkMat.mat` | material | 3505 | `6343b2a667bc23d5a93d2df15b4db3a984c8a649c4c65444e36e28d933be9ead` |
| `Assets/UndercookedStarter/Materials/Appliances/TrashMat.mat` | material | 3506 | `efdec8668bcef1d62e5e4449f5b26aa81c568489d3a79c809d91d5d00a2af56e` |
| `Assets/UndercookedStarter/Materials/FlamesMat.mat` | material | 3917 | `c024b31f1fbb20f9131276f9028713235b2f2bc3ce42617fdc73544fc379dd80` |
| `Assets/UndercookedStarter/Materials/FloorTile1.mat` | material | 4092 | `f349e60b7ade9438b7113f916f943417592e23aabe0b4a583ee4e1379aa15108` |
| `Assets/UndercookedStarter/Materials/FloorTile2.mat` | material | 3948 | `5b7dfb6ec7fa72362b92e5d5990c8cc9ad15c327f82622d830a95cc5ca7c037b` |
| `Assets/UndercookedStarter/Materials/FrictionlessPhysicMaterial.physicMaterial` | material | 353 | `15101fd0b6aff54615ee29eb922002600b1484e38eab9c17e3d7040dbfc29c19` |
| `Assets/UndercookedStarter/Materials/HighFrictionPhysicMaterial.physicMaterial` | material | 359 | `43baf5b0e4c16cfa8ad785864b9471ddcef298823e9ec0cfce5beec5acacb4bc` |
| `Assets/UndercookedStarter/Materials/Ingredients/OnionMat.mat` | material | 3505 | `73261daebd775a5aa639453b24f5212ce3f098a69f58457c5edff78bc7f31b74` |
| `Assets/UndercookedStarter/Materials/Ingredients/TomatoMat.mat` | material | 3506 | `1ac0b5f150c40e33f669ab638b7dc61d3f70b224fe584aebbc0b280b2048a96f` |
| `Assets/UndercookedStarter/Materials/Player/CharacterSelectorMat.mat` | material | 4459 | `6ccc977518c0f50c8f26d471d7372a2334a418d5545b2fe9bfd1e87da4772f60` |
| `Assets/UndercookedStarter/Materials/Player/ChefBaseMat.mat` | material | 3957 | `c837efa3c460119897c710c1c15ea7be3a8a1a9cbb7af8c40dbf48d3e1f7a6a6` |
| `Assets/UndercookedStarter/Materials/Player/ChefHeadMat.mat` | material | 3957 | `c06dda2e01c0d5390f159900f5eccf8579add06366a8b08dd1e8b8cd76e2e463` |
| `Assets/UndercookedStarter/Materials/Player/DustParticleMat.mat` | material | 4043 | `529dfd039530e6707a4d7ca76f511bd61da45d4470c28528f4c6821fcc535bcd` |
| `Assets/UndercookedStarter/Materials/Player/PlayerUniqueColorMat.mat` | material | 3911 | `5fd070255f7853e89e9fd75060db8d39a3d8fda7d50ba8eb64c42a16a45e043f` |
| `Assets/UndercookedStarter/Materials/Skybox_Mat.mat` | material | 2564 | `4fcf3a3841445f2982ec79ac791190363397fc3c97429aebff7fdcf9fc0dbd74` |
| `Assets/UndercookedStarter/Materials/StarGlowParticleMat.mat` | material | 4721 | `9a45551a5cf05d5f5aec2fe04f920d8ebe66c1a6fd1a733451737b339892a486` |
| `Assets/UndercookedStarter/Materials/StarParticleMat.mat` | material | 3165 | `2aae5b5ae1be5e4a04443ffdb9e02f36a183fb8e9c15b4a45e77b302942caa31` |
| `Assets/UndercookedStarter/Materials/SteamMat.mat` | material | 3745 | `4776619ded589d2d3e002702c01f458fd8e11cfc4c19760cee3c56fea4de334f` |
| `Assets/UndercookedStarter/Materials/UI_Mat.mat` | material | 3301 | `4ae0d640ee548962b7b5ae600c7af79c017bd6ffdb7778543b533803781b84ea` |
| `Assets/UndercookedStarter/Materials/WallMat.mat` | material | 4382 | `f27c5f761e3638fa7fa08e7a1fa79a36566fa4b8f3f95cce8071803f864597f4` |
| `Assets/UndercookedStarter/Scenes/KitchenStarter.unity` | starter scene | 60534 | `5f433ebed1109b2c8548d3eae90cc998831ae10fec18ec4ef7182a9d3d4e1934` |
| `Assets/UndercookedStarter/Settings/ForwardRenderer.asset` | scene settings | 1893 | `7638fa9dec60da784639a6e98f630ed939ee7d24a66301a6f48c2645728e4703` |
| `Assets/UndercookedStarter/Settings/InputSystem.inputsettings.asset` | scene settings | 762 | `0fe1f48d7a2c8ae5856d467bcc7b8d9d6b23bd67ca793ccc79bba47302b62da6` |
| `Assets/UndercookedStarter/Settings/UniversalRP-HighQuality.asset` | scene settings | 4554 | `ec156068f99f8d2cd8972ee488666c58870892a1ba0787991c27033ae404c41c` |
| `Assets/UndercookedStarter/Settings/UniversalRP-LowQuality.asset` | scene settings | 4553 | `c8cd87f8d58888da27c651d580d71bdb8dce98a9810e6ba04c982ecda85ce6b0` |
| `Assets/UndercookedStarter/Settings/UniversalRP-MediumQuality.asset` | scene settings | 4556 | `6f229abd29f33e4287abe116e6d00e6f45a5e15d10e2ce358e92537e898dd852` |
| `Assets/UndercookedStarter/Shaders/Flames.shadergraph` | shader | 110220 | `2d5e24bf3f7c9f7a4fe7045eed229282e69f529ad0994230801a01b66b6029ec` |
| `Assets/UndercookedStarter/Shaders/Highlight.shadergraph` | shader | 42924 | `e6d27bcc6fb8b8ba9c1f2e60d9b1ede4953f49e34a4395883be92f220eed7c12` |
| `Assets/UndercookedStarter/Shaders/HighlightFlame.shadergraph` | shader | 74921 | `51b0dce82026f7e7b37188bfb3b9a8e0b642840ba21cea1a53180875bcd578b6` |
| `Assets/UndercookedStarter/Shaders/ScrollingTexture.shadergraph` | shader | 36161 | `19fc4ef4aecb191f5c8e46cdd66482f73dfd17f089c2c9e99f2f7c7e0bf8f83c` |
| `Assets/UndercookedStarter/Shaders/Shader Graphs_Flames.mat` | shader | 2418 | `d1d2fb0226873ff2145ccc9d9b50698449dfba21792dc8361765ebc35f9332ea` |
| `Assets/UndercookedStarter/Shaders/Shader Graphs_Highlight.mat` | shader | 1948 | `7b6c2408e8c88a4daf462d47db49af4251a18abea09b8e288fc7b640b591de94` |
| `Assets/UndercookedStarter/Shaders/Shader Graphs_HighlightFlame.mat` | shader | 1774 | `744f6464d5a3d397c0c28903b020dff37f711f36bdaa7b3b17cf5f3d1e73f7d8` |
| `Assets/UndercookedStarter/Shaders/Shader Graphs_SwingFlames.mat` | shader | 2256 | `cd0841ffc513b24a9af899cf9d0ef7b57c5725362a908b234741610688c76dc9` |
| `Assets/UndercookedStarter/Shaders/SwingFlames.shadergraph` | shader | 169253 | `16522a0fd996bad27065f0fc0b0b6d12420a2b75989e2c0219f2111a9c6363cf` |
