#!/usr/bin/env python3
"""compactflash.device, ptable.library and fat95 under AmigaOS on an
emulated PCMCIA IDE card (FS-UAE, A1200).

    run.py [--config FILE] [--os NAME ...] [--scenario NAME ...] [--list] [--work DIR]

Preparation builds a boot disk from the AmigaOS disks named in the config
(C: commands, Format) with the driver set and the test tools on it. Each
scenario then gets its own card image, cfd.prefs and steps; the guest writes
its findings to the host directory OUT:, and the host checks them, the serial
log (FLAGS 8) and the image. Exit 0 when every scenario that ran passes; an
OS whose files are missing is skipped.

FS-UAE needs: controller scide with pcmcia on, Fast RAM at most
4 MB (8 MB Zorro II overlaps the PCMCIA window and card.resource stays off),
HANDLER_FAT in cfd.prefs, and a read-only boot disk. A swap is the Gayle
disable bit set and cleared from the guest; card.resource re-enables the slot
at once, so a card cannot stay out and the UNMOUNT policies are not covered.
UAE generates its own card CIS, so CIS routing is not covered either.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

import yaml
from scenarios import BASE_PREFS, CF0_MOUNTLIST, MIX, RDB, SCENARIOS

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent  # relative paths in the config start here
IMAGE_SECTORS = 131072  # 64 MB card
MIX_SECTORS = 245760  # 120 MB card for the mixed layouts
BOOT_LIMIT = 60  # seconds to the first line in OUT:log.txt
GPT_FAT = "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7"

PATH_KEYS = ("cfd", "ptable", "lsptres", "fat95", "lsfsres", "pfs3", "work")
OS_PATH_KEYS = ("kickstart", "kickstart_ext", "commands_adf", "workbench_adf")
# guest tools built by make (tools/*.c)
GUEST_TOOLS = [ROOT / "build/tools" / n for n in ("devinfo", "holdfile")]

# C: commands the steps use, taken from the OS disks for an AmigaOS boot disk
COMMANDS = ["Assign", "Copy", "Delete", "DiskChange", "Execute", "Info", "List",
            "MakeDir", "Mount", "SetPatch", "Version", "Wait"]  # fmt: skip

# small guest tools, assembled with vasm during preparation
TOOLS = {
    # the Gayle PCMCIA disable bit: set, FS-UAE drops card detect; cleared, it
    # raises it again. Together they are a swap of the same card.
    "cardout": "\tmove.b\t$da8000,d0\n\tor.b\t#1,d0\n\tmove.b\td0,$da8000\n",
    "cardin": "\tmove.b\t$da8000,d0\n\tand.b\t#$fe,d0\n\tmove.b\td0,$da8000\n",
    # pr_WindowPtr -1 for the shell process: a missing volume is an error,
    # not a requester that waits forever
    "noreq": "\tmove.l\t4.w,a6\n\tsub.l\ta1,a1\n\tjsr\t-294(a6)\n\tmove.l\td0,a0\n\tmoveq\t#-1,d0\n\tmove.l\td0,184(a0)\n",
}

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


def adf_read(adf, path, dest):
    """Read path from an ADF; a compressed update file (name.Z) is unpacked."""
    for name in (path, path + ".Z"):
        r = subprocess.run(["xdftool", str(adf), "read", name, str(dest)], capture_output=True)
        if r.returncode == 0 and dest.exists():
            if name.endswith(".Z"):
                data = subprocess.run(["gzip", "-dc", str(dest)], capture_output=True, check=True)
                dest.write_bytes(data.stdout)
            return True
    return False


def tools(cfg, work):
    """Guest tools, built once for every OS."""
    prep = work / "tools"
    files = prep / "files"
    files.mkdir(parents=True)
    for name, src in TOOLS.items():
        s = prep / (name + ".s")
        s.write_text(src + "\tmoveq\t#0,d0\n\trts\n")
        sh(cfg["vasm"], "-quiet", "-Fhunkexe", "-o", files / name, s)
    for p in GUEST_TOOLS:
        shutil.copyfile(p, files / p.name)
    return files


def payload_files(cfg, files):
    """What the boot medium carries besides the OS: tools, modules, handler."""
    return [
        (files / "noreq", "C/noreq"),
        (cfg["lsptres"], "C/lsptres"),
        (cfg["lsfsres"], "C/lsfsres"),
        (cfg["cfd"] / "dist/full/68020/devs/compactflash.device", "Devs/compactflash.device"),
        (cfg["ptable"], "Libs/ptable.library"),
        (cfg["fat95"], "L/fat95"),
    ]


def prepare(cfg, osname, osc, files, work):
    """The boot disk for one OS, built from the OS disks. Returns FS-UAE lines."""
    prep = work / osname / "boot"
    prep.mkdir(parents=True)
    adf = prep / "boot.adf"
    sh("xdftool", adf, "create", "+", "format", "TestBoot", "DOS3", "+", "boot", "install")
    for d in ("C", "S", "L", "Libs", "Devs"):
        sh("xdftool", adf, "makedir", d)
    for cmd in COMMANDS:
        dest = prep / cmd
        if not any(adf_read(src, "C/" + cmd, dest) for src in osc["commands_adf"]):
            sys.exit("C/%s is on none of %s" % (cmd, ", ".join(map(str, osc["commands_adf"]))))
        sh("xdftool", adf, "write", dest, "C/" + cmd)
    if not adf_read(osc["workbench_adf"], "System/Format", prep / "Format"):
        sys.exit("System/Format is not on %s" % osc["workbench_adf"])
    for src, dest in [*payload_files(cfg, files), (prep / "Format", "C/Format")]:
        sh("xdftool", adf, "write", src, dest)
    (prep / "startup").write_text(STARTUP)
    sh("xdftool", adf, "write", prep / "startup", "S/Startup-Sequence")
    return ["floppy_drive_0 = %s" % adf, "writable_floppy_images = 0"]


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
        sh("mkntfs", "-F", "-Q", "-q", "-s", "512", "-L", "NTFS", path)
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


def run(cfg, osname, osc, boot, files, work, name, sc):
    d = work / osname / name
    for sub in ("out", "xdg", "base"):
        (d / sub).mkdir(parents=True)
    out = d / "out"
    payload, up = os.urandom(300000), os.urandom(70000)
    hdf, parts = card_image(d, sc.get("layout", "mbr"), payload, cfg)
    (out / "up.bin").write_bytes(up)
    prefs = dict(BASE_PREFS, **sc.get("prefs", {}))
    (out / "cfd.prefs").write_text("".join("%s %s\n" % kv for kv in prefs.items()))
    (out / "yes").write_text("y\ny\ny\n\n\n")
    for tool in ("cardout", "cardin", *(p.name for p in GUEST_TOOLS)):
        shutil.copyfile(files / tool, out / tool)
    shutil.copyfile(cfg["cfd"] / "dist/c/CFInfo", out / "CFInfo")
    if "mountlist" in sc:
        (out / sc["mountlist"]).write_text(CF0_MOUNTLIST.format(name=sc["mountlist"]))
    (out / "steps").write_text(sc["steps"].format(wait=cfg["wait"]))
    serial = d / "serial.txt"
    serial.touch()
    rom = str(osc["kickstart"])
    ext = osc.get("kickstart_ext") or (rom[:-2] + "E0" if rom.endswith(".F8") else None)
    lines = (
        ["[fs-uae]", "amiga_model = A1200", "cpu = %s" % osc.get("cpu", "68020"), "chip_memory = 2048",
         "fast_memory = 4096", "kickstart_file = %s" % rom]
        + (["kickstart_ext_file = %s" % ext] if ext else [])
        + boot + list(osc.get("fsuae", []))
        + ["hard_drive_0 = %s" % out, "hard_drive_0_label = OUT", "hard_drive_0_priority = -128",
           "hard_drive_1 = %s" % hdf, "hard_drive_1_type = hdf", "hard_drive_1_controller = scide",
           "uae_pcmcia = true", "serial_port = %s" % serial, "joystick_port_1 = none", "uae_cpu_speed = max",
           "floppy_drive_speed = 800", "fullscreen = 0", "base_dir = %s" % (d / "base"), ""]
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
    if isinstance(value, list):
        return [resolve(v) for v in value]
    p = Path(value).expanduser()
    return p if p.is_absolute() else ROOT / p


def load_config(path):
    cfg = {"fsuae": "fs-uae", "vasm": "vasmm68k_mot", "wait": 10, "limit": 180,
           "work": "build/integration", "cfd": "."}  # fmt: skip
    cfg.update(yaml.safe_load(path.read_text()) or {})
    missing = [k for k in ("os", "ptable", "lsptres", "fat95", "lsfsres", "pfs3") if k not in cfg]
    for name, osc in (cfg.get("os") or {}).items():
        missing += [
            "os %s: %s" % (name, k)
            for k in ("kickstart", "commands_adf", "workbench_adf")
            if k not in osc
        ]
    if missing:
        sys.exit("%s lacks %s" % (path, ", ".join(missing)))
    for k in PATH_KEYS:
        cfg[k] = resolve(cfg[k])
    # a fat95 with exFAT carries the boot sector signature; the mixed cards then expect exFAT to mount
    cfg["fat95_exfat"] = cfg["fat95"].exists() and b"EXFAT   " in cfg["fat95"].read_bytes()
    for osc in cfg["os"].values():
        if isinstance(osc.get("commands_adf"), str):
            osc["commands_adf"] = [osc["commands_adf"]]
        for k in OS_PATH_KEYS:
            if k in osc:
                osc[k] = resolve(osc[k])
    return cfg


def os_missing(osc):
    """The OS files of a profile that are not there."""
    paths = [osc[k] for k in ("kickstart", "kickstart_ext", "workbench_adf") if k in osc]
    return [p for p in paths + osc["commands_adf"] if not p.exists()]


def shown(p):
    """A path relative to the repository root when it is near it."""
    return os.path.relpath(p, ROOT) if p.is_relative_to(ROOT.parent) else str(p)


def main():
    sys.stdout.reconfigure(line_buffering=True)  # progress shows up in a log file
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument(
        "--config", type=Path, default=Path(os.environ.get("CFD_IT_CONFIG", HERE / "config.yaml"))
    )
    ap.add_argument("--os", action="append", help="run on these configured OSes only (repeatable)")
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
    builds = [
        cfg[k] for k in ("ptable", "lsptres", "fat95", "lsfsres", "pfs3") if not cfg[k].exists()
    ]
    builds += [p for p in (cfg["cfd"] / "dist/full/68020/devs/compactflash.device", cfg["cfd"] / "dist/c/CFInfo",
                           *GUEST_TOOLS) if not p.exists()]  # fmt: skip
    if builds:
        sys.exit("missing builds: %s" % ", ".join(map(shown, builds)))
    oses = a.os or list(cfg["os"])
    unknown = [o for o in oses if o not in cfg["os"]]
    if unknown:
        sys.exit("not in the config: %s" % ", ".join(unknown))
    names = a.scenario or list(SCENARIOS)
    plan, skipped = [], []
    print("plan:")
    print(
        "  fat95 %s: exFAT partitions %s"
        % (shown(cfg["fat95"]), "mount" if cfg["fat95_exfat"] else "refused")
    )
    for osname in oses:
        osc = cfg["os"][osname]
        gone = os_missing(osc)
        if gone:
            skipped.append(osname)
            print("  %-13s skip: %s not found" % (osname, ", ".join(map(shown, gone))))
        else:
            plan.append((osname, osc))
            print("  %-13s %s" % (osname, " ".join(names)))
    work = (a.work or cfg["work"] / time.strftime("cfd-it-%Y%m%d-%H%M%S")).resolve()
    if work.exists():
        sys.exit("%s exists; give a new --work directory" % work)
    work.mkdir(parents=True)
    files = tools(cfg, work)
    failed, total = [], 0
    for osname, osc in plan:
        boot = prepare(cfg, osname, osc, files, work)
        for n in names:
            total += 1
            if not run(cfg, osname, osc, boot, files, work, n, SCENARIOS[n]):
                failed.append("%s %s" % (osname, n))
    print(
        "%d/%d scenarios passed%s%s"
        % (
            total - len(failed),
            total,
            "; failed: " + ", ".join(failed) if failed else "",
            "; skipped: " + ", ".join(skipped) if skipped else "",
        )
    )
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
