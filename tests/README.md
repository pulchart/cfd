# cfd tests

Assembled sources run in amitools/vamos with the card, Exec and dos.library mocked. Each suite and what it checks: [INVENTORY.md](INVENTORY.md).

## Requires

The ptable submodule. `make test` runs the suites in the amiga-toolchain image, which holds vasm 2.0f, Python 3.14+, `amitools` and `machine68k` at the versions in its `requirements.txt`, see [docs/building.md](../docs/building.md). For Python runs outside the image, `uv pip install -r` that file into a venv:

```sh
git submodule update --init
make test
```

`make lint` runs ruff and yamllint; `pre-commit install` runs them before each commit.

`make check-test-deps` diagnoses dependencies. `make test PTABLE=/path/to/ptable` tests against another ptable checkout instead of `extern/ptable`.

Sources assemble into temporary files; release binaries remain untouched.

## Integration tests

AmigaOS and card insertion/removal run in FS-UAE: [integration/README.md](integration/README.md). PCMCIA timing needs real hardware.

## Writing a test

Give the module docstring a one-line summary and a `Status:` line, add the suite to `TEST_SUITES` in the Makefile, run `make test-list-update` and commit INVENTORY.md.
