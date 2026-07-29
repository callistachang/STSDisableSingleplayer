using System;
using System.Reflection;
using System.Threading.Tasks;
using HarmonyLib;
using MegaCrit.Sts2.Core.Nodes;
using MegaCrit.Sts2.Core.Nodes.Screens.CharacterSelect;
using MegaCrit.Sts2.Core.Nodes.Screens.CustomRun;
using MegaCrit.Sts2.Core.Nodes.Screens.DailyRun;
using MegaCrit.Sts2.Core.Runs;

namespace DisableSinglePlayer;

/// <summary>
/// Blocks every code path that can start or resume a solo run. Hiding the menu button
/// is only cosmetic; this is the part that actually prevents solo play.
///
/// In v0.109.1 four methods start a fresh solo run -- NGame is the one the other three
/// funnel into, and those three are the screens the player reaches it from -- and one
/// more resumes a saved run. All five are patched to refuse.
/// </summary>
internal static class SoloRunBlocker
{
    private static readonly (Type Type, string Method)[] Targets =
    {
        (typeof(NGame),                  "StartNewSingleplayerRun"),
        (typeof(NCharacterSelectScreen), "StartNewSingleplayerRun"),
        (typeof(NCustomRunScreen),       "StartNewSingleplayerRun"),
        (typeof(NDailyRunScreen),        "StartNewSingleplayerRun"),
        (typeof(RunManager),             "SetUpSavedSingleplayer"),
    };

    internal static void Apply(Harmony harmony)
    {
        foreach (var (type, method) in Targets)
            PatchUtil.PatchAll(harmony, type, method, PrefixFor);
    }

    /// <summary>
    /// Picks a prefix whose <c>__result</c> parameter matches the target's return type,
    /// which Harmony requires to be exact. Most of these targets are async, so skipping
    /// the original without also filling in a completed Task would leave the caller
    /// awaiting null.
    /// </summary>
    private static HarmonyMethod? PrefixFor(MethodInfo target)
    {
        var ret = target.ReturnType;

        if (ret == typeof(void))
            return new HarmonyMethod(AccessTools.Method(typeof(SoloRunBlocker), nameof(BlockVoid)));

        if (ret == typeof(Task))
            return new HarmonyMethod(AccessTools.Method(typeof(SoloRunBlocker), nameof(BlockTask)));

        if (ret.IsGenericType && ret.GetGenericTypeDefinition() == typeof(Task<>))
        {
            var open = AccessTools.Method(typeof(SoloRunBlocker), nameof(BlockTaskOf));
            return new HarmonyMethod(open.MakeGenericMethod(ret.GetGenericArguments()[0]));
        }

        // Anything else (a Godot SignalAwaiter, a coroutine handle) would need to be
        // decompiled first to work out what a safe stand-in result looks like.
        PatchUtil.Log($"SKIPPED {target.DeclaringType?.Name}.{target.Name}: " +
                      $"unhandled return type {ret.Name}. Decompile it and add a prefix.");
        return null;
    }

    // Returning false skips the original method.
    private static bool BlockVoid(MethodBase __originalMethod)
    {
        Refused(__originalMethod);
        return false;
    }

    private static bool BlockTask(MethodBase __originalMethod, ref Task __result)
    {
        Refused(__originalMethod);
        __result = Task.CompletedTask;
        return false;
    }

    private static bool BlockTaskOf<T>(MethodBase __originalMethod, ref Task<T> __result)
    {
        Refused(__originalMethod);
        __result = Task.FromResult<T>(default!);
        return false;
    }

    private static void Refused(MethodBase origin) =>
        PatchUtil.Log($"refused solo run via {origin.DeclaringType?.Name}.{origin.Name} -- co-op only.");
}
