"""Shared test paths; no emulator import required."""
import os
import shutil
import sys
from pathlib import Path

if sys.flags.optimize:
    raise SystemExit('Tests require assertions: unset PYTHONOPTIMIZE and omit -O.')

ROOT = Path(__file__).resolve().parents[1]
VASM = (os.environ.get('CFD_VASM') or
        (str(Path(os.environ['VASM_HOME']) / 'bin/vasmm68k_mot')
         if os.environ.get('VASM_HOME') else None) or
        shutil.which('vasmm68k_mot') or '/opt/vasm/bin/vasmm68k_mot')
# make passes PTABLE as CFD_PTABLE; a relative path is from the repository root.
PTABLE_SRC = ROOT / os.environ.get('CFD_PTABLE', 'extern/ptable') / 'src'
