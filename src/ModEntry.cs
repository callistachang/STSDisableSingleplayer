using System;
using HarmonyLib;
using MegaCrit.Sts2.Core.Modding;

namespace DisableSinglePlayer;

/// <summary>
/// Entry point. The loader scans mod assemblies for [ModInitializer] and calls the
/// named static method once the game has finished loading.
/// </summary>
[ModInitializer(nameof(Initialize))]
public static class ModEntry
{
    private const string HarmonyId = "callista.disablesingleplayer";

    /// <summary>Built against Slay the Spire 2 v0.109.1 (commit c8c577f6).</summary>
    internal const string TargetGameVersion = "v0.109.1";

    public static void Initialize()
    {
        try
        {
            var harmony = new Harmony(HarmonyId);

            // Block the run entry points first, so that even if hiding the menu button
            // fails, solo runs stay unreachable.
            SoloRunBlocker.Apply(harmony);
            MenuHider.Apply(harmony);

            PatchUtil.Log($"loaded (built against {TargetGameVersion}).");
        }
        catch (Exception ex)
        {
            PatchUtil.Log($"FAILED to initialize: {ex}");
        }
    }
}
