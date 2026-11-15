#!/bin/sh
# Carceral Consultation UI checks: no stray colors, and every clickable
# element is a standard control. Run before every commit that touches the UI.
dir="$(dirname "$0")"
python3 "$dir/check_theme.py" "$@"; a=$?
python3 "$dir/check_controls.py"; b=$?
[ $a -eq 0 ] && [ $b -eq 0 ]
