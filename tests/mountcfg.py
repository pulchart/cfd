#!/usr/bin/env python3
"""cfd.prefs keys to the MountCfg, override rows and UNMOUNT list.

Drives _mwReadConfig with a prefs text and reads back the MountCfg handed to
ptable.library, by offsets from the assembler listing. Case ids: C3 prefs
buffer size, C4 table bounds and line scope, C5 binding rows. OPEN lists the ids whose fix has
not landed: their check must still fail, and the fixing commit removes the id.

Status: gated, run by make test.
Run: python3 tests/mountcfg.py"""
import sys,tempfile
from pathlib import Path
from prefsrig import (CFG, DEV, DOSB, EXEC, UNIT, LVO_ALLOCMEM, LVO_FINDNAME, LVO_FORBID,
                      LVO_FREEMEM, LVO_PERMIT, LVO_SIGNAL, Loader, build)
from toolchain import ROOT

OPEN = set()
NEED = ('CFG_Buf','CFG_MountCfg','CFG_Prefixes','CFG_Overrides','CFG_BUFSZ','CFG_Trunc',
        'mc_Flags','mc_Control','mc_Overrides','mc_NodeDosType','mc_NodeHandler','mc_Size',
        'mc_UnmFlags','mc_Sizeof','ovr_Prefix','ovr_Flags','ovr_HasFlags','ovr_Control',
        'ovr_Sizeof','MCUF_KEEPSTATIC','MCUF_STAMPONLY','MCUF_MOUNTUSED')
DOS,SFS,PFS,PDS,FAT = 0x444F5300,0x53465300,0x50465300,0x50445300,0x46415400
UNMOUNT_ALL = [PFS,PDS,DOS,DOS,SFS,FAT]

class Cfg:
    """The parsed result, read while the machine is alive."""
    def __init__(self,d):
        eq=d.eq; mc=eq['CFG_MountCfg']
        def cstr(p): return d.cstr(p) if p else None
        self.trunc=d.b(eq['CFG_Trunc'])
        self.buf=bytes(d.mem.r_block(CFG+eq['CFG_Buf'],eq['CFG_BUFSZ']))
        self.mc={n[3:]:d.l(mc+eq[n]) for n in eq if n.startswith('mc_') and n!='mc_Sizeof'}
        self.raw=[d.l(mc+i) for i in range(0,eq['mc_Sizeof'],4)]
        self.control=cstr(self.mc['Control'])
        self.handler=cstr(self.mc['NodeHandler'])
        self.rows=[]
        p=self.mc['Overrides']
        while p and len(self.rows)<16:
            prefix=d.mem.r32(p+eq['ovr_Prefix'])
            if not prefix: break
            self.rows.append((prefix,d.mem.r32(p+eq['ovr_Flags']),d.mem.r8(p+eq['ovr_HasFlags']),
                              cstr(d.mem.r32(p+eq['ovr_Control']))))
            p+=eq['ovr_Sizeof']
        self.overrides_at=p and CFG+eq['CFG_Overrides']
        self.binds=[]
        if 'mc_Binds' in eq:
            p,n,size=self.mc['Binds'],self.mc['BindCount'],self.mc['BindSize']
            for i in range(n if p else 0):
                r=p+i*size
                flags=d.mem.r8(r+eq['bnd_Flags'])
                pri=d.mem.r32(r+eq['bnd_Pri'])
                self.binds.append(dict(prefix=d.mem.r32(r+eq['bnd_Prefix']),
                    force=bool(flags&(1<<eq['BNDB_FORCE'])),
                    pri=(pri-(1<<32) if pri>>31 else pri) if flags&(1<<eq['BNDB_PRI']) else None,
                    dostype=d.mem.r32(r+eq['bnd_DosType']),
                    handler=cstr(d.mem.r32(r+eq['bnd_Handler'])),
                    stack=d.mem.r32(r+eq['bnd_Stack'])))
            self.bindsize_ok=(n==0 and p==0) or size==eq['bnd_Sizeof']
        self.prefixes=[]
        for i in range(16):
            v=d.l(eq['CFG_Prefixes']+4*i)
            if not v: break
            self.prefixes.append(v)
    def row(self,prefix): return [r for r in self.rows if r[0]==prefix]

def parse(image,eq,text):
    with Loader(image,eq,{'ENV:cfd.prefs':text}) as d:
        d.run()
        return Cfg(d)

