using System;
using Godot;
using HarmonyLib;
using MegaCrit.Sts2.Core.Nodes.Screens.MainMenu;

namespace DisableSinglePlayer;

/// <summary>
/// Takes the Singleplayer entry off the main menu, so players aren't offered something
/// <see cref="SoloRunBlocker"/> will silently refuse.
///
/// The button is a private field on NMainMenu (_singleplayerButton in v0.109.1) rather
/// than a stable scene path, so it has to be read reflectively.
/// </summary>
internal static class MenuHider
{
    private const string ButtonField = "_singleplayerButton";

    // Patching _Ready alone isn't enough. NMainMenu.RefreshButtons() re-derives button
    // visibility from save state, and sets `_singleplayerButton.Visible = true` outright
    // whenever there's no run in progress. It runs after abandoning a run and after
    // closing the Timeline screen, either of which would bring the button back.
    private static readonly string[] MenuHooks = { "_Ready", "RefreshButtons" };

    internal static void Apply(Harmony harmony)
    {
        var postfix = new HarmonyMethod(
            AccessTools.Method(typeof(MenuHider), nameof(AfterMainMenuReady)));

        foreach (var hook in MenuHooks)
        {
            foreach (var target in PatchUtil.FindAll(typeof(NMainMenu), hook))
            {
                try
                {
                    harmony.Patch(target, postfix: postfix);
                    PatchUtil.Log($"patched NMainMenu.{hook}");
                }
                catch (Exception ex)
                {
                    PatchUtil.Log($"FAILED to patch NMainMenu.{hook}: {ex.Message}");
                }
            }
        }
    }

    /// <summary>
    /// Runs after the menu finishes building. Deliberately swallows everything: an
    /// exception escaping here would break main menu construction and leave the game
    /// sitting on a black screen.
    /// </summary>
    private static void AfterMainMenuReady(NMainMenu __instance)
    {
        try
        {
            var button = PatchUtil.GetField<Node>(__instance, ButtonField);
            if (button == null) return;

            // Disable it as well as hiding it: a hidden button is still focusable, so a
            // controller could otherwise land on it and activate it sight unseen.
            if (button is BaseButton clickable)
            {
                clickable.Disabled = true;
                clickable.FocusMode = Control.FocusModeEnum.None;
            }

            if (button is CanvasItem drawable)
                drawable.Visible = false;

            PatchUtil.Log("hid the Singleplayer main menu entry.");
        }
        catch (Exception ex)
        {
            PatchUtil.Log($"could not hide Singleplayer button: {ex.Message}");
        }
    }
}
