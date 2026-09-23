# cfd tests

Assembled sources run in amitools/vamos with the card, Exec and dos.library mocked. Each suite and what it checks: [INVENTORY.md](INVENTORY.md).

## Requires

Linux, Python 3.11+, [vasm 2.0f](http://sun.hasenbraten.de/vasm/) and the ptable submodule. From the repository root:

```sh
git submodule update --init
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r tests/requirements.txt
make test
```

`make check-test-deps` diagnoses dependencies. Set `VASM_HOME` or `make VASM=/path/to/vasmm68k_mot`. The pinned Python forks conflict with upstream `amitools`/`machine68k`; use a clean environment.

Sources assemble into temporary files; release binaries remain untouched.

## Not covered

Real AmigaOS, PCMCIA timing and physical card insertion/removal.

## Writing a test

Give the module docstring a one-line summary and a `Status:` line, add the suite to `TEST_SUITES` in the Makefile, run `make test-list-update` and commit INVENTORY.md.
