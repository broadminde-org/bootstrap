"""llmdocs — LLM-friendly upstream-docs generator framework.

Stdlib only. The framework owns the universal pipeline shape:

    clone upstream -> prepare source -> resolve pages -> emit
    -> postprocess -> write topic files

The customization surface for each new doc source is:
  - the upstream repo URL + pinned VERSION
  - a `sections.json` mapping topic names to source pages
  - one or more emitters (function from payload -> Markdown)
  - a source-specific postprocess function

See PIPELINE.md for the full shape and LLM_INSTRUCTIONS.md for the
step-by-step recipe an LLM should follow when adapting this for a
new doc source.
"""

from .build import build, BuildConfig, DEFAULT_EMITTER
from . import emitters
from . import postprocess, clone, prep, sections, topic

__all__ = [
    "build", "BuildConfig", "DEFAULT_EMITTER",
    "emitters", "postprocess", "clone", "prep", "sections", "topic",
]
__version__ = "0.1.0"