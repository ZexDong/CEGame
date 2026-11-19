// Published NUnit filter: GameCreate.Stormbound.PublicSmoke.StormboundPublicEditModeSmoke
using System;
using System.IO;
using GameCreate.Session;
using NUnit.Framework;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace GameCreate.Stormbound.PublicSmoke
{
    public sealed class StormboundPublicEditModeSmoke
    {
        [Serializable] sealed class Manifest
        {
            public string starter_scene;
            public string asset_manifest;
            public string asset_catalog;
            public string asset_contact_sheet;
            public string runtime_session_model;
        }

        static Manifest ReadManifest()
        {
            return JsonUtility.FromJson<Manifest>(File.ReadAllText("BENCHMARK_MANIFEST.json"));
        }

        [Test]
        public void PUB_EDIT_01_DeclaredStarterSceneExistsAndLoads()
        {
            var path = ReadManifest().starter_scene;
            Assert.That(Application.unityVersion, Does.StartWith("6000.0.80"));
            Assert.NotNull(AssetDatabase.LoadAssetAtPath<SceneAsset>(path));
            Assert.IsTrue(EditorSceneManager.OpenScene(path, OpenSceneMode.Single).IsValid());
        }

        [Test]
        public void PUB_EDIT_02_PublicAssetInventoryIsAvailable()
        {
            var manifest = ReadManifest();
            foreach (var path in new[] { manifest.asset_manifest, manifest.asset_catalog, manifest.asset_contact_sheet })
                Assert.IsTrue(File.Exists(path), path);
        }

        [Test]
        public void PUB_EDIT_03_CommonServiceTypesAndPublicModelAreAvailable()
        {
            Assert.IsTrue(typeof(IGameSession).IsInterface);
            var manifest = ReadManifest();
            Assert.IsTrue(File.Exists("SESSION_MODEL.json"));
            Assert.IsTrue(File.Exists(manifest.runtime_session_model));
            Assert.AreEqual(File.ReadAllText("SESSION_MODEL.json"), File.ReadAllText(manifest.runtime_session_model),
                "The public model and its runtime copy must stay identical.");
            Assert.NotNull(Resources.Load<TextAsset>("session-model"));
        }
    }
}

