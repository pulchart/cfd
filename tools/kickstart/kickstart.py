#!/usr/bin/env python3
"""CFD Kickstart ROM builder for Amiga 600 / 1200 (AmigaOS 3.1 and 3.2.3).

Produces 1 MB ROMs that include extra modules.

Prerequisites (pre-installed on this system):
  /opt/Capitoline/capcli.Linux
  /opt/Capitoline/Components, /opt/Capitoline/Capitoline Hashes
  /opt/AmigaOS/Update3.2.3/{ROMs,ADFs}                 (3.2.3 builds)
  /opt/AmigaOS/AmigaOS3.1/{ROMs,ADFs}                  (3.1 builds)
  /opt/AmigaOS/AmigaOS2.05/{ROMs,ADFs}                 (2.05 builds, A600)
  /opt/AmigaOS/AmigaOS2.04/{ROMs,ADFs}                 (2.04 builds, A500+)
  /opt/AmigaOS/AmigaOS3.2/adf/...
"""

from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

import yaml
from jinja2 import Environment, FileSystemLoader

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent

CAPITOLINE_DIR = Path("/opt/Capitoline")
CAPCLI = CAPITOLINE_DIR / "capcli.Linux"

KICKSTART_YAML = SCRIPT_DIR / "kickstart.yaml"
OUT_DIR = SCRIPT_DIR / "out"

VALID_ROMS = ("E0", "F8")


@dataclass
class FileEntry:
    name: str
    kind: str = "file"


@dataclass
class AdfGroup:
    adf_ref: str
    libs: list[str]
    kind: str = "adf_group"


@dataclass
class SourceRomEntry:
    """Stock module pulled from `$SOURCEROM`, used by `relocate` rows to
    place a stock F8 module into the E0 ROM (template emits
    `add "$SOURCEROM" <name>` in the E0 section)."""
    name: str
    kind: str = "from_source_rom"


def _load_config() -> dict:
    """Load kickstart.yaml once at module init.

    Convert YAML strings to native Python types where useful (amigaos_dir
    becomes a Path).  Everything else stays as-is and is consumed downstream.
    """
    cfg = yaml.safe_load(KICKSTART_YAML.read_text())
    for m in cfg["models"].values():
        m["amigaos_dir"] = Path(m["amigaos_dir"])
    return cfg


CONFIG = _load_config()
MODELS = CONFIG["models"]


def info(msg: str) -> None:
    print(f"==>    {msg}")


def die(msg: str, code: int = 1) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(code)


def preflight(models: list[str]) -> None:
    if not (CAPCLI.is_file() and os.access(CAPCLI, os.X_OK)):
        die(f"Missing {CAPCLI}")
    if not (CAPITOLINE_DIR / "Components").is_dir():
        die(f"Missing {CAPITOLINE_DIR / 'Components'}")
    if not KICKSTART_YAML.is_file():
        die(f"Missing {KICKSTART_YAML}")
    for m in models:
        cfg = MODELS[m]
        amiga = cfg["amigaos_dir"]
        if not (amiga / "ROMs").is_dir():
            die(f"Missing {amiga / 'ROMs'} (for {m})")
        if not (amiga / "ADFs").is_dir():
            die(f"Missing {amiga / 'ADFs'} (for {m})")
        tmpl = SCRIPT_DIR / cfg["template"]
        if not tmpl.is_file():
            die(f"Missing template {tmpl} (for {m})")


def _need_rom(r: dict, allowed: tuple = VALID_ROMS) -> str:
    """Require the row to carry an explicit `rom:` field from `allowed`."""
    rom = r.get("rom")
    if rom is None:
        die(f"row {r!r} is missing required `rom:` field "
            f"(must be one of {', '.join(allowed)})")
    rom = rom.upper()
    if rom not in allowed:
        die(f"`rom:` must be one of {allowed} (got {r.get('rom')!r}) "
            f"in row {r!r}")
    return rom


def _ensure_unique_target(target: str, patched: dict) -> None:
    """Reject two rows that touch the same stock module."""
    if target in patched:
        die(f"Two rows target stock module '{target}' in {KICKSTART_YAML.name}")


def _link_adf(adf_path: Path, workdir: Path) -> Path:
    """Symlink an ADF into workdir so capcli's `loadadf "<basename>"` finds it."""
    if not adf_path.is_file():
        die(f"Missing ADF: {adf_path}")
    link = workdir / adf_path.name
    if not link.exists():
        link.symlink_to(adf_path)
    return link


