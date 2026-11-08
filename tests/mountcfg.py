#!/usr/bin/env python3
"""cfd.prefs keys to the MountCfg, override rows and UNMOUNT list.

Drives _mwReadConfig with a prefs text and reads back the MountCfg handed to
ptable.library, by offsets from the assembler listing. Case ids: C3 prefs
buffer size, C4 table bounds and line scope. OPEN lists the ids whose fix has
not landed: their check must still fail, and the fixing commit removes the id.

Status: gated, run by make test.
Run: python3 tests/mountcfg.py"""
import sys,tempfile
from pathlib import Path
from prefsrig import CFG, Loader, build
from toolchain import ROOT

OPEN = {'C3','C4'}
NEED = ('CFG_MountCfg','CFG_Prefixes','CFG_Overrides','CFG_BUFSZ','CFG_Trunc',
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
    return True

def c_overrides(image,eq,_):
    c=parse(image,eq,b'FLAGS_PFS 3\nCONTROL_SFS abc\nCONTROL_FFS ffs\n')
    assert c.overrides_at,'mc_Overrides not set'
    assert sorted(c.rows)==sorted([(PFS,3,1,None),(PDS,3,1,None),(SFS,0,0,'abc'),(DOS,0,0,'ffs')]),c.rows
    return True

def c_pool(image,eq,_):
    # Every string key at once: CONTROL, each CONTROL_<fs> row, HANDLER_FAT.
    text=b'CONTROL g\nHANDLER_FAT L:h\n'+b''.join(b'CONTROL_%s %s\n'%(k,k.lower())
                                                    for k in (b'DOS',b'FFS',b'SFS',b'PFS',b'FAT'))
    c=parse(image,eq,text)
    assert c.control=='g' and c.handler=='L:h',vars(c)
    want={DOS:'ffs',SFS:'sfs',PFS:'pfs',PDS:'pfs',FAT:'fat'}
    assert {r[0]:r[3] for r in c.rows}==want,c.rows
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
    c=parse(image,eq,b'UNMOUNT FAT\nHANDLER_FAT "L:SFS"\n')
    assert c.prefixes==[FAT],[hex(p) for p in c.prefixes]
    return True

CASES = [
    ('', 'defaults', c_defaults), ('', 'global keys', c_globals),
    ('', 'keys are whole words', c_whole_word), ('', 'per-fs override rows', c_overrides),
    ('', 'every string key fits the pool', c_pool), ('', 'UNMOUNT list', c_unmount),
    ('', 'policy bits', c_policy), ('', 'shipped cfd.prefs', c_shipped),
    ('C3', 'key past 511 bytes is read', c_long_prefs),
    ('C4', 'UNMOUNT names from its line only', c_unmount_line),
]

def main():
    failures=[]
    with tempfile.TemporaryDirectory() as t:
        image,eq=build(Path(t),NEED)
        for ident,label,fn in CASES:
            try:
                ok=bool(fn(image,eq,None))
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
