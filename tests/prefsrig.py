"""Shared rig for the cfd.prefs tests: build cfd.s with a listing, run
_mwReadConfig against mocked exec and dos.library calls.

dos.library follows the NDK GetVar contract (-1 means undefined, 0 is a valid
empty value, V37+ returns characters copied). The config frame is filled with
$55 before the run, so a field the parser does not set reads as garbage."""
import re,subprocess
from amitools.binfmt.BinFmt import BinFmt
from amitools.binfmt.Relocate import Relocate
from amitools.vamos.machine import Machine
from toolchain import PTABLE_SRC, ROOT, VASM
BASE,UNIT,DEV,CFG,EXEC,DOSB,STACK=0x10000,0x100000,0x140000,0x200000,0x280000,0x2c0000,0x300000
LVO_OPENLIB,LVO_CLOSELIB=552,414
LVO_OPEN,LVO_CLOSE,LVO_READ,LVO_DELAY,LVO_GETVAR=30,36,42,198,906
ENVARC,ARCHIVE='ENVARC:cfd.prefs','SYS:Prefs/Env-Archive/cfd.prefs'

def build(tmp,need=()):
    obj=tmp/'cfd'; lst=tmp/'cfd.lst'
    subprocess.run([VASM,'-quiet','-Fhunkexe','-m68000','-DDEBUG=1',
                    '-I',str(PTABLE_SRC),'-L',str(lst),'-o',str(obj),'src/cfd.s'],
                   cwd=ROOT,check=True)
    eq={}
    for line in lst.read_text(errors='replace').splitlines():
        m=re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\s+E:([0-9A-Fa-f]{8})\s*$',line)
        if m: eq[m.group(1)]=int(m.group(2),16)
    for n in ('CFG_SIZEOF','CFD_PrefsReady',*need): assert n in eq,'missing equate '+n
    return BinFmt().load_image(str(obj)),eq

class Loader:
    """sources: name -> bytes, or None for "not there". v36 makes GetVar report
    the whole variable instead of what it copied."""
    def __init__(self,image,eq,sources,v36=False,prefs_ready=True):
        self.eq=eq; self.sources=sources; self.v36=v36
        self.opened=[]; self.reads=[]; self.delays=0
        self.m=Machine.from_name('68000',ram_size=8192)
        self.cpu,self.mem=self.m.get_cpu(),self.m.get_mem()
        self.mem.w_block(BASE,bytes(Relocate(image).relocate_one_block(BASE)))
        self.syms={s.name.decode():BASE+s.offset
                   for s in image.get_segments()[0].get_symtab().get_symbols()}
        self.mem.w32(4,EXEC)
        self.mem.w8(DEV+eq['CFD_PrefsReady'],1 if prefs_ready else 0)
        self.mem.w_block(CFG,b'\x55'*eq['CFG_SIZEOF'])
        self.handles={}
        self.hook(EXEC,LVO_OPENLIB,self.open_lib)
        self.hook(EXEC,LVO_CLOSELIB,lambda:None)
        self.hook(DOSB,LVO_GETVAR,self.getvar)
        self.hook(DOSB,LVO_OPEN,self.dos_open)
        self.hook(DOSB,LVO_READ,self.dos_read)
        self.hook(DOSB,LVO_CLOSE,lambda:None)
        self.hook(DOSB,LVO_DELAY,self.delay)
    def hook(self,base,lvo,fn):
        t=self.m.get_traps().alloc(lambda op,pc,f=fn: f())
        self.mem.w16(base-lvo,0xa000|t); self.mem.w16(base-lvo+2,0x4e75)
    def cstr(self,addr):
        out=bytearray()
        while True:
            c=self.mem.r8(addr); addr+=1
            if not c: return bytes(out).decode('latin-1')
            out.append(c)
    def open_lib(self): self.cpu.w_reg(0,DOSB)          # d0 = DOSBase
    def delay(self): self.delays+=1
    def getvar(self):
        name=self.cstr(self.cpu.r_reg(1))               # d1
        buf,size=self.cpu.r_reg(2),self.cpu.r_reg(3)    # d2,d3
        val=self.sources.get('ENV:'+name)
        if val is None: self.cpu.w_reg(0,0xffffffff); return
        copied=min(len(val),size-1)                     # room for the NUL
        self.mem.w_block(buf,val[:copied]+b'\0')
        self.cpu.w_reg(0,len(val) if self.v36 else copied)
    def dos_open(self):
        name=self.cstr(self.cpu.r_reg(1))               # d1
        self.opened.append(name)
        if self.sources.get(name) is None: self.cpu.w_reg(0,0); return
        h=0x8000+len(self.handles); self.handles[h]=name; self.cpu.w_reg(0,h)
    def dos_read(self):
        name=self.handles[self.cpu.r_reg(1)]            # d1
        buf,length=self.cpu.r_reg(2),self.cpu.r_reg(3)
        val=self.sources[name][:length]
        self.reads.append((name,length))
        if val: self.mem.w_block(buf,val)
        self.cpu.w_reg(0,len(val))
    def run(self):
        for r in range(15): self.cpu.w_reg(r,0x55550000+r)
        self.cpu.w_reg(11,UNIT); self.cpu.w_reg(12,DEV); self.cpu.w_reg(13,CFG)
        self.m.prepare(self.syms['_mwReadConfig'],STACK)
        st=self.m.execute(4000000)
        assert self.m.was_exit(st),'_mwReadConfig did not return'
        assert self.cpu.r_sp()==STACK,'_mwReadConfig left the stack unbalanced'
    def b(self,off): return self.mem.r8(CFG+off)
    def l(self,off): return self.mem.r32(CFG+off)
    def close(self): self.m.cleanup()
    def __enter__(self): return self
    def __exit__(self,*exc): self.close()
