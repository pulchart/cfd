#!/usr/bin/env python3
"""CFD Kickstart ROM builder for Amiga 600 / 1200.

Produces 1 MB ROMs that include compactflash.device + ptable.library.

Prerequisites (pre-installed on this system):
  /opt/Capitoline/capcli.Linux
  /opt/Capitoline/Components, /opt/Capitoline/Capitoline Hashes
  /opt/AmigaOS/Update3.2.3/{ROMs,ADFs}
  /opt/AmigaOS/AmigaOS3.2/adf/workbench3.2.adf  (for rexxsyslib, optional)
  xdftool in PATH                               (optional, for rexxsyslib)

Usage:
  build_rom.py            # builds both A600 and A1200
  build_rom.py a600
  build_rom.py a1200
  build_rom.py --help
"""

from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent

CAPITOLINE_DIR = Path("/opt/Capitoline")
CAPCLI = CAPITOLINE_DIR / "capcli.Linux"
AMIGAOS_DIR = Path("/opt/AmigaOS/Update3.2.3")
WB32_ADF = Path("/opt/AmigaOS/AmigaOS3.2/adf/workbench3.2.adf")

TEMPLATE = SCRIPT_DIR / "capitoline.script.in"
OUT_DIR = SCRIPT_DIR / "out"
DIST_DIR = REPO_ROOT / "dist" / "full"

MODELS = {
    "A600": {
        "cpu": "68000",
        "sourcerom_crc": "0xe1f50b0b",  # CDTVA500A600A2000.47.115.rom
        "adf_crc": "0xb6dfa531",        # ModulesA600_3.2.3.adf
        # A600 uses a single 16-bit Kickstart ROM; flash cfd.rom directly.
        # No byteswapped split halves needed.
        "saveprofile": "",
    },
    "A1200": {
        "cpu": "68020",
        "sourcerom_crc": "0xb18d3b67",  # A1200.47.115.rom
        "adf_crc": "0x920f6115",        # ModulesA1200_3.2.3.adf
        # A1200 has two physical Kickstart chips; produce byteswapped
        # 512 KB halves cfd.hi.bin / cfd.lo.bin for dual-chip flashing.
        "saveprofile": (
            "romprofile dual 0 1\n"
            "saveprofile 512 byteswap ./cfd"
        ),
    },
}


def info(msg: str) -> None:
    print(f"==>    {msg}")


def warn(msg: str) -> None:
    print(f"WARN:  {msg}", file=sys.stderr)


def die(msg: str, code: int = 1) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(code)


def preflight() -> None:
    if not (CAPCLI.is_file() and os.access(CAPCLI, os.X_OK)):
        die(f"Missing {CAPCLI}")
    if not (CAPITOLINE_DIR / "Components").is_dir():
        die(f"Missing {CAPITOLINE_DIR / 'Components'}")
    if not (AMIGAOS_DIR / "ROMs").is_dir():
        die(f"Missing {AMIGAOS_DIR / 'ROMs'}")
    if not (AMIGAOS_DIR / "ADFs").is_dir():
        die(f"Missing {AMIGAOS_DIR / 'ADFs'}")
    if not TEMPLATE.is_file():
        die(f"Missing {TEMPLATE}")


