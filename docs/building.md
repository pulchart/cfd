# Building cfd

## Requirements

* vasm 2.0f (`vasmm68k_mot`), default path `/opt/vasm` (`VASM_HOME=`)
* vbcc and the NDK for the tools, default path `/opt/vbcc` (`VBCC_HOME=`); extract the NDK into `NDK/`
* an amigaos-ptable checkout: `extern/ptable` submodule or `PTABLE=`
* python3 for the guides and tests, `lha` for releases

## ptable.library

`ptable.library`, `lsptres` and `lsptres.guide` are built in amigaos-ptable and copied into `dist/`. During ptable development build against a local checkout:

```sh
export PTABLE=/path/to/amigaos-ptable
```

`make ptable-sync` moves `extern/ptable` to its `origin/master` tip and rebuilds; commit the gitlink with the rebuilt `dist/` afterwards.

## Release

```sh
make clean; make; make guide; make release
```

`make clean` also cleans the `PTABLE` checkout.

## Targets

| Target | Does |
|--------|------|
| `make` | drivers, automount, ptable.library copies, tools |
| `make full`, `small`, `full-000`, `small-000` | one driver variant |
| `make tools` | CFInfo, pcmciacheck, pcmciaspeed, lsptres |
| `make guide` | AmigaGuide files from Markdown |
| `make stage` | archive tree in `build/stage` |
| `make release` | Aminet LHA archive and readme |
| `make test` | emulated test suites |
| `make checksums`, `clean`, `distclean`, `help` | sizes and checksums, cleanup, target list |

Options: `V=1` verbose, `GTIMING=1` Gayle timing (experimental), `FUNCEXT_VOTING=0`, `ATAPI=1`.

Output goes to `dist/<flavour>/<cpu>/{devs,libs}/` and `dist/c/`.

## Install script

`make stage` joins fragments into `Install` and `Setup` and replaces `@VERSION@`. `Install.info` and `Setup.info` start them with `Installer`.

| File | Does |
|------|------|
| `install/cfd.head` | version, final report names `SYS:`, welcome, variables for `ptable.inc` |
| `$(PTABLE)/install/common.inc` | `P_COPY`: copies a file, asks before replacing a newer one; `P_LOADMODULE`: one LoadModule line in `S:User-Startup` shared by cfd and fat95 |
| `$(PTABLE)/install/ptable.inc` | CPU and small/full choice, `ptable.library` to `LIBS:` |
| `install/cfd.inc` | device and automount, tools list, optional parts, `LoadModule` line |
| `install/cfd.tail` | `(exit)` |
| `install/setup.head`, `setup.inc`, `setup.tail` | `Setup`: one question per `cfd.prefs` setting, writes `ENVARC:` and optionally `ENV:` |

- `Install` = `cfd.head` + `common.inc` + `ptable.inc` + `cfd.inc` + `cfd.tail`.
- `Setup` = `setup.head` + `setup.inc` + `setup.tail`.

The CPU and variant chosen in `ptable.inc` select the device and automount too. `cfd.head` sets `ptable-ask-lsptres` to 0; `lsptres` is in the tools list. Build with `PTABLE=` pointing at an amigaos-ptable checkout.
