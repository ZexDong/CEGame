using System;
using System.Linq;
using GameCreate.NoirRoombreak.Evaluator;

static class NoirAudioArchitectureRegression
{
    static int failures;
    static SuppliedAssetRules.Identity Id(string path) => new SuppliedAssetRules.Identity(path);
    static void Check(bool condition, string message) { if (!condition) { failures++; Console.Error.WriteLine("FAIL: " + message); } else Console.WriteLine("PASS: " + message); }

    public static int Main()
    {
        var standard = new[]
        {
            Id("Assets/TaskAssets/NoirSource/Audio/Player/Jump.wav"),
            Id("Assets/TaskAssets/NoirSource/Audio/Player/Dash.wav"),
            Id("Assets/TaskAssets/NoirSource/Audio/Player/Attack.wav"),
            Id("Assets/TaskAssets/NoirSource/Audio/Player/Kill.wav"),
            Id("Assets/TaskAssets/NoirSource/Audio/Player/PlayerDeath.wav"),
            Id("Assets/TaskAssets/NoirSource/Audio/Enemy/AlertSound.wav"),
            Id("Assets/TaskAssets/NoirSource/Audio/Enemy/laserShoot.wav")
        };
        Check(SuppliedAssetRules.HasEquivalentAudioInventory(standard, 7, false, out var standardRoles), "persistent AudioSource.clip inventory is accepted");
        Check(standardRoles.Contains("jump") && standardRoles.Contains("alert") && standardRoles.Contains("laser"), "standard roles resolve from canonical protected paths");

        Check(SuppliedAssetRules.HasEquivalentAudioInventory(standard, 1, true, out var oneShotRoles), "one clipless AudioSource plus serialized supplied AudioClip fields is accepted for PlayOneShot");
        Check(SuppliedAssetRules.HasSuppliedActionFeedback(standard, "jump", true), "normal jump playback plus supplied jump reference passes action feedback");
        Check(!SuppliedAssetRules.HasSuppliedActionFeedback(standard, "jump", false), "mere serialized clip references do not fake action playback");

        var normalized = new[] { Id(@"ASSETS\TASKASSETS\NOIRSOURCE\AUDIO\PLAYER\JUMP.WAV"), Id("assets/taskassets/noirsource/audio/player/attack.wav"), Id("assets/taskassets/noirsource/audio/enemy/laserShoot.wav") };
        Check(SuppliedAssetRules.HasEquivalentAudioInventory(normalized, 1, true, out var normalizedRoles), "public catalog paths are normalized without license, credit, or content-hash gates");
        Check(normalizedRoles.SequenceEqual(new[] { "attack", "jump", "laser" }), "catalog-path roles are exact and deterministic");

        var fake = new[] { Id("Assets/NoirChallenge/Fake/Jump.wav"), Id("Assets/NoirChallenge/Fake/Dash.wav"), Id("Assets/NoirChallenge/Fake/Laser.wav") };
        Check(!SuppliedAssetRules.HasEquivalentAudioInventory(fake, 3, true, out _), "filename-token replacements without a public-catalog source reference do not count as supplied audio");
        Check(!SuppliedAssetRules.HasEquivalentAudioInventory(standard, 0, false, out _), "references without an AudioSource or observed action playback do not count as assembled output");

        Console.WriteLine(failures == 0 ? "Noir audio architecture regression: PASS" : $"Noir audio architecture regression: FAIL ({failures})");
        return failures == 0 ? 0 : 1;
    }
}
