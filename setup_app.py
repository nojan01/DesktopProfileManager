"""
py2app Setup – erzeugt Desktop Profile Manager.app
Aufruf: python3 setup_app.py py2app

Copyright (c) 2026 Norbert Jander
Lizenz: MIT
"""

from setuptools import setup
import os

# ── tkinter-Recipe deaktivieren ───────────────────────────────────
# Die App nutzt kein tkinter. Die py2app-tkinter-Recipe ruft jedoch
# beim Build _tkinter.create() auf, was mit der Homebrew-Installation
# von tcl-tk 9.0 abstürzt (NaN-Scaling-Bug). Wir schalten die Recipe
# daher hart ab, damit der Build durchläuft.
try:
    import py2app.recipes.tkinter as _tk_recipe

    _tk_recipe.check = lambda cmd, mf: None
except Exception:
    pass

APP_NAME = "Desktop Profile Manager"
APP_VERSION = "1.2.0"
APP_SCRIPT = "desktop_profile_manager_app.py"
ICON_FILE = "icon.icns"

setup(
    name=APP_NAME,
    version=APP_VERSION,
    app=[APP_SCRIPT],
    data_files=[],
    options={
        "py2app": {
            "iconfile": ICON_FILE,
            "plist": {
                "CFBundleName": APP_NAME,
                "CFBundleDisplayName": APP_NAME,
                "CFBundleIdentifier": "com.desktopprofilemanager.app",
                "CFBundleVersion": APP_VERSION,
                "CFBundleShortVersionString": APP_VERSION,
                "LSMinimumSystemVersion": "12.0",
                "LSUIElement": True,  # Kein Dock-Icon
                "NSHumanReadableCopyright": "Copyright © 2026 Norbert Jander. MIT License.",
                "CFBundleDocumentTypes": [],
                "NSAppleEventsUsageDescription":
                    "Desktop Profile Manager benötigt Zugriff auf Finder und System Events, "
                    "um Desktop-Icons, den Hintergrund sowie Fensterpositionen "
                    "von Apps zu lesen und wiederherzustellen.",
            },
            "packages": ["rumps", "AppKit", "objc"],
            "includes": [
                "rumps",
                "AppKit",
                "Foundation",
            ],
            "excludes": [
                "tkinter",
                "_tkinter",
                "Tkinter",
                "tcl",
                "tk",
                "turtle",
                "test",
                "unittest",
                "pydoc_data",
            ],
            "frameworks": [],
            "strip": True,
            "optimize": 2,
            "semi_standalone": False,
            "site_packages": True,
            "arch": "universal2",
        }
    },
    setup_requires=["py2app"],
)
