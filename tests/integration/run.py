#!/usr/bin/env python3
"""compactflash.device, ptable.library and fat95 on an emulated PCMCIA IDE
card (FS-UAE, A1200).

    run.py --os NAME [--config FILE] [--scenario NAME ...] [--work DIR]
    run.py --list

Runs in an amiga-fsuae OS image (make test-integration): AMIGA_SYSTEM is the
system directory, AMIGA_KICKSTART the ROM and AMIGA_KICKSTART_EXT its second
half. --os names the OS profile of the config. Preparation copies the system
directory and puts the driver set and the test tools on it: the driver,
ptable.library, lsptres and CFInfo from dist/, the guest tools from make,
fat95, lsfsres and PFS3 from their releases unless the config names builds.
Each scenario then gets its own card image, cfd.prefs and steps; the guest
writes its findings to the host directory OUT:, and the host checks them, the
serial log (FLAGS 8) and the image. Exit 0 when every scenario passes.

FS-UAE needs: controller scide with pcmcia on, Fast RAM at most 4 MB (8 MB
Zorro II overlaps the PCMCIA window and card.resource stays off) and
HANDLER_FAT in cfd.prefs. A swap is the Gayle disable bit set and cleared
from the guest; card.resource re-enables the slot at once, so a card cannot
stay out and the UNMOUNT policies are not covered. UAE generates its own card
CIS, so CIS routing is not covered either.
"""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

import yaml
from scenarios import BASE_PREFS, CF0_MOUNTLIST, MIX, RDB, SCENARIOS

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent  # relative paths in the config start here
IMAGE_SECTORS = 131072  # 64 MB card
MIX_SECTORS = 245760  # 120 MB card for the mixed layouts
BOOT_LIMIT = 60  # seconds to the first line in OUT:log.txt
GPT_FAT = "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7"

# this repository's builds (make)
BUILDS = {
    "cfd": "dist/full/68020/devs/compactflash.device",
    "cfinfo": "dist/c/CFInfo",
    "ptable": "dist/full/68020/libs/ptable.library",
    "lsptres": "dist/c/lsptres",
}
# guest tools (make devinfo holdfile cardout cardin noreq)
GUEST_TOOLS = [
    ROOT / "build/tools" / n for n in ("devinfo", "holdfile", "cardout", "cardin", "noreq")
]
# releases fetched into build/deps when the config names no build:
# key: (url, SHA-256 of the download, file in the lha archive or None for a plain file)
FAT95_LHA = "https://github.com/pulchart/fat95/releases/download/v20261115/fat95.v20261115.lha"
FAT95_SHA256 = "0493cea074caccda415716ff0035fad06ee88a86e61a1e48419f89afed36e758"
RELEASES = {
    "fat95": (FAT95_LHA, FAT95_SHA256, "fat95/l/68020/fat95"),
    "lsfsres": (FAT95_LHA, FAT95_SHA256, "fat95/c/lsfsres"),
    "pfs3": (
        "https://github.com/pulchart/pfs3aio/releases/download/20261119-1/pfs3aio-20261119-1-020-gcc13",
        "7d42e1257752299572c0453394c04c6d5d37128abda6a0d454654db8e72a3761",
        None,
    ),
}
DEPS = ROOT / "build/deps"
PATH_KEYS = (*BUILDS, *RELEASES, "work")

STARTUP = """SetPatch >NIL:
FailAt 200
MakeDir RAM:T RAM:ENV
Assign >NIL: ENV: RAM:ENV
Assign >NIL: T: RAM:T
Echo "start" >OUT:log.txt
Copy OUT:cfd.prefs ENV:cfd.prefs
noreq
Execute OUT:steps
OUT:CFInfo >OUT:cfinfo.txt
Echo "DONE" >OUT:done
"""


def sh(*a, **k):
    return subprocess.run([str(x) for x in a], check=True, capture_output=True, **k)


def fetch(key):
    """A release file, downloaded once into build/deps and checked by SHA-256."""
    url, sha256, member = RELEASES[key]
    name = url.rsplit("/", 1)[1]
    dest = DEPS / (member or name)
    if not dest.exists():
        download = DEPS / name
        if not download.exists():
            data = urllib.request.urlopen(url).read()
            if hashlib.sha256(data).hexdigest() != sha256:
                sys.exit("%s: unexpected SHA-256" % url)
            DEPS.mkdir(parents=True, exist_ok=True)
            download.write_bytes(data)
        if member:
            sh("lha", "-xqw=%s" % DEPS, download)
    return dest