PTB,FRAME=0x2e0000,0x380000
class Worker(Loader):
    """_MountWorkEntry with exec, dos and ptable.library mocked. alloc=False
    fails every AllocMem; device/ptable=False make FindName/OpenLibrary fail."""
    def __init__(self,image,eq,sources,device=True,ptable=True,alloc=True):
        super().__init__(image,eq,sources)
        self.device,self.ptable,self.alloc=device,ptable,alloc
        self.allocs={}; self.events=[]; self.mountcfg=None
        self.mem.w32(DEV+eq['CFD_ExecBase'],EXEC)
        self.mem.w32(DEV+eq['CFD_Unit'],UNIT)
        self.mem.w32(UNIT+eq['CFU_DriveSize'],1000)
        self.mem.w32(UNIT+eq['CFU_MountDone'],0x100)
        self.mem.w32(UNIT+eq['CFU_MountAgent'],0x7000)
        for lvo,fn in ((LVO_FORBID,lambda:None),(LVO_PERMIT,lambda:None),
                       (LVO_FINDNAME,self.find_name),(LVO_ALLOCMEM,self.alloc_mem),
                       (LVO_FREEMEM,self.free_mem),
                       (LVO_SIGNAL,lambda:self.events.append('Signal'))):
            self.hook(EXEC,lvo,fn)
        for lvo,name in ((36,'Scan'),(42,'Mount'),(48,'Unmount'),(60,'MarkAbsent')):
            self.hook(PTB,lvo,lambda name=name:self.ptable_call(name))
    def find_name(self): self.cpu.w_reg(0,DEV if self.device else 0)
    def open_lib(self):
        name=self.cstr(self.cpu.r_reg(9))               # a1
        base={'dos.library':DOSB,'ptable.library':PTB if self.ptable else 0}[name]
        self.cpu.w_reg(0,base)
    def alloc_mem(self):
        size=self.cpu.r_reg(0)
        if not self.alloc: self.cpu.w_reg(0,0); return
        addr=FRAME+0x10000*len(self.allocs)
        self.mem.w_block(addr,b'\x55'*size)
        self.allocs[addr]=size; self.cpu.w_reg(0,addr)
    def free_mem(self):
        addr,size=self.cpu.r_reg(9),self.cpu.r_reg(0)
        assert self.allocs.pop(addr,None)==size,'FreeMem of %x/%d not allocated'%(addr,size)
    def ptable_call(self,name):
        self.events.append(name)
        if name=='Mount':
            a0=self.cpu.r_reg(8)
            self.mountcfg=(a0,self.mem.r32(a0+self.eq['mc_Size']))
        self.cpu.w_reg(0,0)

def worker(image,eq,**kw):
    with Worker(image,eq,{'ENV:cfd.prefs':b'AUTOMOUNT 1\n'},**kw) as d:
        d.run('_MountWorkEntry')
        return d.events,d.allocs,d.mountcfg

def c_worker(_,__,wimage_eq):
    image,eq=wimage_eq
    ev,left,mc=worker(image,eq)
    assert ev==['Scan','Mount','Signal'] and not left,(ev,left)
    assert mc and mc[1]==eq['mc_Sizeof'] and FRAME<=mc[0]<FRAME+0x10000,mc
    ev,left,_=worker(image,eq,alloc=False)
    assert ev==['Signal'] and not left,('no memory',ev,left)
    ev,left,_=worker(image,eq,ptable=False)
    assert ev==['Signal'] and not left,('no ptable',ev,left)
    ev,left,_=worker(image,eq,device=False)
    assert ev==[] and not left,('no device',ev,left)
    return True

def c_defaults(image,eq,_):
    c=parse(image,eq,b'')
    assert c.mc['Size']==eq['mc_Sizeof'],c.mc
    assert all(v==0 for k,v in c.mc.items() if k!='Size'),c.mc
    assert 0x55555555 not in c.raw,'MountCfg field left unset: %s'%[hex(v) for v in c.raw]
    assert c.prefixes==UNMOUNT_ALL,[hex(p) for p in c.prefixes]
    return True

def c_globals(image,eq,_):
    c=parse(image,eq,b'FLAGS 9\nCONTROL "-d +D"\nDOSTYPE_FAT 0x4D534400\nHANDLER_FAT L:CrossDOSFileSystem\n')
    assert (c.mc['Flags'],c.control,c.mc['NodeDosType'],c.handler)==(9,'-d +D',0x4D534400,'L:CrossDOSFileSystem'),vars(c)
    assert c.rows==[],c.rows
    return True

