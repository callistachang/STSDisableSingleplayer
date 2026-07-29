using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using HarmonyLib;
using MegaCrit.Sts2.Core.Logging;

namespace DisableSinglePlayer;

/// <summary>
/// Reflection helpers for patching an Early Access target.
///
/// Every signature this mod touches was read out of sts2.dll v0.109.1. Mega Crit
/// renames things between patches, so nothing here assumes a lookup succeeded: a
/// missing target is logged and skipped instead of throwing, so one stale patch
/// can't take the rest of the mod (or the main menu) down with it.
/// </summary>
internal static class PatchUtil
{
    internal static void Log(string message) => MegaCrit.Sts2.Core.Logging.Log.Warn($"[DisableSinglePlayer] {message}");

    /// <summary>Every method on <paramref name="type"/> with the given name, overloads included.</summary>
    internal static IReadOnlyList<MethodInfo> FindAll(Type type, string name)
    {
        const BindingFlags Flags = BindingFlags.Public | BindingFlags.NonPublic
                                 | BindingFlags.Instance | BindingFlags.Static
                                 | BindingFlags.DeclaredOnly;

        var found = type.GetMethods(Flags).Where(m => m.Name == name).ToList();
        if (found.Count == 0)
            Log($"MISSING: {type.FullName}.{name} not found -- game update likely renamed it.");

        return found;
    }

    /// <summary>Applies <paramref name="patch"/> to every overload, logging which ones landed.</summary>
    internal static void PatchAll(
        Harmony harmony, Type type, string name, Func<MethodInfo, HarmonyMethod?> patch)
    {
        foreach (var target in FindAll(type, name))
        {
            var prefix = patch(target);
            if (prefix == null) continue;

            try
            {
                harmony.Patch(target, prefix: prefix);
                Log($"patched {type.Name}.{name}({Describe(target)}) -> {target.ReturnType.Name}");
            }
            catch (Exception ex)
            {
                Log($"FAILED to patch {type.Name}.{name}: {ex.Message}");
            }
        }
    }

    private static string Describe(MethodInfo m) =>
        string.Join(", ", m.GetParameters().Select(p => p.ParameterType.Name));

    /// <summary>Reads a private field, returning null instead of throwing if it has been renamed or removed.</summary>
    internal static T? GetField<T>(object instance, string fieldName) where T : class
    {
        var field = AccessTools.Field(instance.GetType(), fieldName);
        if (field == null)
        {
            Log($"MISSING: field '{fieldName}' on {instance.GetType().Name}.");
            return null;
        }

        return field.GetValue(instance) as T;
    }
}