def extract_rexxsyslib(workdir: Path) -> str:
    """Extract rexxsyslib.library from workbench3.2.adf into workdir.

    Returns the Capitoline `add` line to substitute, or empty string on miss.
    """
    if not WB32_ADF.is_file() or shutil.which("xdftool") is None:
        warn(f"Skipping rexxsyslib.library (missing {WB32_ADF} or xdftool).")
        return ""

    info(f"Extracting rexxsyslib.library from {WB32_ADF}")
    target = workdir / "rexxsyslib.library"
    result = subprocess.run(
        ["xdftool", str(WB32_ADF), "read", "Libs/rexxsyslib.library", str(target)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if result.returncode != 0 or not target.is_file():
        warn("xdftool failed to extract rexxsyslib.library - skipping")
        return ""
    return "add rexxsyslib.library"


def render_template(workdir: Path, cfg: dict, model: str, add_rexx_line: str) -> Path:
    """Render capitoline.script.in -> workdir/capitoline.script."""
    text = TEMPLATE.read_text()
    replacements = {
        "@@SOURCEROM_CRC@@": cfg["sourcerom_crc"],
        "@@ADF_CRC@@": cfg["adf_crc"],
        "@@MODEL@@": model,
        "@@SAVEPROFILE@@": cfg["saveprofile"],
        "@@OUTDIR@@": ".",
        "@@ADD_REXXSYSLIB@@": add_rexx_line,
    }
    for token, value in replacements.items():
        text = text.replace(token, value)
    out = workdir / "capitoline.script"
    out.write_text(text)
    return out


def run_capcli(workdir: Path, script: Path) -> Path:
    """Run capcli.Linux from workdir with stdin from script. Returns log path."""
    info("Running capcli.Linux...")
    log = workdir / "capitoline.log"
    with script.open("rb") as stdin, log.open("wb") as out:
        result = subprocess.run(
            [str(CAPCLI)],
            cwd=workdir,
            stdin=stdin,
            stdout=out,
            stderr=subprocess.STDOUT,
            check=False,
        )
    if result.returncode != 0:
        _dump_log_tail(log)
        die(f"capcli.Linux failed - see {log}")
    return log


def _dump_log_tail(log: Path, n: int = 40) -> None:
    try:
        lines = log.read_text(errors="replace").splitlines()
        for line in lines[-n:]:
            print(line, file=sys.stderr)
    except OSError:
        pass


def build_one(model: str) -> None:
    cfg = MODELS[model]
    cpu = cfg["cpu"]

    info("==========================================================")
    info(f"Building {model} ROM (CPU {cpu})")
    info("==========================================================")

    dev = DIST_DIR / cpu / "devs" / "compactflash.device"
    lib = DIST_DIR / cpu / "libs" / "ptable.library"
    if not dev.is_file():
        die(f"Missing {dev} - run 'make' in repo root first.")
    if not lib.is_file():
        die(f"Missing {lib} - run 'make' in repo root first.")

    workdir = SCRIPT_DIR / f"workdir_{model}"
    if workdir.exists():
        shutil.rmtree(workdir)
    workdir.mkdir(parents=True)

    try:
        os.symlink(CAPITOLINE_DIR / "Components",        workdir / "Components")
        os.symlink(CAPITOLINE_DIR / "Capitoline Hashes", workdir / "Capitoline Hashes")
        os.symlink(AMIGAOS_DIR / "ROMs",                 workdir / "ROMs")
        os.symlink(AMIGAOS_DIR / "ADFs",                 workdir / "ADFs")

        shutil.copy2(dev, workdir / "compactflash.device")
        shutil.copy2(lib, workdir / "ptable.library")

        add_rexx_line = extract_rexxsyslib(workdir)
        script = render_template(workdir, cfg, model, add_rexx_line)
        log = run_capcli(workdir, script)

        f8 = workdir / "cfd.F8"
        e0 = workdir / "cfd.E0"
        if not f8.is_file():
            _dump_log_tail(log)
            die(f"Missing {f8}")
        if not e0.is_file():
            _dump_log_tail(log)
            die(f"Missing {e0}")

        model_out = OUT_DIR / model
        if model_out.exists():
            shutil.rmtree(model_out)
        model_out.mkdir(parents=True)

        rom = model_out / "cfd.rom"
        with rom.open("wb") as out:
            out.write(f8.read_bytes())
            out.write(e0.read_bytes())

        shutil.copy2(e0, model_out / "cfd.E0")
        shutil.copy2(f8, model_out / "cfd.F8")
        shutil.copy2(log, model_out / "capitoline.log")
        shutil.copy2(script, model_out / "capitoline.script")

        copied = 0
        for f in sorted(workdir.glob("cfd*.bin")):
            shutil.copy2(f, model_out / f.name)
            copied += 1

        info(f"Output in {model_out}/:")
        size = rom.stat().st_size
        sha = hashlib.sha256(rom.read_bytes()).hexdigest()
        print(f"       cfd.rom ({size} bytes)  sha256: {sha}")
        print("       cfd.E0 / cfd.F8 (512 KB halves)")
        print("       capitoline.log + capitoline.script")
        if copied > 0:
            print(f"       {copied} byteswapped split file(s) for EPROM burning")
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


def parse_args(argv: list[str]) -> list[str]:
    parser = argparse.ArgumentParser(
        prog="build_rom.py",
        description=(
            "CFD Kickstart ROM builder for Amiga 600 / 1200. "
            "Produces 1 MB ROMs that include compactflash.device + ptable.library."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Targets:\n"
            "  a600 / A600       build only the A600 ROM\n"
            "  a1200 / A1200     build only the A1200 ROM\n"
            "  all / both        build both (default)\n"
        ),
    )
    parser.add_argument(
        "target",
        nargs="?",
        default="all",
        help="which ROM(s) to build: a600, a1200, all (default: all)",
    )
    args = parser.parse_args(argv)
    target = args.target.lower()
    if target in ("a600",):
        return ["A600"]
    if target in ("a1200",):
        return ["A1200"]
    if target in ("all", "both", ""):
        return ["A600", "A1200"]
    parser.error(f"Unknown target '{args.target}'. Try: a600 | a1200 | all")
    return []  # unreachable


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    models = parse_args(argv)
    preflight()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for m in models:
        build_one(m)
    info("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