def c_whole_word(image,eq,_):
    c=parse(image,eq,b'FLAGS_DOS 7\nCONTROL_FAT x\n')
    assert c.mc['Flags']==0 and c.control is None,c.mc
    assert c.row(DOS)==[(DOS,7,1,None)] and c.row(FAT)==[(FAT,0,0,'x')],c.rows
    c=parse(image,eq,b'XFLAGS 1\nFLAGSX 2\nFLAGS_DOS 7\nCONTROL_FA')
    assert c.mc['Flags']==0 and c.rows==[(DOS,7,1,None)],(c.mc,c.rows)
    c=parse(image,eq,b'FFLAGS 1\nFLAGS 3')
    assert c.mc['Flags']==3,c.mc
    return True

def c_overrides(image,eq,_):
    c=parse(image,eq,b'FLAGS_PFS 3\nCONTROL_SFS abc\nCONTROL_FFS ffs\n')
    assert c.overrides_at,'mc_Overrides not set'
    assert sorted(c.rows)==sorted([(PFS,3,1,None),(PDS,3,1,None),(SFS,0,0,'abc'),(DOS,0,0,'ffs')]),c.rows
    return True

def c_unmount(image,eq,_):
    c=parse(image,eq,b'UNMOUNT FAT SFS\n')
    assert c.prefixes==[SFS,FAT],[hex(p) for p in c.prefixes]
    c=parse(image,eq,b'UNMOUNT NONE\n')
    assert c.prefixes==[],[hex(p) for p in c.prefixes]
    return True

def c_policy(image,eq,_):
    c=parse(image,eq,b'AUTOMOUNT 0\nUNMOUNT_STATIC 0\nMOUNT_USED 1\n')
    want=(1<<eq['MCUF_KEEPSTATIC'])|(1<<eq['MCUF_STAMPONLY'])|(1<<eq['MCUF_MOUNTUSED'])
    assert c.mc['UnmFlags']==want,c.mc
    keep,used=1<<eq['MCUF_KEEPSTATIC'],1<<eq['MCUF_MOUNTUSED']
    for text,flags in ((b'UNMOUNT_STATIC off\nMOUNT_USED yes\n',keep|used),
                       (b'UNMOUNT_STATIC No\nMOUNT_USED On\n',keep|used),
                       (b'UNMOUNT_STATIC maybe\nMOUNT_USED 2\n',0),
                       (b'UNMOUNT_STATIC ON\nMOUNT_USED NEVER\n',0)):
        c=parse(image,eq,text)
        assert c.mc['UnmFlags']==flags,(text,c.mc['UnmFlags'])
    return True

def c_shipped(image,eq,_):
    c=parse(image,eq,(ROOT/'dist/ENVARC/cfd.prefs').read_bytes())
    assert c.trunc==0 and c.row(FAT)==[(FAT,0,0,'-d-D+q')],vars(c)
    return True

def c_long_prefs(image,eq,_):
    # A key past the first 511 bytes of a commented prefs file.
    text=b''.join(b'; comment line %04d ................................\n'%i for i in range(30))+b'FLAGS 9\n'
    c=parse(image,eq,text)
    assert c.trunc==0 and c.mc['Flags']==9,(c.trunc,c.mc['Flags'],len(text))
    return True

def c_unmount_line(image,eq,_):
    # An UNMOUNT name on another line is not part of the list.
    text=b'UNMOUNT FAT\nHANDLER_FAT "L:SFS"\n'
    c=parse(image,eq,text)
    assert c.prefixes==[FAT],[hex(p) for p in c.prefixes]
    assert c.buf.startswith(text+b'\0'),'buffer not restored: %r'%c.buf[:40]
    return True

def bind(c,prefix):
    rows=[r for r in c.binds if r['prefix']==prefix]
    assert len(rows)==1,(hex(prefix),c.binds)
    return rows[0]

def row(prefix,**kw):
    out=dict(prefix=prefix,force=False,pri=None,dostype=0,handler=None,stack=0)
    out.update(kw); return out

def c_bind_none(image,eq,_):
    c=parse(image,eq,b'FLAGS 1\n')
    assert 'mc_Binds' in eq,'no binding rows in this build'
    assert c.binds==[] and c.mc['Binds']==0,c.mc
    return True

