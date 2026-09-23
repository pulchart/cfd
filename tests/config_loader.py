#!/usr/bin/env python3
"""The cfd.prefs loader: which source wins, empty sources and truncated input.

The parser tests feed CFG_Buf directly, so they cannot see the cascade in
front of it. This one mocks dos.library per the NDK GetVar contract (-1 means
undefined, 0 is a valid empty value, V37+ returns characters copied) and asks
_mwReadConfig which source won and what AUTOMOUNT ended up as. An empty
source is an answer rather than a miss, and a source filling the buffer is
reported as cut instead of read as a valid prefix.

Status: gated, run by make test.
Run: python3 tests/config_loader.py
"""
import re,subprocess,sys,tempfile
from pathlib import Path
from amitools.binfmt.BinFmt import BinFmt
from amitools.binfmt.Relocate import Relocate
from amitools.vamos.machine import Machine
from toolchain import ROOT, VASM
BASE,UNIT,DEV,CFG,EXEC,DOSB,STACK=0x10000,0x100000,0x140000,0x200000,0x280000,0x2c0000,0x300000
LVO_OPENLIB,LVO_CLOSELIB=552,414
LVO_OPEN,LVO_CLOSE,LVO_READ,LVO_DELAY,LVO_GETVAR=30,36,42,198,906
NEED=('CFG_Buf','CFG_AutoMount','CFG_AmBad','CFG_Source','CFG_Trunc','CFG_DbgRead',
      'CFG_BUFSZ','CFD_PrefsReady')
ENVARC,ARCHIVE='ENVARC:cfd.prefs','SYS:Prefs/Env-Archive/cfd.prefs'

def build(tmp):
    obj=tmp/'cfd'; lst=tmp/'cfd.lst'
    subprocess.run([VASM,'-quiet','-Fhunkexe','-m68000','-DDEBUG=1',
                    '-I','extern/ptable/src','-L',str(lst),'-o',str(obj),'src/cfd.s'],
                   cwd=ROOT,check=True)
    eq={}
    for line in lst.read_text(errors='replace').splitlines():
        m=re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\s+E:([0-9A-Fa-f]{8})\s*$',line)
        if m: eq[m.group(1)]=int(m.group(2),16)
    for n in NEED: assert n in eq,'missing equate '+n
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
        read=self.mem.r32(CFG+self.eq['CFG_DbgRead'])
        return dict(am=1 if self.mem.r8(CFG+self.eq['CFG_AutoMount']) else 0,
                    ambad=self.mem.r8(CFG+self.eq['CFG_AmBad']),
                    source=self.mem.r8(CFG+self.eq['CFG_Source']),
                    trunc=self.mem.r8(CFG+self.eq['CFG_Trunc']),
                    read=read-(1<<32) if read>>31 else read)
    def close(self): self.m.cleanup()

bad=[]
def check(name,cond,detail=''):
    print(f'  {name:52} {"ok " if cond else "FAIL"} {detail}')
    if not cond: bad.append(name)

def load(image,eq,sources,**kw):
    d=Loader(image,eq,sources,**kw)
    try: return d.run(),d
    finally: d.close()

ON=b'AUTOMOUNT 1\n'; OFF=b'AUTOMOUNT 0\n'
def filler(total,head=b'',tail=b''):
    """head + comment padding + tail, exactly total bytes."""
    pad=total-len(head)-len(tail)
    assert pad>=2
    return head+b'; '+b'p'*(pad-3)+b'\n'+tail

with tempfile.TemporaryDirectory() as t:
    image,eq=build(Path(t))
    BUFSZ=eq['CFG_BUFSZ']

    print('source precedence')
    r,_=load(image,eq,{'ENV:cfd.prefs':ON})
    check('a plain AUTOMOUNT 1 in ENV: is read and applied',r['am']==1 and r['source']==1,str(r))
    # The archive says the opposite of the default, so a leak through the empty
    # source would be visible; an empty source wins and carries no settings.
    r,_=load(image,eq,{'ENV:cfd.prefs':b'',ARCHIVE:OFF})
    check('an empty ENV: wins and masks the archive',r['am']==1 and r['source']==1,str(r))
    r,d=load(image,eq,{ARCHIVE:ON})
    check('a missing ENV: falls through to the archive',r['am']==1 and r['source']==3,str(r))
    check('and it tried ENVARC: on the way',ENVARC in d.opened,str(d.opened))
    r,_=load(image,eq,{ENVARC:b'',ARCHIVE:OFF})
    check('an empty ENVARC: wins and masks the archive',r['am']==1 and r['source']==2,str(r))
    r,_=load(image,eq,{'ENV:cfd.prefs':ON,ENVARC:OFF,ARCHIVE:OFF})
    check('the first source decides, not the last',r['am']==1 and r['source']==1,str(r))
    r,_=load(image,eq,{'ENV:cfd.prefs':OFF,ARCHIVE:ON})
    check('an AUTOMOUNT 0 in ENV: is not overruled',r['am']==0 and r['source']==1,str(r))
    r,d=load(image,eq,{})
    check('no source anywhere leaves the built-in default on',
          r['am']==1 and r['source']==0 and r['read']==-1,str(r))
    check('and a resolved cascade does not wait',d.delays==0,str(d.delays))

    print('truncation: a source that fills the buffer is reported as cut')
    # The head is inside the buffer and the tail is past it. Nothing here may
    # act on the tail, and the loader has to say the source was cut: reading an
    # incomplete prefix as if it were the whole file is the defect this covers.
    long_env=filler(618,ON,OFF)
    r,_=load(image,eq,{'ENV:cfd.prefs':long_env})
    check('a long ENV: is reported cut and its tail is not parsed',
          r['trunc']==1 and r['am']==1,str(r))
    r,_=load(image,eq,{'ENV:cfd.prefs':long_env},v36=True)
    check('the same under V36 GetVar semantics',r['trunc']==1 and r['am']==1,str(r))
    r,_=load(image,eq,{ARCHIVE:long_env})
    check('a long archive file is reported cut as well',r['trunc']==1 and r['am']==1,str(r))
    for n in (BUFSZ-3,BUFSZ-2,BUFSZ-1):
        r,_=load(image,eq,{'ENV:cfd.prefs':filler(n,ON)})
        want=1 if n>=BUFSZ-1 else 0
        check(f'ENV: of exactly {n} bytes: cut={want}',
              r['trunc']==want and r['am']==1,str(r))
    r,_=load(image,eq,{'ENV:cfd.prefs':filler(BUFSZ-2,ON)})
    check('the last complete size is still read whole',r['read']==BUFSZ-2,str(r))

    print('values')
    r,_=load(image,eq,{'ENV:cfd.prefs':b'AUTOMOUNT maybe\n'})
    check('an unrecognized value keeps the default and is reported',
          r['am']==1 and r['ambad']==1,str(r))
    for text,want in ((b'AUTOMOUNT ON\n',1),(b'AUTOMOUNT off\n',0),
                      (b'AUTOMOUNT YES\n',1),(b'AUTOMOUNT no\n',0)):
        r,_=load(image,eq,{'ENV:cfd.prefs':text})
        check('%-22s reads as %d' % (text.strip().decode(),want),
              r['am']==want and r['ambad']==0,str(r))

print('FAIL' if bad else 'PASS',len(bad),'failed')
sys.exit(1 if bad else 0)