def prepare(cfg, osc, work):
    """The boot volume, a copy of the system directory; returns the FS-UAE
    lines that attach it."""
    sysdir = work / "boot"
    shutil.copytree(os.environ["AMIGA_SYSTEM"], sysdir, symlinks=True)
    subprocess.run(["chmod", "-R", "u+w", str(sysdir)], check=True)  # an ISO tree is read-only
    if not (sysdir / "C/Format").exists():  # AmigaOS keeps it in System/
        shutil.copyfile(sysdir / "System/Format", sysdir / "C/Format")
    payload = [
        (ROOT / "build/tools/noreq", "C/noreq"),
        (cfg["lsptres"], "C/lsptres"),
        (cfg["lsfsres"], "C/lsfsres"),
        (cfg["cfd"], "Devs/compactflash.device"),
        (cfg["ptable"], "Libs/ptable.library"),
        (cfg["fat95"], "L/fat95"),
    ]
    for src, dest in payload:
        shutil.copyfile(src, sysdir / dest)
    startup = STARTUP if osc.get("setpatch", True) else STARTUP.replace("SetPatch >NIL:\n", "")
    (sysdir / "S/Startup-Sequence").write_text(startup)
    return ["hard_drive_2 = %s" % sysdir, "hard_drive_2_label = Boot", "hard_drive_2_priority = 10"]


def ntfs_volume(path, sectors):
    """An NTFS boot sector, enough for a handler to tell the volume apart."""
    with path.open("r+b") as f:
        f.write(b"\xeb\x52\x90NTFS    " + (512).to_bytes(2, "little") + b"\x08")
        f.seek(0x28)
        f.write((sectors - 1).to_bytes(8, "little"))
        f.seek(510)
        f.write(b"\x55\xaa")


