"""Check make test dependencies before importing the emulator."""
import importlib.metadata as md
import shutil
import subprocess
import sys
from toolchain import PTABLE_SRC, ROOT, VASM


def main():
    bad = sys.version_info < (3, 11)
    print('Python', sys.version.split()[0], '(3.11+ required)')
    for name, tested in (('amitools-amifuse', '0.8.0.post8'),
                         ('machine68k-amifuse', '0.4.1.post1')):
        try:
            version = md.version(name)
            print(name, version, '' if version == tested else '(untested version)')
        except md.PackageNotFoundError:
            print(name, 'missing; install tests/requirements.txt')
            bad = True
    for name in ('amitools', 'machine68k'):
        try:
            md.version(name)
        except md.PackageNotFoundError:
            continue
        print(name, 'conflicts with required fork; use a fresh venv, or uninstall')
        print('both providers and reinstall tests/requirements.txt')
        bad = True
    try:
        result = subprocess.run([VASM, '-v'], capture_output=True, text=True, timeout=10)
        banner = (result.stdout + result.stderr).strip().splitlines()[0]
        print(VASM, banner)
        if '2.0f' not in banner:
            print('vasm version untested; expected 2.0f')
    except (OSError, subprocess.SubprocessError, IndexError):
        print('vasm missing; set VASM_HOME or put vasmm68k_mot on PATH')
        bad = True
    if not (PTABLE_SRC / 'ptable_pub.i').is_file():
        print(f'ptable missing at {PTABLE_SRC.parent}; run git submodule update --init or set PTABLE')
        bad = True
    return int(bad)


if __name__ == '__main__':
    raise SystemExit(main())
