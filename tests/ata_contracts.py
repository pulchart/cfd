"""ATA I/O dispatch, config bounds, geometry and media notifications.

Status: gated, run by make test on both CPUs and build flavors.
Run: python3 tests/ata_contracts.py"""
import re
import struct
import subprocess
import tempfile
from pathlib import Path
from amitools.binfmt.BinFmt import BinFmt
from amitools.binfmt.Relocate import Relocate
from amitools.vamos.machine import Machine
from toolchain import PTABLE_SRC, ROOT, VASM

BASE, UNIT, DEV, REQ, BUF, EXEC, CALLBACK, STACK = (
    0x10000, 0x40000, 0x42000, 0x44000, 0x50000, 0x70000, 0x71000, 0x90000)


def build(directory, cpu, full):
    out, listing = directory / 'cfd', directory / 'cfd.lst'
    flags = (['-D__68020__=1'] if cpu == '68020' else []) + (['-DDEBUG=1'] if full else [])
    subprocess.run([VASM, '-quiet', '-Fhunkexe', '-m'+cpu, *flags,
                    '-I', str(PTABLE_SRC), '-L', str(listing), '-o', str(out),
                    'src/cfd.s'], cwd=ROOT, check=True)
    eq = {name: int(value, 16) for name, value in re.findall(
        r'^([A-Za-z_][\w]*)\s+E:([0-9A-Fa-f]{8})\s*$', listing.read_text(), re.MULTILINE)}
    return BinFmt().load_image(str(out)), eq


class Device:
    def __init__(self, image, eq, cpu):
        self.eq, self.events = eq, []
        self.m = Machine.from_name(cpu, ram_size=2048)
        self.cpu, self.mem = self.m.get_cpu(), self.m.get_mem()
        self.mem.w_block(BASE, bytes(Relocate(image).relocate_one_block(BASE)))
        self.sym = {s.name.decode(): BASE+s.offset for s in image.get_segments()[0].get_symtab().get_symbols()}
        self.mem.w32(DEV+eq['CFD_ExecBase'], EXEC)
        for name, value, width in (('CFU_DriveSize', 12345, 4), ('CFU_BlockSize', 512, 4),
                                   ('CFU_BlockShift', 9, 2), ('CFU_CardReady', 1, 2)):
            getattr(self.mem, 'w'+str(width*8))(UNIT+eq[name], value)

    def trap(self, address, callback):
        tid = self.m.get_traps().alloc(lambda op, pc: callback())
        self.mem.w16(address, 0xa000 | tid)
        self.mem.w16(address+2, 0x4e75)

    def run(self, name):
        for r in range(15): self.cpu.w_reg(r, 0x123400+r)
        self.cpu.w_reg(10, REQ); self.cpu.w_reg(11, UNIT); self.cpu.w_reg(12, DEV)
        self.m.prepare(self.sym[name], STACK)
        result = self.m.execute(200000)
        assert self.m.was_exit(result), name+' did not return'
        assert self.cpu.r_sp() == STACK, name+' changed stack'
        return self.cpu.r_reg(0)

    def close(self): self.m.cleanup()


