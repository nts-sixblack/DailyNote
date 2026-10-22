#!/usr/bin/env python3
"""Builds and signs the "DailyNote Lock Screen" refresh shortcut bundled with the app.

Usage: python3 Tools/make_shortcut.py [--unsigned]
Writes DailyNote/Resources/DailyNote Lock Screen.shortcut (signed for "anyone" with `shortcuts sign`).

Flow (mode string comes from GetWallpaperModeIntent, see WallpaperConfig.shortcutMode):
    mode   = Get Wallpaper Mode                    # "same" | "pair" | "lock", plus "blur", "redraw"
    image  = Generate Latest Wallpaper
    all    = Get All Wallpapers
    slot   = Get DailyNote Wallpaper Slot(all)     # position of DailyNote's wallpaper, 0 = make a new one
    places = Lock + Home if mode contains "same", else Lock Screen
    if slot > 0:  Poster = item `slot` of all; set Poster to image for places
    otherwise:    Poster = set wallpaper to image for places (creates a wallpaper)
    if mode contains "redraw": set Poster to image again (iOS sometimes keeps showing the old image)
    if mode contains "pair":   set Poster's Home Screen to Generate Home Screen Wallpaper [redraw]
    switch to Poster
    Confirm Wallpaper Applied                      # commits the slot for the next run

Reusing the slot keeps the Lock Screen gallery from growing by one wallpaper per run.
"blur" turns on the Set Wallpaper action's Legibility Blur (Home Screen only unless mode is "same").
"""
import os
import plistlib
import subprocess
import sys
import tempfile
import uuid

BUNDLE_ID = "com.sixpilot.DaillyNote"
TEAM_ID = "7SW8XKHH7V"
APP_NAME = "DailyNote"
NAME = "DailyNote Lock Screen"
POSTER = "DailyNoteWallpaper"

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "DailyNote", "Resources", f"{NAME}.shortcut")


def uid():
    return str(uuid.uuid4()).upper()


def output_ref(name, action_uuid):
    return {
        "Value": {"OutputName": name, "OutputUUID": action_uuid, "Type": "ActionOutput"},
        "WFSerializationType": "WFTextTokenAttachment",
    }


def poster_ref():
    return {"Value": {"Type": "Variable", "VariableName": POSTER}, "WFSerializationType": "WFTextTokenAttachment"}


def app_intent(type_name, action_uuid, **params):
    return {
        "WFWorkflowActionIdentifier": f"{BUNDLE_ID}.{type_name}",
        "WFWorkflowActionParameters": {
            "AppIntentDescriptor": {
                "AppIntentIdentifier": type_name,
                "BundleIdentifier": BUNDLE_ID,
                "Name": APP_NAME,
                "TeamIdentifier": TEAM_ID,
            },
            "UUID": action_uuid,
            **params,
        },
    }


def action(identifier, **params):
    return {"WFWorkflowActionIdentifier": f"is.workflow.actions.{identifier}", "WFWorkflowActionParameters": params}


def if_(group, input_ref, condition, **params):
    return action("conditional", GroupingIdentifier=group, WFCondition=condition, WFControlFlowMode=0,
                  WFInput={"Type": "Variable", "Variable": input_ref}, **params)


def if_contains(group, mode, text):
    return if_(group, output_ref("Wallpaper Mode", mode), 99, WFConditionalActionString=text)


def otherwise(group):
    return action("conditional", GroupingIdentifier=group, WFControlFlowMode=1)


def end_if(group):
    return action("conditional", GroupingIdentifier=group, UUID=uid(), WFControlFlowMode=2)


def set_wallpaper(image, places, blur, poster=None, action_uuid=None):
    params = dict(UUID=action_uuid or uid(), WFInput=image, WFWallpaperLegibilityBlur=blur,
                  WFWallpaperLocation=places, WFWallpaperShowPreview=False, WFWallpaperSmartCrop=False)
    if poster:
        params["WFSelectedPoster"] = poster
    return action("wallpaper.set", **params)


def set_poster_variable(source):
    return action("setvariable", WFVariableName=POSTER, WFInput=source)


