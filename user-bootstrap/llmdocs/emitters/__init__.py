"""Emitter registry + dispatcher.

An emitter is a function with one of two signatures:

    # markdown / text source
    def render(source: str, docname: str, version: str) -> str: ...

    # docutils XML / similar structured source
    def render(root, docname: str, version: str) -> str: ...

The framework auto-detects the signature by inspecting the first
parameter's annotation, or the caller can decorate the function with
`@emitter("markdown")` or `@emitter("xml-root")` to be explicit.

Per-source wrappers register custom emitters via `BuildConfig.extra_emitters`
(a dict of `name -> render_fn`). The framework combines those with the
built-in emitters below and resolves `sections.json`'s `emitter:` field
through the combined registry.
"""
from __future__ import annotations

import inspect
from typing import Callable, Any

__all__ = [
    "REGISTRY",
    "make_registry",
    "make_render",
    "register",
    "EmitterFormat",
]

EmitterFormat = str  # "markdown" | "xml-root" | "auto"


def _detect_format(fn: Callable) -> str:
    """Determine whether an emitter expects markdown text or an XML root.

    Inspection order:
      1. Explicit `EMITTER_FORMAT` module-level attribute (set by the
         `@register("format")` decorator)
      2. First parameter annotation (`str` -> markdown, anything else -> xml-root)
      3. Default to markdown
    """
    explicit = getattr(fn, "EMITTER_FORMAT", None)
    if explicit in ("markdown", "xml-root"):
        return explicit
    sig = inspect.signature(fn)
    params = list(sig.parameters.values())
    if params:
        ann = params[0].annotation
        if ann is str:
            return "markdown"
        if ann is not inspect.Parameter.empty:
            return "xml-root"
    return "markdown"


def register(name: str, fmt: EmitterFormat = "auto") -> Callable:
    """Decorator that registers an emitter under `name` and pins its
    payload format. Usage:

        @emitters.register("endpoint", fmt="xml-root")
        def render(root, docname, version):
            ...
    """
    def deco(fn: Callable) -> Callable:
        fn.EMITTER_NAME = name
        fn.EMITTER_FORMAT = fmt if fmt != "auto" else _detect_format(fn)
        REGISTRY[name] = fn
        return fn
    return deco


def make_registry(extra: dict | None = None) -> dict:
    """Build the emitter registry: built-ins plus any extras from the
    per-source config."""
    reg = dict(REGISTRY)
    if extra:
        for name, fn in extra.items():
            fmt = getattr(fn, "EMITTER_FORMAT", None) or _detect_format(fn)
            fn.EMITTER_FORMAT = fmt
            reg[name] = fn
    return reg


def make_render(registry: dict) -> Callable[..., str]:
    """Build the dispatcher function passed to the topic generator.

    The dispatcher signature is `(emitter_name, payload, docname,
    version, ext=DEFAULT_EXT)`. `ext` is forwarded to emitters that
    want to include the file extension in their output (e.g. the
    citation preamble emitted by `prose_md`).
    """
    def render(emitter_name: str, payload: Any, docname: str, version: str,
               ext: str = ".md") -> str:
        if emitter_name not in registry:
            raise KeyError(
                f"emitter {emitter_name!r} not in registry; "
                f"available: {sorted(registry.keys())}"
            )
        fn = registry[emitter_name]
        # Pass `ext` as kwarg so emitters that don't accept it still work
        # (they get the default). Emitters that do care (like `prose_md`)
        # read it via the named parameter.
        try:
            return fn(payload, docname, version, ext=ext)
        except TypeError:
            return fn(payload, docname, version)
    return render


# Built-in emitters. Per-source wrappers can override these by passing
# a same-named entry in `BuildConfig.extra_emitters`.

from . import prose_md, prose_xml  # noqa: E402

REGISTRY: dict[str, Callable] = {
    # `prose` is the canonical passthrough emitter name. `prose_md` is
    # an explicit alias for the same function.
    "prose": prose_md.render,
    "prose_md": prose_md.render,
    # `prose_xml` walks a docutils XML root and emits Markdown. Use this
    # for sources that have already been transformed into docutils XML
    # (e.g. via `llmdocs.prep.sphinx_xml_via_docker`).
    "prose_xml": prose_xml.render,
}

prose_md.render.EMITTER_FORMAT = "markdown"
prose_xml.render.EMITTER_FORMAT = "xml-root"