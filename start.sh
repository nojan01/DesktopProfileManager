#!/bin/bash
# Desktop Profile Manager starten
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/.venv/bin/python3" "$DIR/desktop_profile_manager_app.py"