def check_io(d, name, offset, length):
    def transfer():
        d.events.append((d.cpu.r_reg(0), d.cpu.r_reg(1), d.cpu.r_reg(9)))
        d.cpu.w_reg(0, d.cpu.r_reg(1))
    target = '_ReadBlocks' if name.startswith('_Read') else '_WB2'
    d.trap(d.sym[target], transfer)
    d.mem.w32(REQ+32, offset >> 32); d.mem.w32(REQ+44, offset & 0xffffffff)
    d.mem.w32(REQ+36, length); d.mem.w32(REQ+40, BUF)
    result = d.run(name)
    lba = (offset if name.endswith('64') else offset & 0xffffffff) // 512
    assert d.events == [(lba, length//512, BUF)], (name, d.events)
    assert d.mem.r32(REQ+32) == length//512*512
    assert result & 255 == 0
    for r in (2, 3, 4, 5, 6, 7, 13): assert d.cpu.r_reg(r) == 0x123400+r


def check_config(d, length, null):
    e = d.eq
    for name, value, width in (('CFU_OpenFlags', 0x1234, 2), ('CFU_MultiSize', 16, 2),
                               ('CFU_MultiSizeRW', 256, 2), ('CFU_ReceiveMode', 3, 1),
                               ('CFU_WriteMode', 2, 1)):
        getattr(d.mem, 'w'+str(width*8))(UNIT+e[name], value)
    d.mem.w_block(BUF-16, b'\xa5'*96)
    d.mem.w32(REQ, 0 if null else BUF); d.mem.w32(REQ+4, length); d.mem.w32(REQ+8, 0xdeadbeef)
    assert d.run('_CFDGetConfig') == 0
    assert e['CFD_CONFIG_SIZE'] == 12
    payload = struct.pack('>HBBHHHBB', 12, e['FILE_VERSION'], e['FILE_REVISION'], 0x1234, 16, 256, 3, 2)
    count = 0 if null else min(length, 12)
    assert bytes(d.mem.r_block(BUF, count)) == payload[:count]
    assert bytes(d.mem.r_block(BUF+count, 64-count)) == b'\xa5'*(64-count)
    assert bytes(d.mem.r_block(BUF-16, 16)) == b'\xa5'*16
    assert d.mem.r32(REQ+8) == (count or 0xdeadbeef)


def check_geometry(d, length):
    d.mem.w16(UNIT+d.eq['CFU_ConfigBlock']+12, 63)
    d.mem.w16(UNIT+d.eq['CFU_ConfigBlock']+6, 16)
    d.mem.w32(REQ+36, length); d.mem.w32(REQ+40, BUF)
    result = d.run('_GetGeometry')
    if length != 32:
        assert result & 255 == 0xfc
    else:
        assert result == 0 and d.mem.r32(REQ+32) == 32
        assert bytes(d.mem.r_block(BUF, 32)) == struct.pack('>7IBBH', 512, 12345, 12, 1008, 16, 63, 1, 0, 1, 0)


def check_media(d, size):
    d.mem.w32(UNIT+d.eq['CFU_DriveSize'], size)
    assert d.run('_ChangeState') == 0
    assert d.mem.r32(REQ+32) == (0 if size else 1)


def check_notify(d, valid):
    head = UNIT+d.eq['CFU_Clients']
    d.mem.w32(head, REQ); d.mem.w32(head+4, 0); d.mem.w32(head+8, REQ)
    d.mem.w32(REQ, head+4); d.mem.w32(REQ+4, head)
    d.mem.w32(REQ+40, BUF if valid else 0)
    d.mem.w32(BUF+d.eq['IS_Code'], CALLBACK); d.mem.w32(BUF+d.eq['IS_Data'], BUF+64)
    for name, offset in (('Forbid', -132), ('Permit', -138), ('Remove', -252)):
        d.trap(EXEC+offset, lambda name=name: d.events.append(name))
    d.trap(CALLBACK, lambda: d.events.append(('notify', d.cpu.r_reg(9))))
    d.run('NotifyClients')
    assert d.events == ['Forbid', ('notify', BUF+64) if valid else 'Remove', 'Permit']


def main():
    with tempfile.TemporaryDirectory() as temp:
        for cpu in ('68000', '68020'):
            for full in (False, True):
                image, eq = build(Path(temp), cpu, full)
                cases = [(check_io, (name, offset, length))
                         for name in ('_Read', '_Read64', '_Write', '_Write64')
                         for offset, length in ((0, 0), (0, 512), (512, 2048), (513, 1025), ((1<<32)+512, 512))]
                cases += [(check_config, (length, null)) for length in (*range(14), 64) for null in (False, True)]
                cases += [(check_geometry, (length,)) for length in (0, 32)]
                cases += [(check_media, (size,)) for size in (0, 12345)]
                cases += [(check_notify, (valid,)) for valid in (False, True)]
                for function, args in cases:
                    d = Device(image, eq, cpu)
                    try: function(d, *args)
                    finally: d.close()
                print(cpu, 'full' if full else 'small', len(cases), 'ATA cases passed')


if __name__ == '__main__': main()
