"""Check make test dependencies before importing the emulator."""

import importlib.metadata as md
import subprocess
import sys
from pathlib import Path
from toolchain import PTABLE_SRC, VASM

# The amiga-toolchain image lists the Python packages it installs, at the
# versions the suites run with; make runs the suites in that image.
IMAGE_REQUIREMENTS = Path("/usr/share/amiga-toolchain/requirements.txt")


def image_versions():
    """The image's pinned versions by distribution name, {} outside the image."""
    pins = {}
    if IMAGE_REQUIREMENTS.is_file():
        for line in IMAGE_REQUIREMENTS.read_text().splitlines():
            name, _, pinned = line.split("#")[0].partition("==")
            if pinned:
                pins[name.split("[")[0].strip().lower()] = pinned.strip()
    return pins


def main():
    bad = sys.version_info < (3, 14)
    print("Python", sys.version.split()[0], "(3.14+ required)")
    pins = image_versions()
    for name in ("amitools", "machine68k"):
        tested = pins.get(name)
        try:
            version = md.version(name)
            print(name, version, "" if tested in (None, version) else f"(the image has {tested})")
        except md.PackageNotFoundError:
            print(name, "missing; run make, which uses the amiga-toolchain image,")
            print("or uv pip install -r its requirements.txt")
            bad = True
    for name in ("amitools-amifuse", "machine68k-amifuse"):
        try:
            md.version(name)
        except md.PackageNotFoundError:
            continue
        print(name, "claims the import path of the upstream package; use a fresh venv,")
        print("or uninstall both providers and reinstall the image's requirements.txt")
        bad = True
    try:
        result = subprocess.run([VASM, "-v"], capture_output=True, text=True, timeout=10)
        banner = (result.stdout + result.stderr).strip().splitlines()[0]
        print(VASM, banner)
        if "2.0f" not in banner:
            print("vasm version untested; expected 2.0f")
    except OSError, subprocess.SubprocessError, IndexError:
        print("vasm missing; set VASM_HOME or put vasmm68k_mot on PATH")
        bad = True
    if not (PTABLE_SRC / "ptable_pub.i").is_file():
        print(
            f"ptable missing at {PTABLE_SRC.parent}; run git submodule update --init or set PTABLE"
        )
        bad = True
    return int(bad)


if __name__ == "__main__":
    raise SystemExit(main())
