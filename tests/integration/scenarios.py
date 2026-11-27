"""Scenarios for run.py, read from scenarios.yaml, and the check sets they
name. A check set gets the Result of a run and returns (description, ok)
pairs: on what the guest wrote to OUT:, the serial log and the card image."""

import re
from pathlib import Path

import yaml

BASE_PREFS = {"AUTOMOUNT": "1", "FLAGS": "8", "CONTROL_FAT": "-d-D+q", "HANDLER_FAT": "L:fat95"}

CF0_MOUNTLIST = """{name}:
FileSystem = L:fat95
Device = compactflash.device
Unit = 0
Flags = 0
LowCyl = 0
HighCyl = 0
Surfaces = 1
BlocksPerTrack = 1
BlockSize = 512
Buffers = 20
BufMemType = 1
BootPri = 0
Stacksize = 4096
Priority = 5
GlobVec = -1
DosType = 0x46415401
#
"""

# fs, sectors, MBR type: a mixed card, one partition per file system
MIX = [("fat12", 16384, 0x01), ("fat16", 49152, 0x06), ("fat32", 81920, 0x0C),
       ("ntfs", 16384, 0x07), ("exfat", 32768, 0x07)]  # fmt: skip
# every CFn: that exists: read the payload, write a file, read it back;
# logical MBR partitions are named from CF4
MIX_IO = (
    "".join(
        "Copy CF%d:payload.bin OUT:got%d.bin\nCopy OUT:up.bin CF%d:up.bin\nCopy CF%d:up.bin OUT:back%d.bin\n"
        % (n, n, n, n, n)
        for n in range(10)
    )
    + "Wait 5\n"
)

# name, DosType, label: an RDB card with one partition per Amiga file system;
# PFS3 comes from the RDB, FFS from the ROM
RDB = [("CFF", 0x444F5303, "FFSVOL"), ("CFP", 0x50465303, "PFSVOL")]
# formatted in the guest, so the handlers write their own structures; Format
# asks before it starts, answered from OUT:yes
RDB_IO = (
    "".join(
        "Format DRIVE %s: NAME %s%s QUICK NOICONS <OUT:yes >OUT:fmt%d.txt\n"
        % (n, label, " FFS" if n == "CFF" else "", i)
        for i, (n, _, label) in enumerate(RDB)
    )
    + "Wait 3\nInfo >OUT:info1.txt\n"
    + "".join(
        "Copy OUT:up.bin %s:up.bin\nCopy %s:up.bin OUT:back%d.bin\n" % (n, n, i)
        for i, (n, _, _) in enumerate(RDB)
    )
    + "Wait 5\n"
)


def volume_line(lines, dev):
    """Info lists a device as "CF0 " (3.2) or "CF0:" (3.1, AROS)."""
    return next((line for line in lines if line.startswith((dev + " ", dev + ":"))), "")


def info_has(r, n, dev):
    return "read/write" in volume_line(r.text("info%d.txt" % n).splitlines(), dev).lower()


def pt_row(r, n, dev):
    return next(
        (line for line in r.text("pt%d.txt" % n).splitlines() if line.split()[:1] == [dev]), ""
    )


def read_ok(r, n):
    return r.got(n) == r.payload


def automount(r):
    return [
        ("CF0: mounted", info_has(r, 0, "CF0")),
        ("lsptres: present and mounted", " P--M- " in pt_row(r, 0, "CF0")),
        ("CONTROL_FAT on the row", "-d-D+q" in pt_row(r, 0, "CF0")),
        ("payload read back", read_ok(r, 0)),
        ("written file on the image", r.image_file("up.bin") == r.up),
    ]


def automount_off(r):
    return [
        ("CF0: not mounted", not info_has(r, 0, "CF0")),
        ("no mount in lsptres", "M-" not in pt_row(r, 0, "CF0")),
    ]


def static(r):
    return [("CF0: mounted by hand", info_has(r, 0, "CF0")), ("payload read back", read_ok(r, 0))]


def static_in_use(r):
    return [
        ("CF0: automounted", info_has(r, 0, "CF0")),
        ("CFX: refused, object in use", "in use" in r.text("listx.txt").lower()),
        ("CF0: still reads", read_ok(r, 0)),
    ]


def static_mount_used(r):
    return [
        ("CF0: automounted", info_has(r, 0, "CF0")),
        ("CFX: lists the payload", "payload.bin" in r.text("listx.txt").lower()),
    ]


def handler_params(r):
    return [
        ("CF0: mounted", info_has(r, 0, "CF0")),
        ("DosType 0x46415401", "0x46415401" in pt_row(r, 0, "CF0")),
        ("node priority 3, stack 16384", r.devinfo("CF0") == (3, 16384)),
    ]


