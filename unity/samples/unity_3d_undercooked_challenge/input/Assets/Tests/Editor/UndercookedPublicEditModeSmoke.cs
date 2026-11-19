using NUnit.Framework;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace GameCreate.Benchmark.Undercooked.PublicSmoke
{
    public sealed class UndercookedPublicEditModeSmoke
    {
        [Test]
        public void PUB_EDIT_01_StarterSceneExistsAndLoads()
        {
            const string path = "Assets/UndercookedStarter/Scenes/KitchenStarter.unity";
            Assert.NotNull(AssetDatabase.LoadAssetAtPath<SceneAsset>(path));
            var scene = EditorSceneManager.OpenScene(path, OpenSceneMode.Single);
            Assert.IsTrue(scene.IsValid());
        }

        [Test]
        public void PUB_EDIT_02_RequiredFirstPartyModelsExist()
        {
            string[] paths =
            {
                "Assets/UndercookedStarter/Art/FBX/Chef.fbx",
                "Assets/UndercookedStarter/Art/FBX/IngredientCrate.fbx",
                "Assets/UndercookedStarter/Art/FBX/ChoppingBoard.fbx",
                "Assets/UndercookedStarter/Art/FBX/CookingPot.fbx",
                "Assets/UndercookedStarter/Art/FBX/Plate.fbx",
                "Assets/UndercookedStarter/Art/FBX/DeliverCountertop.fbx"
            };
            foreach (var path in paths)
                Assert.NotNull(AssetDatabase.LoadAssetAtPath<GameObject>(path), path);
        }

        [Test]
        public void PUB_EDIT_03_RemovedGameplayAndLeanStayAbsent()
        {
            Assert.IsFalse(AssetDatabase.IsValidFolder("Assets/3rdParty/Lean"));
            Assert.IsFalse(AssetDatabase.IsValidFolder("Assets/Scripts"));
        }
    }
}