def _handle_skip(r: dict, workdir: Path, by_rom: dict, patched: dict) -> None:
    """`skip:` -- drop a stock F8 module entirely (no `rom:` allowed)."""
    target = r["skip"]
    if "rom" in r:
        die(f"`skip` row must not specify `rom:`, skipped modules "
            f"aren't added to either ROM bank: {r!r}")
    _ensure_unique_target(target, patched)
    patched[target] = f"# Skipped: {target} (see kickstart.yaml)"


def _handle_relocate(r: dict, workdir: Path, by_rom: dict, patched: dict) -> None:
    """`relocate:` -- move a stock F8 module to E0 (keep stock content)."""
    target = r["relocate"]
    _need_rom(r, allowed=("E0",))
    _ensure_unique_target(target, patched)
    patched[target] = f"# Relocated to E0: {target} (stock from $SOURCEROM)"
    by_rom["E0"].append(SourceRomEntry(name=target))


def _handle_replace(r: dict, workdir: Path, by_rom: dict, patched: dict) -> None:
    """`replace:` + `with:` (file) or `adf:`+`adf_path:` (ADF entry).

    `rom: "F8"` substitutes at the stock module's natural slot; `rom: "E0"`
    suppresses the F8 line and lands the substitute in E0 instead.
    """
    target = r["replace"]
    _ensure_unique_target(target, patched)
    rom_dst = _need_rom(r)

    if "with" in r:
        staged_path = r["with"]
        if rom_dst == "F8":
            patched[target] = (f"# Patched: {target}\n"
                               f'add "{staged_path}"')
        else:
            patched[target] = (f"# Relocated to E0: {target} "
                               f"(substituted with {staged_path})")
            by_rom["E0"].append(FileEntry(name=Path(staged_path).name))
    elif "adf" in r:
        # `adf_path` is case-sensitive: capcli's `add ADF:/<path>` does an
        # exact-case lookup against the entry names in the loaded ADF.
        # A mismatch (e.g. `LIBS/RESOURCES/` vs the actual `LIBS/Resources/`)
        # leaves TEMPFILE.bin unwritten and capcli logs
        # `ERROR: Unable to open file TEMPFILE.bin` while still exiting 0.
        # `run_capcli` greps the log for `error:` and dies hard, so any
        # case typo surfaces as a build failure instead of silently shipping
        # a broken ROM.
        adf = _link_adf(Path(r["adf"]), workdir)
        inner = r["adf_path"]
        if rom_dst == "F8":
            patched[target] = (f"# Patched: {target} (from {adf.name})\n"
                               f'loadadf "{adf.name}"\n'
                               f"add ADF:/{inner}")
        else:
            patched[target] = (f"# Relocated to E0: {target} "
                               f"(substituted from {adf.name})")
            by_rom["E0"].append(AdfGroup(adf_ref=adf.name, libs=[inner]))
    else:
        die(f"`replace` row for '{target}' needs either `with:` (file path) "
            f"or `adf:`+`adf_path:` (entry inside an ADF)")


def _handle_adf(r: dict, workdir: Path, by_rom: dict, patched: dict) -> None:
    """`adf:` + `adf_path:` (specific ADF) or `adf_modules:` (model `$ADF`).

    Consecutive rows that share the same ADF reference collapse into a
    single `loadadf` followed by multiple `add ADF:/...` directives.
    """
    rom = _need_rom(r)
    if "adf_modules" in r:
        adf_ref, lib_path = "$ADF", r["adf_modules"]
    else:
        adf = _link_adf(Path(r["adf"]), workdir)
        adf_ref, lib_path = adf.name, r["adf_path"]
    bucket = by_rom[rom]
    if bucket and isinstance(bucket[-1], AdfGroup) and bucket[-1].adf_ref == adf_ref:
        bucket[-1].libs.append(lib_path)
    else:
        bucket.append(AdfGroup(adf_ref=adf_ref, libs=[lib_path]))


def _handle_file(r: dict, workdir: Path, by_rom: dict, patched: dict) -> None:
    """`file:` -- add a file from disk to a ROM bank by basename."""
    rom = _need_rom(r)
    src = Path(r["file"])
    if not src.is_absolute():
        src = REPO_ROOT / src
    if not src.is_file():
        die(f"Missing module: {src}")
    shutil.copy2(src, workdir / src.name)
    by_rom[rom].append(FileEntry(name=src.name))