def swap(r):
    order = ("[CFD] Card removed", "[PT] card removed", "[CFD] Card inserted", "..RESULT: accept")
    return [
        ("removal then insertion in the serial log", r.serial_order(*order)),
        ("CF0: mounted after the swap", info_has(r, 1, "CF0")),
        ("lsptres: present and mounted", " P--M- " in pt_row(r, 1, "CF0")),
        ("payload read back after the swap", read_ok(r, 1)),
        ("written file on the image", r.image_file("up.bin") == r.up),
    ]


def swap_open(r):
    held = r.out / "held.bin"
    return [
        *swap(r),
        (
            "held file reads back through its handle",
            held.exists() and held.read_bytes() == r.payload,
        ),
    ]


def mix(r, source):
    """Each partition of a mixed card is published; FAT mounts, reads and
    writes; NTFS is refused; exFAT mounts with a fat95 that has it and is refused
    otherwise."""
    rows = {}
    for line in r.text("pt0.txt").splitlines():
        f = line.split()
        if f and f[0].startswith("CF") and len(f) > 4 and f[4] == source:
            if not re.match(r"^\d+[KMGT]?$", f[-1]):
                f = f[:-1]  # newer lsptres: the FS the handler found
            rows[int(f[-3])] = f[0]
    info = r.text("info0.txt").splitlines()
    refused = {"ntfs"} | (set() if r.cfg.get("fat95_exfat") else {"exfat"})
    out = []
    for i, ((fs, _, _), (start, _)) in enumerate(zip(MIX, r.parts, strict=True)):
        name = rows.get(start)
        out.append(("%s published as %s" % (fs, name or "-"), name is not None))
        if name is None:
            continue
        n = int(name[2:])
        mounted = "read/write" in volume_line(info, name).lower()
        if fs in refused:
            out.append(("%s refused by fat95" % fs, not mounted))
            continue
        out.append(("%s mounted" % fs, mounted))
        if fs.startswith("fat"):
            out.append(("%s payload read back" % fs, r.got(n) == r.payload))
        back = r.out / ("back%d.bin" % n)
        out.append(("%s written file reads back" % fs, back.exists() and back.read_bytes() == r.up))
        if fs.startswith("fat"):
            out.append(("%s written file on the image" % fs, r.image_file("up.bin", i) == r.up))
    return out


def rdb(r):
    names = [n for n, _, _ in RDB]
    rows = {
        line.split()[0]: line
        for line in r.text("pt0.txt").splitlines()
        if line.split()[:1] and line.split()[0] in names
    }
    fsres = r.text("fsres.txt").lower()
    info = r.text("info1.txt").splitlines()
    out = [("PFS3 handler loaded from the RDB", "50465303" in fsres)]
    for i, (name, dostype, label) in enumerate(RDB):
        row = rows.get(name, "")
        out.append(("%s published from the RDB, DosType 0x%08X" % (name, dostype),
                    " RDB " in row and ("%08X" % dostype) in row.upper()))  # fmt: skip
        out.append(("%s formatted and mounted as %s" % (name, label),
                    "read/write" in volume_line(info, name).lower() and label in volume_line(info, name)))  # fmt: skip
        back = r.out / ("back%d.bin" % i)
        out.append(
            ("%s written file reads back" % name, back.exists() and back.read_bytes() == r.up)
        )
    return out


CHECKS = {
    "automount": automount,
    "automount_off": automount_off,
    "static": static,
    "static_in_use": static_in_use,
    "static_mount_used": static_mount_used,
    "handler_params": handler_params,
    "swap": swap,
    "swap_open": swap_open,
    "rdb": rdb,
    "mbr_mix": lambda r: mix(r, "MBR"),
    "gpt_mix": lambda r: mix(r, "GPT"),
}


def load(path):
    data = yaml.safe_load(path.read_text())
    fragments = dict(data["fragments"], mix_io=MIX_IO, rdb_io=RDB_IO)
    out = {}
    for name, s in data["scenarios"].items():
        unknown = [f for f in s["steps"] if f not in fragments]
        if unknown or s["checks"] not in CHECKS:
            raise SystemExit("%s: %s: unknown %s" % (path, name, ", ".join(unknown) or s["checks"]))
        sc = dict(s)
        sc["steps"] = "".join(fragments[f] for f in s["steps"])
        sc["checks"] = CHECKS[s["checks"]]
        sc["prefs"] = {k: str(v) for k, v in s.get("prefs", {}).items()}
        out[name] = sc
    return out


SCENARIOS = load(Path(__file__).resolve().parent / "scenarios.yaml")
