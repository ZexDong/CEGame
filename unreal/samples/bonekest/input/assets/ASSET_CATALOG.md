# Exact presentation asset catalog

All files below are installed in starter-project/Content and load as native UE packages.
Required means the numbered GDD asset rule applies; dependency means that role needs
the package to load or render. Additional pieces support room/effect variety.
assets/ASSET_CATALOG.json records the supplied object paths, dependencies, hashes, sizes and
per-file license groups. Hashes and sizes describe the starting snapshot only.
Required entries retain their package/object paths in the final project; permitted
in-place edits may change their bytes and dependencies as defined in GDD Section 6.4.7.
Optional entries may be reorganized or removed if no required dependency is broken.
No assembled gameplay or level is supplied.

The role and replacement policy comes exclusively from GDD Section 6. The starter
does not automatically instantiate these assets. Materials and particle systems contain
presentation logic only; they do not implement damage, maze generation or victory.

| Native Content path | Type | Use | Requirement |
| --- | --- | --- | --- |
| Doors/SM_Ring.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| Effects/GhostEffect/FX_GhostSmoke.uasset | ParticleSystem | Cyan spectral flame/smoke | ASSET-05 |
| Effects/GhostEffect/MI_Pickups_Coin.uasset | MaterialInstanceConstant | Coin pickup colour material; Dependency of /Game/Pickups/Assets/SM_Coin | ASSET-03 |
| Effects/GhostEffect/MI_Pickups_KeyBlue.uasset | MaterialInstanceConstant | KeyBlue pickup colour material; Dependency of /Game/Pickups/Assets/SM_Key | ASSET-03 |
| Effects/GhostEffect/MI_Pickups_KeyGreen.uasset | MaterialInstanceConstant | KeyGreen pickup colour material | ASSET-03 |
| Effects/GhostEffect/MI_Pickups_KeyRed.uasset | MaterialInstanceConstant | KeyRed pickup colour material; Dependency of /Game/Pickups/Assets/SM_Heart | ASSET-03 |
| Effects/GhostEffect/MI_Pickups_Magic.uasset | MaterialInstanceConstant | Magic pickup colour material; Spectral monster encounter manifestation | ASSET-03, ASSET-05 |
| Effects/GhostEffect/M_Pickups.uasset | Material | Mandatory dependency for ASSET-03, ASSET-05 | ASSET-03, ASSET-05 |
| Effects/GhostEffect/Mat_FX.uasset | Material | Mandatory dependency for ASSET-05 | ASSET-05 |
| Effects/GhostEffect/SM_Particle_Smoke_01.uasset | StaticMesh | Mandatory dependency for ASSET-05 | ASSET-05 |
| Effects/MF_PSXEffect.uasset | MaterialFunction | Mandatory dependency for ASSET-01 | ASSET-01 |
| Effects/MPC_PSXEffect.uasset | MaterialParameterCollection | Mandatory dependency for ASSET-01 | ASSET-01 |
| Effects/M_PS1_PostProcess.uasset | Material | Mandatory dependency for ASSET-05 | ASSET-05 |
| Effects/M_PS1_PostProcess_Inst.uasset | MaterialInstanceConstant | World pixelation and retro postprocess | ASSET-05 |
| FXVarietyPack/Materials/MI_ky_aura011_4x4.uasset | MaterialInstanceConstant | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Materials/MI_ky_aura011_4x4_nonD.uasset | MaterialInstanceConstant | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Materials/MI_ky_auraWall02_two.uasset | MaterialInstanceConstant | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Materials/MI_ky_chantDecoAc.uasset | MaterialInstanceConstant | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Materials/MI_ky_circle9_4x4c2.uasset | MaterialInstanceConstant | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Materials/MI_ky_circleDust.uasset | MaterialInstanceConstant | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Materials/MI_ky_flare_flash_trs.uasset | MaterialInstanceConstant | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Materials/MI_ky_lightning02_4x4.uasset | MaterialInstanceConstant | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Materials/MI_ky_lightningDust01_4x4_nonD.uasset | MaterialInstanceConstant | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Materials/MI_ky_primitive_dynB_nonD.uasset | MaterialInstanceConstant | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Materials/MI_ky_shine01R_nonD.uasset | MaterialInstanceConstant | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Materials/MI_ky_starDust_dis.uasset | MaterialInstanceConstant | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Materials/MI_ky_storm01_nonD.uasset | MaterialInstanceConstant | Supplementary MaterialInstanceConstant presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| FXVarietyPack/Materials/MI_ky_turbulence_smoke2d_trs.uasset | MaterialInstanceConstant | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Materials/MI_ky_vortex04B_4x4_two.uasset | MaterialInstanceConstant | Supplementary MaterialInstanceConstant presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| FXVarietyPack/Materials/M_ky_Fresnel.uasset | Material | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Materials/M_ky_auraWall02.uasset | Material | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Materials/M_ky_base.uasset | Material | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Materials/M_ky_base_anime.uasset | Material | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Materials/M_ky_base_turbulence.uasset | Material | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Materials/M_ky_chantDecoA.uasset | Material | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Materials/M_ky_circle01_4x4G_nonD.uasset | Material | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Materials/M_ky_dust01_4x4.uasset | Material | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Materials/M_ky_empty.uasset | Material | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Materials/M_ky_flare01_primitive.uasset | Material | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Materials/M_ky_flare_flash.uasset | Material | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Materials/M_ky_magicCircle020.uasset | Material | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Materials/M_ky_primitive_dyn2.uasset | Material | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Materials/M_ky_starDust.uasset | Material | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Materials/M_ky_stone02.uasset | Material | Supplementary Material presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| FXVarietyPack/Materials/M_ky_storm01.uasset | Material | Supplementary Material presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| FXVarietyPack/Materials/M_ky_stormDeco01.uasset | Material | Supplementary Material presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| FXVarietyPack/Materials/M_ky_subUV01.uasset | Material | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Materials/M_ky_subUV_dynRGB.uasset | Material | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Materials/M_ky_vortex04_4x4.uasset | Material | Supplementary Material presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| FXVarietyPack/Materials/Mfunction/MF_ky_AddHilight.uasset | MaterialFunction | Supplementary MaterialFunction presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| FXVarietyPack/Materials/Mfunction/MF_ky_MaskToTopUnder.uasset | MaterialFunction | Supplementary MaterialFunction presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| FXVarietyPack/Materials/Mfunction/MF_ky_TexController.uasset | MaterialFunction | Supplementary MaterialFunction presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| FXVarietyPack/Materials/Mfunction/MF_ky_TexController_primitive.uasset | MaterialFunction | Supplementary MaterialFunction presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| FXVarietyPack/Materials/Mfunction/MF_ky_UVcontrol_4x4.uasset | MaterialFunction | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Materials/Mfunction/MF_ky_VectorToRadialValue.uasset | MaterialFunction | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Meshes/SM_ky_auraWall_distB_kai.uasset | StaticMesh | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Meshes/SM_ky_circleDist06.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| FXVarietyPack/Meshes/SM_ky_cylinderBend07.uasset | StaticMesh | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Meshes/SM_ky_cylinder_lowPoly_dist.uasset | StaticMesh | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Meshes/SM_ky_cylinder_superLow.uasset | StaticMesh | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Meshes/SM_ky_quad_centerRot.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| FXVarietyPack/Meshes/SM_ky_tornado07.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| FXVarietyPack/Particles/P_ky_healAura.uasset | ParticleSystem | Cast aura | ASSET-05 |
| FXVarietyPack/Particles/P_ky_lightning1.uasset | ParticleSystem | Impact/lightning | ASSET-05 |
| FXVarietyPack/Particles/P_ky_lightning2.uasset | ParticleSystem | Cast lightning | ASSET-05 |
| FXVarietyPack/Particles/P_ky_magicCircle1.uasset | ParticleSystem | Portal and spell ground ring | ASSET-05 |
| FXVarietyPack/Particles/P_ky_storm.uasset | ParticleSystem | Supplementary ParticleSystem presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| FXVarietyPack/Textures/T_ky_aura011_4x4.uasset | Texture2D | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Textures/T_ky_auraWallWhite_4x4.uasset | Texture2D | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Textures/T_ky_bg.uasset | Texture2D | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Textures/T_ky_bg_LC.uasset | Texture2D | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Textures/T_ky_chantDecoC.uasset | Texture2D | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Textures/T_ky_circle01_4x4.uasset | Texture2D | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Textures/T_ky_circle9_4x4.uasset | Texture2D | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Textures/T_ky_circleDust.uasset | Texture2D | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Textures/T_ky_dist_noise.uasset | Texture2D | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Textures/T_ky_dust01_4x4.uasset | Texture2D | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Textures/T_ky_dust_longStar.uasset | Texture2D | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Textures/T_ky_flareVertical02.uasset | Texture2D | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Textures/T_ky_flare_a.uasset | Texture2D | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Textures/T_ky_lightning02_4x4.uasset | Texture2D | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Textures/T_ky_lightningDust01_4x4.uasset | Texture2D | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Textures/T_ky_magicCircle020.uasset | Texture2D | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Textures/T_ky_maskCircle.uasset | Texture2D | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Textures/T_ky_maskRGB3.uasset | Texture2D | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Textures/T_ky_noise.uasset | Texture2D | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Textures/T_ky_noise13_sml_nor.uasset | Texture2D | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Textures/T_ky_noise17.uasset | Texture2D | Supplementary Texture2D presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| FXVarietyPack/Textures/T_ky_noise4.uasset | Texture2D | Supplementary Texture2D presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| FXVarietyPack/Textures/T_ky_noise5.uasset | Texture2D | Supplementary Texture2D presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| FXVarietyPack/Textures/T_ky_noise6.uasset | Texture2D | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Textures/T_ky_shine01_4x4.uasset | Texture2D | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Textures/T_ky_smoke03.uasset | Texture2D | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Textures/T_ky_smoke_kai.uasset | Texture2D | Mandatory dependency for ASSET-05 | ASSET-05 |
| FXVarietyPack/Textures/T_ky_stone02_2x2.uasset | Texture2D | Supplementary Texture2D presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| FXVarietyPack/Textures/T_ky_vortex04_4x4.uasset | Texture2D | Supplementary Texture2D presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| InfinityBladeAdversaries/Enemy/Enemy_Greater_Spider_Boss/Enemy_SpiderBoss_Cine_Animation/ExoGame_Greater_Spider_Cine_Finale.uasset | AnimSequence | Supplementary AnimSequence presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| InfinityBladeAdversaries/Enemy/Enemy_Greater_Spider_Boss/Materials/CharM_Greater_Spider_BossFire.uasset | Material | Supplementary Material presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| InfinityBladeAdversaries/Enemy/Enemy_Greater_Spider_Boss/SK_Greater_Spider_Boss_Cine.uasset | SkeletalMesh | Supplementary SkeletalMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| InfinityBladeAdversaries/Enemy/Enemy_Greater_Spider_Boss/SK_Greater_Spider_Boss_Cine_Skeleton.uasset | Skeleton | Supplementary Skeleton presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| InfinityBladeAdversaries/Enemy/Enemy_Greater_Spider_Boss/Textures/T_Enemy_SpiderBoss_E.uasset | Texture2D | Supplementary Texture2D presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| InfinityBladeAdversaries/Enemy/Enemy_Greater_Spider_Boss/Textures/T_Enemy_SpiderBoss_Fire_D.uasset | Texture2D | Supplementary Texture2D presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| InfinityBladeAdversaries/Enemy/Enemy_Greater_Spider_Boss/Textures/T_Enemy_SpiderBoss_Fire_M.uasset | Texture2D | Supplementary Texture2D presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| InfinityBladeAdversaries/Enemy/Enemy_Greater_Spider_Boss/Textures/T_Enemy_SpiderBoss_Fire_N.uasset | Texture2D | Supplementary Texture2D presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| Pickups/Assets/SM_Coin.uasset | StaticMesh | Coin pickup silhouette | ASSET-03 |
| Pickups/Assets/SM_Heart.uasset | StaticMesh | Heart pickup silhouette | ASSET-03 |
| Pickups/Assets/SM_Key.uasset | StaticMesh | Key pickup silhouette | ASSET-03 |
| PlayerCharacter/Animations/A_PlayerCharacter_Blast.uasset | AnimSequence | Mage escape flourish animation | ASSET-01 |
| PlayerCharacter/Animations/A_PlayerCharacter_Charge_Attack.uasset | AnimSequence | Supplementary AnimSequence presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| PlayerCharacter/Animations/A_PlayerCharacter_Default_Attack.uasset | AnimSequence | Mage cast animation | ASSET-01 |
| PlayerCharacter/Animations/A_PlayerCharacter_Die.uasset | AnimSequence | Mage death animation | ASSET-01 |
| PlayerCharacter/Animations/A_PlayerCharacter_Hit_Back.uasset | AnimSequence | Supplementary AnimSequence presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| PlayerCharacter/Animations/A_PlayerCharacter_Hit_Front.uasset | AnimSequence | Mage hit animation | ASSET-01 |
| PlayerCharacter/Animations/A_PlayerCharacter_Hit_Left.uasset | AnimSequence | Supplementary AnimSequence presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| PlayerCharacter/Animations/A_PlayerCharacter_Hit_Right.uasset | AnimSequence | Supplementary AnimSequence presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| PlayerCharacter/Animations/A_PlayerCharacter_Idle_Loop.uasset | AnimSequence | Mage idle animation | ASSET-01 |
| PlayerCharacter/Animations/A_PlayerCharacter_Jump.uasset | AnimSequence | Supplementary AnimSequence presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| PlayerCharacter/Animations/A_PlayerCharacter_Rapid_Fire_Loop.uasset | AnimSequence | Supplementary AnimSequence presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| PlayerCharacter/Animations/A_PlayerCharacter_Roar.uasset | AnimSequence | Supplementary AnimSequence presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| PlayerCharacter/Animations/A_PlayerCharacter_Run_Loop.uasset | AnimSequence | Mage movement animation | ASSET-01 |
| PlayerCharacter/Animations/A_PlayerCharacter_Shuffle_Left_Loop.uasset | AnimSequence | Supplementary AnimSequence presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| PlayerCharacter/Animations/A_PlayerCharacter_Shuffle_Right_Loop.uasset | AnimSequence | Supplementary AnimSequence presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| PlayerCharacter/Animations/A_PlayerCharacter_Spawn.uasset | AnimSequence | Mage spawn animation | ASSET-01 |
| PlayerCharacter/Animations/A_PlayerCharacter_Strafe_Left_Loop.uasset | AnimSequence | Supplementary AnimSequence presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| PlayerCharacter/Animations/A_PlayerCharacter_Strafe_Right_Loop.uasset | AnimSequence | Supplementary AnimSequence presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| PlayerCharacter/Animations/A_PlayerCharacter_Summon.uasset | AnimSequence | Supplementary AnimSequence presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| PlayerCharacter/Animations/A_PlayerCharacter_Wall.uasset | AnimSequence | Supplementary AnimSequence presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| PlayerCharacter/Character/PHYS_PlayerCharacter.uasset | PhysicsAsset | Mandatory dependency for ASSET-01 | ASSET-01 |
| PlayerCharacter/Character/SKEL_PlayerCharacter.uasset | Skeleton | Mandatory dependency for ASSET-01 | ASSET-01 |
| PlayerCharacter/Character/SK_PlayerCharacter.uasset | SkeletalMesh | Mage body, skull, robe and open book; Dependency of /Game/PlayerCharacter/Character/PHYS_PlayerCharacter | ASSET-01 |
| PlayerCharacter/Materials/M_PlayerCharacter.uasset | Material | Mandatory dependency for ASSET-01 | ASSET-01 |
| PlayerCharacter/Materials/M_PlayerCharacter_RGB.uasset | Texture2D | Mandatory dependency for ASSET-01 | ASSET-01 |
| PlayerCharacter/Materials/T_PlayerCharacter_E.uasset | Texture2D | Mandatory dependency for ASSET-01 | ASSET-01 |
| PlayerCharacter/Materials/T_PlayercCharacter_D.uasset | Texture2D | Mandatory dependency for ASSET-01 | ASSET-01 |
| SimpleDungeons/Materials/Mat_SimpleDungeons.uasset | Material | Mandatory dependency for ASSET-02 | ASSET-02 |
| SimpleDungeons/Materials/Mat_SimpleDungeons_DustParticle.uasset | Material | Supplementary Material presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Materials/Mat_SimpleDungeons_LavaGlow.uasset | Material | Supplementary Material presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/EnvParts/SM_Env_Door_Main_03.uasset | StaticMesh | Animated gate leaf | ASSET-02 |
| SimpleDungeons/Meshes/Environment/EnvParts/SM_Env_PrisonCell_Door_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Alter_Evil_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Door_03.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Doorway_01.uasset | StaticMesh | Principal dungeon architecture: Doorway_01 | ASSET-02 |
| SimpleDungeons/Meshes/Environment/SM_Env_Floor_Stone_01.uasset | StaticMesh | Principal dungeon architecture: Floor_Stone_01 | ASSET-02 |
| SimpleDungeons/Meshes/Environment/SM_Env_Floor_Stone_02.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Floor_Stone_03.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Floor_Stone_Broken_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Floor_Stone_Broken_02.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Floor_Stone_Broken_03.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Floor_Stone_Broken_04.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Floor_Stone_Broken_05.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Floor_Stone_ClearEdge_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Floor_Stone_ClearEdge_02.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Floor_Stone_ClearEdge_03.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Pillar_Stone_01.uasset | StaticMesh | Principal dungeon architecture: Pillar_Stone_01 | ASSET-02 |
| SimpleDungeons/Meshes/Environment/SM_Env_Pillar_Stone_02.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Pillar_Stone_03.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Pillar_Stone_Broken_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Pillar_Stone_Broken_02.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Pillar_Stone_Broken_03.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Pit_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_PrisonCell_DoorFrame_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_PrisonCell_Wall_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Railing_Stone_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Railing_Stone_02.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Railing_Stone_Pillar_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Railing_Stone_Pillar_02.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Railing_Wood_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Railing_Wood_02.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_StoneCircle_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Undead_Floor_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Undead_Floor_02.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Undead_Floor_03.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Undead_Floor_04.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Undead_Pillar_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Undead_Pillar_Broken_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Undead_Wall_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Undead_Wall_02.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Undead_Wall_03.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Wall_01.uasset | StaticMesh | Principal dungeon architecture: Wall_01 | ASSET-02 |
| SimpleDungeons/Meshes/Environment/SM_Env_Wall_02.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Wall_Half_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Environment/SM_Env_Wall_Half_02.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/PropParts/SM_Prop_Lever_Floor_Handle_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/PropParts/SM_Prop_Lever_Wall_Handle_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/PropParts/SM_Prop_Stone_Coffin_Lid_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_AlchemyTable_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Alter_Good_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Banner_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Banner_Emblem_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Banner_Emblem_02.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Banner_Emblem_Ripped_02.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Banner_Ripped_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Banner_Ripped_02.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Brazier_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Brazier_02.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Cage_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_CandleStand_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_CandleStand_02.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Cauldron_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_ChairStraps_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Chest_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Coin_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Corpse_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Corpse_02.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Corpse_03.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Crown_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Gem_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Gem_02.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Gem_03.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Gem_04.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Gem_05.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Grate_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Lever_Floor_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Lever_Wall_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Pedestal_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Pit_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Pot_Large_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Pot_Large_02.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Pot_Large_03.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Potion_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Skeleton_03.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Skeleton_04.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Skull_01.uasset | StaticMesh | Room dressing: Skull_01 | ASSET-02 |
| SimpleDungeons/Meshes/Props/SM_Prop_Skull_Pile_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Stone_Coffin_01.uasset | StaticMesh | Room dressing: Stone_Coffin_01 | ASSET-02 |
| SimpleDungeons/Meshes/Props/SM_Prop_Sword_Rusty_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Table_02.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_Torch_01.uasset | StaticMesh | Room dressing: Torch_01 | ASSET-02 |
| SimpleDungeons/Meshes/Props/SM_Prop_WallCuffs_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Props/SM_Prop_WallGrate_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Traps/SM_Trap_BuzzSaw_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Traps/SM_Trap_FloorGrinder_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Traps/SM_Trap_FloorGrinder_02.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Traps/SM_Trap_SpikeBlock_02.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Traps/SM_Trap_SpikeGrate_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Traps/TrapDevices/SM_Trap_BuzzSaw_Blade_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Traps/TrapDevices/SM_Trap_FloorGrinde_Main_02_B.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Traps/TrapDevices/SM_Trap_FloorGrinder_Main_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Traps/TrapDevices/SM_Trap_FloorGrinder_Main_02_A.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Traps/TrapDevices/SM_Trap_SpikeGrate_Spikes_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Meshes/Traps/TrapDevices/SM_Trap_SwingingAxe_Axe_01.uasset | StaticMesh | Supplementary StaticMesh presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| SimpleDungeons/Textures/Tex_SimpleDungeon.uasset | Texture2D | Mandatory dependency for ASSET-02 | ASSET-02 |
| Sounds/A_Bonk.uasset | SoundWave | Monster hit | ASSET-06 |
| Sounds/A_CastMagic.uasset | SoundWave | Cast | ASSET-06 |
| Sounds/A_Coin.uasset | SoundWave | Coin pickup | ASSET-06 |
| Sounds/A_GetKey.uasset | SoundWave | Key pickup | ASSET-06 |
| Sounds/A_IncreaseLives.uasset | SoundWave | Heart pickup / extra life | ASSET-06 |
| Sounds/A_Lose.uasset | SoundWave | Defeat | ASSET-06 |
| Sounds/A_Monster.uasset | SoundWave | Danger warning | ASSET-06 |
| Sounds/A_Music.uasset | SoundWave | Background music | ASSET-06 |
| Sounds/A_OpenDoor.uasset | SoundWave | Door opening | ASSET-06 |
| Sounds/A_TakeMagic.uasset | SoundWave | Scroll pickup | ASSET-06 |
| Sounds/A_Teleport.uasset | SoundWave | Room transfer | ASSET-06 |
| Sounds/A_Win.uasset | SoundWave | Victory | ASSET-06 |
| UserInterface/Buttons/T_Button_Hover.uasset | Texture2D | Button hover state | ASSET-04 |
| UserInterface/Buttons/T_Button_Normal.uasset | Texture2D | Button normal state | ASSET-04 |
| UserInterface/Buttons/T_Button_Pressed.uasset | Texture2D | Button pressed state | ASSET-04 |
| UserInterface/Fonts/Font_Logo.uasset | FontFace | Title typography; Dependency of /Game/UserInterface/Fonts/Font_Logo_Font | ASSET-07 |
| UserInterface/Fonts/Font_Logo_Font.uasset | Font | Title typography | ASSET-07 |
| UserInterface/Fonts/Font_Main.uasset | FontFace | HUD/main UI typography; Dependency of /Game/UserInterface/Fonts/Font_Main_Font | ASSET-07 |
| UserInterface/Fonts/Font_Main_Font.uasset | Font | HUD/main UI typography | ASSET-07 |
| UserInterface/HUD/Textures/AttemptsIcon.uasset | Texture2D | Scroll pickup appearance; HUD AttemptsIcon | ASSET-03, ASSET-04 |
| UserInterface/HUD/Textures/CoinIcon.uasset | Texture2D | HUD CoinIcon | ASSET-04 |
| UserInterface/HUD/Textures/HeartImage_UI.uasset | Texture2D | HUD HeartImage_UI | ASSET-04 |
| UserInterface/HUD/Textures/KeyBlueActive.uasset | Texture2D | HUD KeyBlueActive | ASSET-04 |
| UserInterface/HUD/Textures/KeyBlueInactive.uasset | Texture2D | HUD KeyBlueInactive | ASSET-04 |
| UserInterface/HUD/Textures/KeyGreenActive.uasset | Texture2D | HUD KeyGreenActive | ASSET-04 |
| UserInterface/HUD/Textures/KeyGreenInactive.uasset | Texture2D | HUD KeyGreenInactive | ASSET-04 |
| UserInterface/HUD/Textures/KeyRedActive.uasset | Texture2D | HUD KeyRedActive | ASSET-04 |
| UserInterface/HUD/Textures/KeyRedInactive.uasset | Texture2D | HUD KeyRedInactive | ASSET-04 |
| UserInterface/HUD/Textures/MonsterGreen.uasset | Texture2D | HUD MonsterGreen | ASSET-04 |
| UserInterface/HUD/Textures/MonsterRed.uasset | Texture2D | HUD MonsterRed | ASSET-04 |
| UserInterface/HUD/Textures/MonsterYellow.uasset | Texture2D | HUD MonsterYellow | ASSET-04 |
| UserInterface/HUD/Textures/SkullIcon.uasset | Texture2D | Supplementary Texture2D presentation asset for room/effect variety; no gameplay behavior | Supplementary |
| UserInterface/HUD/Textures/emptyHeartImageUI.uasset | Texture2D | Supplementary Texture2D presentation asset for room/effect variety; no gameplay behavior | Supplementary |