def with_blur(mode, blur_applies, make):
    """Emits make(blur) once, or twice behind `if mode contains "blur"` when the flag matters here."""
    if not blur_applies:
        return make(False)
    g = uid()
    return [if_contains(g, mode, "blur"), *make(True), otherwise(g), *make(False), end_if(g)]


def apply_lock(mode, image, all_ref, slot, places, blur_applies):
    """Points the POSTER variable at DailyNote's wallpaper (existing or new) and sets the image."""
    g_slot = uid()
    item = uid()
    actions = [
        if_(g_slot, output_ref("Wallpaper Slot", slot), 2, WFNumberValue=0),  # slot > 0
        action("getitemfromlist", UUID=item, WFInput=all_ref, WFItemSpecifier="Item At Index",
               WFItemIndex=output_ref("Wallpaper Slot", slot)),
        set_poster_variable(output_ref("Item from List", item)),
        *with_blur(mode, blur_applies, lambda b: [set_wallpaper(image, places, b, poster_ref())]),
        otherwise(g_slot),
    ]

    def new_wallpaper(blur):
        created = uid()
        return [set_wallpaper(image, places, blur, action_uuid=created),
                set_poster_variable(output_ref("Wallpaper", created))]

    actions += with_blur(mode, blur_applies, new_wallpaper)
    actions.append(end_if(g_slot))

    g_redraw = uid()
    actions += [if_contains(g_redraw, mode, "redraw"),
                *with_blur(mode, blur_applies, lambda b: [set_wallpaper(image, places, b, poster_ref())]),
                end_if(g_redraw)]
    return actions


def build():
    mode, lock_img, home_img, all_posters, slot = uid(), uid(), uid(), uid(), uid()
    lock_image = output_ref("Lock Screen Wallpaper", lock_img)
    home_image = output_ref("Home Screen Wallpaper", home_img)
    all_ref = output_ref("Wallpapers", all_posters)

    actions = [
        app_intent("GetWallpaperModeIntent", mode),
        app_intent("GenerateLatestWallpaperIntent", lock_img),
        action("posters.get", UUID=all_posters, WFPosterType="All"),
        app_intent("GetWallpaperSlotIntent", slot, wallpapers=all_ref),
    ]

    g_same = uid()
    actions.append(if_contains(g_same, mode, "same"))
    actions += apply_lock(mode, lock_image, all_ref, slot, ["Lock Screen", "Home Screen"], blur_applies=True)
    actions.append(otherwise(g_same))
    actions += apply_lock(mode, lock_image, all_ref, slot, ["Lock Screen"], blur_applies=False)

    g_pair = uid()
    g_redraw = uid()
    home = lambda b: [set_wallpaper(home_image, ["Home Screen"], b, poster_ref())]
    actions += [
        if_contains(g_pair, mode, "pair"),
        app_intent("GenerateHomeScreenWallpaperIntent", home_img),
        *with_blur(mode, True, home),
        if_contains(g_redraw, mode, "redraw"),
        *with_blur(mode, True, home),
        end_if(g_redraw),
        end_if(g_pair),
        end_if(g_same),
        action("posters.switch", UUID=uid(), WFPoster=poster_ref()),
        app_intent("ConfirmWallpaperAppliedIntent", uid()),
    ]

    return {
        "WFQuickActionSurfaces": [],
        "WFWorkflowActions": actions,
        "WFWorkflowClientVersion": "3612.0.2.1",
        "WFWorkflowHasOutputFallback": False,
        "WFWorkflowHasShortcutInputVariables": False,
        "WFWorkflowIcon": {"WFWorkflowIconGlyphNumber": 61440, "WFWorkflowIconStartColor": -314141441},
        "WFWorkflowImportQuestions": [],
        "WFWorkflowInputContentItemClasses": [],
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowOutputContentItemClasses": [],
        "WFWorkflowTypes": [],
    }


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        unsigned = os.path.join(tmp, f"{NAME}.shortcut")
        with open(unsigned, "wb") as f:
            plistlib.dump(build(), f, fmt=plistlib.FMT_BINARY)
        if "--unsigned" in sys.argv:
            os.replace(unsigned, OUT)
        else:
            subprocess.run(["shortcuts", "sign", "-m", "anyone", "-i", unsigned, "-o", OUT],
                           check=True, stderr=subprocess.DEVNULL)
    print(OUT)


if __name__ == "__main__":
    main()