def resolve_extra_modules(
    workdir: Path, cpu: str, os_: str
) -> tuple[dict[str, list], dict[str, str]]:
    """Walk the `modules` list from kickstart.yaml; stage sources into workdir.

    Returns `(modules_by_rom, patched_modules)`:
    - `modules_by_rom`: dict keyed by ROM ("E0"/"F8") whose values are
      ordered lists of FileEntry / AdfGroup / SourceRomEntry to add to
      that ROM bank.
    - `patched_modules`: dict mapping a stock F8 module name to the
      capcli-script fragment that replaces its natural `add "$SOURCEROM"
      <name>` line.  Fragments are either a suppression comment
      (`skip` / `relocate` / `replace` rom: "E0"), a `# Patched:` +
      `add "<file>"` pair (`replace` + `with:`), or a `# Patched:` +
      `loadadf "<adf>"` + `add ADF:/<inner>` triplet (`replace` + `adf:`).

    See the argparse `--help` epilog and `docs/kickstart.md` for the
    full YAML schema.
    """
    by_rom: dict[str, list] = defaultdict(list)
    patched: dict[str, str] = {}

    for r in CONFIG["modules"]:
        if r.get("cpu") and r["cpu"] != cpu:
            continue
        if r.get("os") and r["os"] != os_:
            continue

        if "skip" in r:
            _handle_skip(r, workdir, by_rom, patched)
        elif "relocate" in r:
            _handle_relocate(r, workdir, by_rom, patched)
        elif "replace" in r:
            _handle_replace(r, workdir, by_rom, patched)
        elif "adf_modules" in r or "adf" in r:
            _handle_adf(r, workdir, by_rom, patched)
        elif "file" in r:
            _handle_file(r, workdir, by_rom, patched)
        else:
            die(f"row has no recognized verb (skip/relocate/replace/"
                f"adf_modules/adf/file): {r!r}")

    return dict(by_rom), patched


