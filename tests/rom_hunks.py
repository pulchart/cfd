#!/usr/bin/env python3
"""Device, automount and bundled ptable modules assemble to one CODE hunk.

They run from Kickstart ROM, where a hunk the loader would write to cannot
exist, so a stray ds/dc storage block is a failure here rather than a silent
write into ROM on hardware.

Status: gated, run by make test.
Run: python3 tests/rom_hunks.py
"""
import subprocess,sys,tempfile
from pathlib import Path
from amitools.binfmt.BinFmt import BinFmt
from toolchain import ROOT, VASM
PTABLE=ROOT/'extern/ptable/src'

# source, extra defines: the flavours the Kickstart build takes
MODULES=[('src/cfd.s', ('-m'+cpu, *(['-D__68020__=1'] if cpu=='68020' else []), *(['-DDEBUG=1'] if full else [])))
         for cpu in ('68000','68020') for full in (False,True)]
MODULES += [('src/cfd_automount.s',('-m68000',)),
            ('extern/ptable/src/ptable_lib.s',('-m68000',)),
            ('extern/ptable/src/ptable_lib.s',('-m68020','-D__68020__=1'))]

def hunks(tmp,source,flags):
    out=tmp/(Path(source).stem+'-'+'-'.join(f.lstrip('-') for f in flags))
    subprocess.run([VASM,'-quiet','-Fhunkexe','-nosym',*flags,
                    '-I',str(PTABLE),'-I',str(ROOT/'src'),'-o',str(out),source],
                   cwd=ROOT,check=True)
    image=BinFmt().load_image(str(out))
    return [(s.get_type_name(),s.size) for s in image.get_segments()]

def main():
    bad=[]
    with tempfile.TemporaryDirectory() as t:
        tmp=Path(t)
        for source,flags in MODULES:
            if not (ROOT/source).is_file():
                raise FileNotFoundError(ROOT/source)
            segs=hunks(tmp,source,flags)
            what=' '.join(f.lstrip('-') for f in flags)
            ok=len(segs)==1 and segs[0][0].upper().endswith('CODE')
            print(f'  {Path(source).name:20} {what:34} {"ok " if ok else "FAIL"} '
                  +', '.join(f'{n} {s}' for n,s in segs))
            if not ok: bad.append((source,what,segs))
    print(f'{len(MODULES)-len(bad)}/{len(MODULES)} modules are one CODE hunk',file=sys.stderr)
    for b in bad: print('  FAIL',b,file=sys.stderr)
    sys.exit(1 if bad else 0)
if __name__=='__main__':main()