def mix_partition(path, fs, sectors, payload):
    path.unlink(missing_ok=True)
    if fs.startswith("fat"):
        bits = fs[3:]
        extra = ["-s", "1"] if bits == "32" else []
        sh("mkfs.fat", "-C", "-F", bits, *extra, "-n", fs.upper(), path, sectors // 2)
        tmp = path.with_suffix(".payload")
        tmp.write_bytes(payload)
        sh("mcopy", "-i", path, tmp, "::payload.bin")
        tmp.unlink()
        return
    with path.open("wb") as f:
        f.truncate(sectors * 512)
    if fs == "ntfs":
        ntfs_volume(path, sectors)
    else:
        sh("mkfs.exfat", "-L", "EXFAT", path)


def card_image(d, layout, payload, cfg):
    hdf = d / "cf.hdf"
    if layout == "rdb":
        cmd = ["rdbtool", "-f", str(hdf), "create", "size=64Mi", "+", "init", "rdb_cyls=32", "+",
               "fsadd", str(cfg["pfs3"]), "dostype=0x50465303"]  # fmt: skip
        for name, dostype, _ in RDB:
            cmd += [
                "+",
                "add",
                "name=%s" % name,
                "size=48%",
                "dostype=0x%08X" % dostype,
                "bs=512",
                "pri=-10",
            ]
        subprocess.run(cmd, check=True, capture_output=True)
        return hdf, []
    mix = layout.endswith("_mix")
    with hdf.open("wb") as f:
        f.truncate((MIX_SECTORS if mix else IMAGE_SECTORS) * 512)
    if layout == "mbr_mix":
        first = MIX[0]
        table = "label: dos\nstart=2048, size=%d, type=%x\ntype=f\n" % (
            first[1],
            first[2],
        ) + "".join("size=%d, type=%x\n" % (n, t) for _, n, t in MIX[1:])
    elif layout == "gpt_mix":
        table = "label: gpt\n" + "".join("size=%d, type=%s\n" % (n, GPT_FAT) for _, n, _ in MIX)
    else:
        table = "label: dos\nstart=2048, size=126976, type=6\n"
    subprocess.run(
        ["sfdisk", "-q", str(hdf)], input=table, text=True, check=True, capture_output=True
    )
    dump = sh("sfdisk", "-J", hdf, text=True).stdout
    parts = [(p["start"], p["size"]) for p in json.loads(dump)["partitiontable"]["partitions"]
             if str(p["type"]).lower() not in ("5", "f")]  # not the extended container  # fmt: skip
    fss = [m[0] for m in MIX] if mix else ["fat16"]
    for i, ((start, size), fs) in enumerate(zip(parts, fss, strict=True)):
        part = d / ("part%d.img" % i)
        mix_partition(part, fs, size, payload)
        sh(
            "dd",
            "if=%s" % part,
            "of=%s" % hdf,
            "bs=512",
            "seek=%d" % start,
            "conv=notrunc,sparse",
            "status=none",
        )
        part.unlink()
    return hdf, parts


def stop(p):
    for sig in (15, 9):  # FS-UAE can outlive SIGTERM once the guest hangs
        try:
            os.killpg(p.pid, sig)
        except ProcessLookupError:
            break
        time.sleep(3)
    p.wait()


class Result:
    def __init__(self, cfg, d, hdf, parts, payload, up):
        self.cfg, self.out, self.hdf, self.parts, self.payload, self.up = (
            cfg,
            d / "out",
            hdf,
            parts,
            payload,
            up,
        )
        self.serial = (d / "serial.txt").read_text(errors="replace")

    def text(self, name):
        p = self.out / name
        return p.read_text(errors="replace") if p.exists() else ""

    def got(self, n):
        p = self.out / ("got%d.bin" % n)
        return p.read_bytes() if p.exists() else None

    def image_file(self, name, part=0):
        r = subprocess.run(["mcopy", "-n", "-i", "%s@@%d" % (self.hdf, self.parts[part][0] * 512), "::" + name, "-"],
                           capture_output=True, env=dict(os.environ, MTOOLS_SKIP_CHECK="1"))  # fmt: skip
        return r.stdout if r.returncode == 0 else None

    def serial_order(self, *marks):
        pos = 0
        for m in marks:
            pos = self.serial.find(m, pos)
            if pos < 0:
                return False
        return True

    def devinfo(self, dev):
        for line in self.text("devinfo.txt").splitlines():
            f = line.split()
            if f and f[0].rstrip(":").upper() == dev and len(f) >= 4:
                try:
                    return int(f[2]), int(f[3])
                except ValueError:
                    pass
        return (None, None)


def emulate(cfg, d, cfgfile, name):
    """Run FS-UAE until the guest writes OUT:done or the limit passes. A start
    that dies or shows no sign of the guest by BOOT_LIMIT is tried once more:
    FS-UAE and Xvfb now and then fail to come up. Returns (in time, seconds)."""
    out = d / "out"
    env = dict(
        os.environ, XDG_RUNTIME_DIR=str(d / "xdg"), SDL_VIDEODRIVER="x11", SDL_AUDIODRIVER="dummy"
    )
    env.pop("WAYLAND_DISPLAY", None)
    limit = cfg["limit"]
    for attempt in (1, 2):
        with (d / "fsuae.log").open("a") as emu:
            p = subprocess.Popen(["xvfb-run", "-a", cfg["fsuae"], str(cfgfile)], env=env, stdout=emu,
                                 stderr=subprocess.STDOUT, start_new_session=True)  # fmt: skip
            t0 = time.monotonic()
            try:
                while (
                    time.monotonic() - t0 < limit
                    and p.poll() is None
                    and not (out / "done").exists()
                ):
                    if time.monotonic() - t0 > BOOT_LIMIT and not (out / "log.txt").exists():
                        break
                    time.sleep(1)
                took = time.monotonic() - t0
                in_time = (out / "done").exists() and took <= limit
                if in_time:
                    time.sleep(1)  # let the last host write land
            finally:
                stop(p)
        if (out / "log.txt").exists():
            return in_time, took
        if attempt == 1:
            print("  %s: the guest did not start, starting FS-UAE again" % name)
    return False, took


def run(cfg, osname, osc, boot, work, name, sc):
    d = work / name
    for sub in ("out", "xdg", "base"):
        (d / sub).mkdir(parents=True)
    out = d / "out"
    payload, up = os.urandom(300000), os.urandom(70000)
    hdf, parts = card_image(d, sc.get("layout", "mbr"), payload, cfg)
    (out / "up.bin").write_bytes(up)
    prefs = dict(BASE_PREFS, **osc.get("prefs", {}), **sc.get("prefs", {}))
    (out / "cfd.prefs").write_text("".join("%s %s\n" % kv for kv in prefs.items()))
    (out / "yes").write_text("y\ny\ny\n\n\n")
    for tool in GUEST_TOOLS:
        shutil.copyfile(tool, out / tool.name)
    shutil.copyfile(cfg["cfinfo"], out / "CFInfo")
    if "mountlist" in sc:
        (out / sc["mountlist"]).write_text(CF0_MOUNTLIST.format(name=sc["mountlist"]))
    (out / "steps").write_text(sc["steps"].format(wait=cfg["wait"]))
    serial = d / "serial.txt"
    serial.touch()
    rom, ext = os.environ["AMIGA_KICKSTART"], os.environ.get("AMIGA_KICKSTART_EXT")
    lines = (
        ["[fs-uae]", "amiga_model = A1200", "cpu = %s" % osc.get("cpu", "68020"), "chip_memory = 2048",
         "fast_memory = 4096", "kickstart_file = %s" % rom]
        + (["kickstart_ext_file = %s" % ext] if ext else [])
        + boot + list(osc.get("fsuae", []))
        + ["hard_drive_0 = %s" % out, "hard_drive_0_label = OUT", "hard_drive_0_priority = -128",
           "hard_drive_1 = %s" % hdf, "hard_drive_1_type = hdf", "hard_drive_1_controller = scide",
           "uae_pcmcia = true", "serial_port = %s" % serial, "joystick_port_1 = none", "uae_cpu_speed = max",
           "fullscreen = 0", "base_dir = %s" % (d / "base"), ""]
    )  # fmt: skip
    cfgfile = d / "run.fs-uae"
    cfgfile.write_text("\n".join(lines))
    in_time, took = emulate(cfg, d, cfgfile, name)
    r = Result(cfg, d, hdf, parts, payload, up)
    checks = [("finished in time", in_time), *sc["checks"](r)]
    print("== %s %s: %s" % (osname, name, sc["doc"]))
    for what, ok in checks:
        print("  %-48s %s" % (what, "ok" if ok else "FAIL"))
    passed = all(ok for _, ok in checks)
    print("  %s in %.0f s, %s" % ("PASS" if passed else "FAIL", took, d))
    return passed


def resolve(value):
    """A config path: absolute as given, relative from the repository root."""
    p = Path(value).expanduser()
    return p if p.is_absolute() else ROOT / p


def load_config(path):
    cfg = {"fsuae": "fs-uae", "wait": 10, "limit": 180, "work": "build/integration"}
    cfg.update(BUILDS)
    cfg.update(yaml.safe_load(path.read_text()) or {})
    if "os" not in cfg:
        sys.exit("%s lacks os" % path)
    for k in PATH_KEYS:
        if k in cfg:
            cfg[k] = resolve(cfg[k])
    return cfg


def shown(p):
    """A path relative to the repository root when it is near it."""
    try:
        return os.path.relpath(p, ROOT) if p.is_relative_to(ROOT.parent) else str(p)
    except ValueError:
        return str(p)


def main():
    sys.stdout.reconfigure(line_buffering=True)  # progress shows up in a log file
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument(
        "--config", type=Path, default=Path(os.environ.get("CFD_IT_CONFIG", HERE / "config.yaml"))
    )
    ap.add_argument("--os", help="OS profile of the config")
    ap.add_argument(
        "--scenario", action="append", choices=sorted(SCENARIOS), help="run only these (repeatable)"
    )
    ap.add_argument("--list", action="store_true", help="list the scenarios and exit")
    ap.add_argument(
        "--work",
        type=Path,
        help="new directory for the run (default: a new one under the config's work)",
    )
    a = ap.parse_args()
    if a.list:
        for name, s in SCENARIOS.items():
            print("%-18s %s" % (name, s["doc"]))
        return
    cfg = load_config(a.config)
    if a.os not in cfg["os"]:
        sys.exit("--os: one of %s" % ", ".join(cfg["os"]))
    osc = cfg["os"][a.os] or {}
    unset = [v for v in ("AMIGA_SYSTEM", "AMIGA_KICKSTART") if not os.environ.get(v)]
    if unset:
        sys.exit("%s not set: run in an amiga-fsuae OS image" % " and ".join(unset))
    for k in RELEASES:
        if k not in cfg:
            cfg[k] = fetch(k)
    builds = [cfg[k] for k in (*BUILDS, *RELEASES) if not cfg[k].exists()]
    builds += [p for p in GUEST_TOOLS if not p.exists()]
    if builds:
        sys.exit("missing builds: %s" % ", ".join(map(shown, builds)))
    # a fat95 with exFAT carries the boot sector signature; the mixed cards then expect exFAT to mount
    cfg["fat95_exfat"] = b"EXFAT   " in cfg["fat95"].read_bytes()
    names = a.scenario or list(SCENARIOS)
    work = (a.work or cfg["work"] / time.strftime("cfd-it-%Y%m%d-%H%M%S")).resolve()
    if work.exists():
        sys.exit("%s exists; give a new --work directory" % work)
    work.mkdir(parents=True)
    print("%s: %s" % (a.os, " ".join(names)))
    print(
        "  fat95 %s: exFAT partitions %s"
        % (shown(cfg["fat95"]), "mount" if cfg["fat95_exfat"] else "refused")
    )
    boot = prepare(cfg, osc, work)
    failed = [n for n in names if not run(cfg, a.os, osc, boot, work, n, SCENARIOS[n])]
    print(
        "%s: %d/%d scenarios passed%s"
        % (
            a.os,
            len(names) - len(failed),
            len(names),
            "; failed: " + ", ".join(failed) if failed else "",
        )
    )
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