def render_template(
    workdir: Path,
    cfg: dict,
    model: str,
    modules_by_rom: dict[str, list],
    patched_modules: dict[str, str],
) -> Path:
    """Render the model's Jinja template -> workdir/capitoline.script."""
    env = Environment(
        loader=FileSystemLoader(str(SCRIPT_DIR)),
        keep_trailing_newline=True,
    )
    tmpl = env.get_template(cfg["template"])
    text = tmpl.render(
        model=model,
        os=cfg["os"],
        sourcerom_crc=cfg["sourcerom_crc"],
        adf_crc=cfg["adf_crc"],
        saveprofile=cfg["saveprofile"],
        outdir=".",
        f8_modules=modules_by_rom.get("F8", []),
        e0_modules=modules_by_rom.get("E0", []),
        patched_modules=patched_modules,
    )
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
    # capcli exits 0 even when it silently drops `add` directives that
    # don't fit or can't be processed; surface those so the build doesn't
    # ship a broken ROM.
    log_text = log.read_text(errors="replace")
    log_lc = log_text.lower()
    if "space in rom" in log_lc:
        _dump_log_tail(log)
        die(f"capcli reported 'no space in rom' - module silently dropped. See {log}")
    # E.g. `ERROR: Unable to open file TEMPFILE.bin` after a `loadadf + add
    # ADF:/...` pair while building an F8 ROM (capcli mishandles ADF-source
    # adds in F8 mode and drops the component).
    if "error:" in log_lc:
        _dump_log_tail(log)
        die(f"capcli logged an ERROR - module(s) likely dropped silently. See {log}")
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
    os_ = cfg["os"]
    amiga = cfg["amigaos_dir"]

    info("==========================================================")
    info(f"Building {model} ROM (OS {os_}, CPU {cpu})")
    info("==========================================================")

    workdir = SCRIPT_DIR / f"workdir_{model}"
    if workdir.exists():
        shutil.rmtree(workdir)
    workdir.mkdir(parents=True)

    try:
        (workdir / "Components").symlink_to(CAPITOLINE_DIR / "Components")
        (workdir / "Capitoline Hashes").symlink_to(CAPITOLINE_DIR / "Capitoline Hashes")
        (workdir / "ROMs").symlink_to(amiga / "ROMs")
        (workdir / "ADFs").symlink_to(amiga / "ADFs")

        modules_by_rom, patched_modules = resolve_extra_modules(workdir, cpu, os_)
        script = render_template(workdir, cfg, model, modules_by_rom, patched_modules)
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
        prog="kickstart.py",
        description=(
            "CFD Kickstart ROM builder for Amiga 600 / 1200 (AmigaOS 2.05, 3.1, 3.2.3). "
            "Produces 1 MB ROMs that include compactflash.device + ptable.library."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Targets:\n"
            "  a600 / a1200                 AmigaOS 3.2.3\n"
            "  a600-3.2.3 / a1200-3.2.3     same as above (explicit)\n"
            "  a600-3.1   / a1200-3.1       AmigaOS 3.1\n"
            "  a600-2.05                    AmigaOS 2.05 (A600)\n"
            "  a500plus-2.04                AmigaOS 2.04 (A500+)\n"
            "  2.04 / 2.05 / 2.0x / 3.1 / 3.2 / 3.2.3   all ROMs for one OS\n"
            "  all                          every variant (default)\n"
            "\n"
            "kickstart.yaml schema (YAML 1.2; `# ...` comments supported):\n"
            "  models:    dict keyed by model name. Fields per entry:\n"
            "                 os, cpu, sourcerom_crc, adf_crc, saveprofile,\n"
            "                 template, amigaos_dir.\n"
            "  modules:   ordered list of entries. Each entry uses one verb (`rom:` is\n"
            "             mandatory per row except on `skip:`):\n"
            "               {adf_modules: <inner>, rom: \"E0\"|\"F8\"}                     : lib from model's modules ADF\n"
            "               {adf: <path>, adf_path: <inner>, rom: \"E0\"|\"F8\"}           : lib from a specific ADF file\n"
            "               {file: <path>, rom: \"E0\"|\"F8\"}                             : file from disk; added by basename\n"
            "               {replace: <stock>, with|adf+adf_path: ..., rom: \"F8\"|\"E0\"} : swap stock module (F8 slot or relocate to E0)\n"
            "               {skip: <stock>}                                            : drop a stock F8 module (no `rom:`)\n"
            "               {relocate: <stock>, rom: \"E0\"}                             : move a stock F8 module to E0\n"
            "             Optional per-entry filters: cpu: \"68000\"|\"68020\", os: \"3.1\"|\"3.2.3\".\n"
            "             Order in the list = order of `add` directives in the Capitoline script.\n"
            "             See docs/kickstart.md for the full verbs reference.\n"
        ),
    )
    parser.add_argument(
        "target",
        nargs="?",
        default="all",
        help="which ROM(s) to build (default: all, every variant)",
    )
    aliases = {
        "a600":            ["A600-3.2.3"],
        "a1200":           ["A1200-3.2.3"],
        "a600-3.2.3":      ["A600-3.2.3"],
        "a1200-3.2.3":     ["A1200-3.2.3"],
        "a600-3.1":        ["A600-3.1"],
        "a1200-3.1":       ["A1200-3.1"],
        "a600-2.05":       ["A600-2.05"],
        "a500plus":        ["A500plus-2.04"],
        "a500plus-2.04":   ["A500plus-2.04"],
        "2.04":            ["A500plus-2.04"],
        "2.05":            ["A600-2.05"],
        "2.0x":            ["A600-2.05", "A500plus-2.04"],
        "3.1":             ["A600-3.1",   "A1200-3.1"],
        "3.2":             ["A600-3.2.3", "A1200-3.2.3"],
        "3.2.3":           ["A600-3.2.3", "A1200-3.2.3"],
        "all":             ["A600-3.2.3", "A1200-3.2.3", "A600-3.1", "A1200-3.1", "A600-2.05", "A500plus-2.04"],
        "both":            ["A600-3.2.3", "A1200-3.2.3"],
        "":                ["A600-3.2.3", "A1200-3.2.3"],
    }
    args = parser.parse_args(argv)
    target = args.target.lower()
    if target not in aliases:
        parser.error(
            f"Unknown target '{args.target}'. Try: a600 | a1200 | "
            f"a600-3.2.3 | a1200-3.2.3 | a600-3.1 | a1200-3.1 | "
            f"a600-2.05 | a500plus-2.04 | 2.04 | 2.05 | 3.1 | 3.2.3 | all"
        )
    return aliases[target]


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    models = parse_args(argv)
    preflight(models)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for m in models:
        build_one(m)
    info("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