def c_bind_handler(image,eq,_):
    c=parse(image,eq,b'HANDLER_SFS L:SmartFilesystem\n')
    assert c.binds==[row(SFS,handler='L:SmartFilesystem')] and c.bindsize_ok,c.binds
    return True

def c_bind_fat_legacy(image,eq,_):
    c=parse(image,eq,b'DOSTYPE_FAT 0x4D534400\nHANDLER_FAT L:CrossDOSFileSystem\nFORCE_FAT YES\n')
    assert c.binds==[row(FAT,dostype=0x4D534400,handler='L:CrossDOSFileSystem',force=True)],c.binds
    assert (c.mc['NodeDosType'],c.handler)==(0x4D534400,'L:CrossDOSFileSystem'),c.mc
    return True

def c_bind_pfs(image,eq,_):
    c=parse(image,eq,b'STACK_PFS 16384\nPRI_PFS -2\n')
    want=dict(stack=16384,pri=-2)
    assert bind(c,PFS)==row(PFS,**want) and bind(c,PDS)==row(PDS,**want),c.binds
    return True

def c_bind_dos_ffs(image,eq,_):
    c=parse(image,eq,b'HANDLER_FFS L:FastFileSystem\nSTACK_DOS 8000\nPRI_DOS 3\nFORCE_FFS 0\n')
    assert c.binds==[row(DOS,handler='L:FastFileSystem',stack=8000,pri=3)],c.binds
    return True

def c_bind_pool(image,eq,_):
    # Every string key at once: CONTROL, each CONTROL_<fs> and HANDLER_<fs>.
    names=(b'DOS',b'FFS',b'SFS',b'PFS',b'FAT')
    text=b'CONTROL g\n'+b''.join(b'CONTROL_%s c%s\nHANDLER_%s L:%s\n'%(k,k.lower(),k,k.lower())
                                for k in names)
    c=parse(image,eq,text)
    assert c.control=='g',c.control
    assert {r[0]:r[3] for r in c.rows}=={DOS:'cffs',SFS:'csfs',PFS:'cpfs',PDS:'cpfs',FAT:'cfat'},c.rows
    assert {r['prefix']:r['handler'] for r in c.binds}=={DOS:'L:ffs',SFS:'L:sfs',PFS:'L:pfs',
                                                       PDS:'L:pfs',FAT:'L:fat'},c.binds
    assert c.handler=='L:fat',c.handler
    return True

CASES = [
    ('', 'defaults', c_defaults), ('', 'global keys', c_globals),
    ('', 'keys are whole words', c_whole_word), ('', 'per-fs override rows', c_overrides),
    ('', 'UNMOUNT list', c_unmount), ('', 'policy bits', c_policy),
    ('', 'shipped cfd.prefs', c_shipped),
    ('', 'worker exits free and signal', c_worker),
    ('C3', 'key past 511 bytes is read', c_long_prefs),
    ('C4', 'UNMOUNT names from its line only', c_unmount_line),
    ('C5', 'no binding keys: no rows', c_bind_none),
    ('C5', 'HANDLER_SFS row', c_bind_handler),
    ('C5', 'FAT keys: row and mc_Node*', c_bind_fat_legacy),
    ('C5', 'PFS keys fill PFS and PDS rows', c_bind_pfs),
    ('C5', 'DOS and FFS keys share a row', c_bind_dos_ffs),
    ('C5', 'every string key fits the pool', c_bind_pool),
]

def main():
    failures=[]
    with tempfile.TemporaryDirectory() as t:
        image,eq=build(Path(t),NEED)
        (Path(t)/'w').mkdir()
        wimage_eq=build(Path(t)/'w',NEED,debug=False)
        for ident,label,fn in CASES:
            try:
                ok=bool(fn(image,eq,wimage_eq))
            except AssertionError as e:
                ok,label=False,'%s (%s)'%(label,e)
            want=ident not in OPEN
            if ok!=want:
                failures.append('%s [%s]: %s'%(label,ident or 'base',
                                               'passes, remove from OPEN' if ok else 'FAILS'))
            print('%-3s %-40s %s'%(ident or '-',label[:40],'ok' if ok else 'open'))
    for f in failures: print('FAIL',f)
    sys.exit(1 if failures else 0)

if __name__=='__main__':
    main()
