using System;
using System.Collections.Generic;
using Benchmark.Dashboard;
using UnityEngine;

/// <summary>Task-owned read-only game-state dashboard. Fill Capture() only.</summary>
public sealed class NoirDashboard : MonoBehaviour, IGameStateDashboard
{
    public string ContractVersion => "game-state-dashboard/v2";
    int revision;
    string lastBody = string.Empty;

    public Snapshot Capture()
    {
        var snapshot = new Snapshot();
        // TODO: map the real game state onto the fixed phase, slots, entities,
        // and clickable targets named in NAMING_TABLES.json. Do not add actions.
        snapshot.phase = GamePhase.NotReady;
        var body = DashboardJson.ToJson(snapshot, false);
        if (!string.Equals(body, lastBody, StringComparison.Ordinal)) { revision++; lastBody = body; }
        snapshot.revision = revision;
        return snapshot;
    }
}
