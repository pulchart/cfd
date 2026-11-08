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
import sys,tempfile
from pathlib import Path
from prefsrig import ARCHIVE, ENVARC, Loader, build
NEED=('CFG_Buf','CFG_AutoMount','CFG_AmBad','CFG_Source','CFG_Trunc','CFG_DbgRead',
      'CFG_BUFSZ')

def result(d):
    eq=d.eq; read=d.l(eq['CFG_DbgRead'])
    return dict(am=1 if d.b(eq['CFG_AutoMount']) else 0,ambad=d.b(eq['CFG_AmBad']),
                source=d.b(eq['CFG_Source']),trunc=d.b(eq['CFG_Trunc']),
                read=read-(1<<32) if read>>31 else read)

bad=[]
def check(name,cond,detail=''):
    print(f'  {name:52} {"ok " if cond else "FAIL"} {detail}')
    if not cond: bad.append(name)

def load(image,eq,sources,**kw):
    with Loader(image,eq,sources,**kw) as d:
        d.run()
        return result(d),d

ON=b'AUTOMOUNT 1\n'; OFF=b'AUTOMOUNT 0\n'
def filler(total,head=b'',tail=b''):
    """head + comment padding + tail, exactly total bytes."""
    pad=total-len(head)-len(tail)
    assert pad>=2
    return head+b'; '+b'p'*(pad-3)+b'\n'+tail

with tempfile.TemporaryDirectory() as t:
    image,eq=build(Path(t),NEED)
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
    long_env=filler(BUFSZ+106,ON,OFF)
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
