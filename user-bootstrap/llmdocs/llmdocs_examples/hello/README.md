# Hello World

A minimal example using `llmdocs`.

## Layout

```
llmdocs/llmdocs_examples/hello/
├── README.md
├── sections.json
├── build.py         # per-source wrapper, ~65 lines
└── _build/src/      # (gitignored) cloned source
└── ref/             # generated output
```

## Source

The example builds docs from a small public Git repo:
`https://github.com/octocat/Hello-World` (the canonical GitHub
"hello world" — one `README`, one `LICENSE`, no extension).

## Run it

From workspace root:

```
python3 -m llmdocs.llmdocs_examples.hello.build
```

Add `--check` to fail-fast if output would change. Add `--refresh`
to force re-clone. Add `--json-stats` to print `{topics, pages, chars,
est_tokens, version}` as JSON to stdout.

## How it uses the framework

The wrapper is intentionally tiny. The key shape:

```python
from llmdocs import BuildConfig, build
from pathlib import Path

WORKSPACE = Path(__file__).resolve().parents[3]

CONFIG = BuildConfig(
    name="hello",
    repo_url="https://github.com/octocat/Hello-World.git",
    version_file=WORKSPACE / "llmdocs" / "llmdocs_examples" / "hello" / "HELLO_VERSION",
    src_dir=WORKSPACE / "llmdocs" / "llmdocs_examples" / "hello" / "_build" / "src",
    sections_file=WORKSPACE / "llmdocs" / "llmdocs_examples" / "hello" / "sections.json",
    output_dir=WORKSPACE / "llmdocs" / "llmdocs_examples" / "hello" / "ref",
    ext="",                          # octocat/Hello-World has no extension
    version_validation_regex=None,   # only has a master branch, no vX.Y.Z tags
)
```

Everything else (clone, page resolution, dispatch, --check,
--json-stats, output writing) comes from `llmdocs.build()`. Per-source
emitters and postprocess steps are added by passing
`extra_emitters={...}` and `postprocess=...` to `BuildConfig` when
needed.

## Try a custom postprocess

To see how postprocess customization works, edit `build.py` and add:

```python
import re
from llmdocs.postprocess import wrap_sections, normalize_whitespace

def my_postprocess(text, version, docname):
    text = re.sub(r"Hello", f"Hello (v{version})", text)
    text = wrap_sections(text)
    text = normalize_whitespace(text)
    return text

CONFIG = BuildConfig(..., postprocess=my_postprocess)
```

Re-run and notice the version pin gets injected into the output.