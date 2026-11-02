"""Shared resolution of the XPolicyLab checkout location.

RMBench no longer vendors XPolicyLab as a git submodule; it lives in a separate
repository and is located through, in priority order:

  1. an explicit value (e.g. the ``--xpolicylab_root`` CLI flag)
  2. the ``XPOLICYLAB_ROOT`` environment variable
  3. a sibling ``XPolicyLab`` directory next to this repository

XPolicyLab's policy adapters (``policy/<name>/``) are not pip-installable, so the
scheduler / server / client all reach them through this single root. The
``client_server`` / ``utils`` packages are importable from the same checkout by
adding this root to ``sys.path`` (see ``eval_policy_xpolicylab.add_xpolicylab_paths``).
"""

from __future__ import annotations

import os
from pathlib import Path

ROBOTWIN_ROOT = Path(__file__).resolve().parents[1]


def resolve_xpolicylab_root(cli_value: str | os.PathLike[str] | None = None) -> Path:
    if cli_value:
        candidate = Path(os.path.expanduser(os.fspath(cli_value)))
    else:
        env_value = os.environ.get("XPOLICYLAB_ROOT")
        if env_value:
            candidate = Path(os.path.expanduser(env_value))
        else:
            candidate = ROBOTWIN_ROOT.parent / "XPolicyLab"

    candidate = candidate.resolve()
    if not (candidate / "setup_policy_server.py").is_file():
        raise FileNotFoundError(
            f"XPolicyLab checkout not found at {candidate}. "
            "Clone it next to RMBench (or set XPOLICYLAB_ROOT), e.g.:\n"
            f"  git clone https://github.com/horserr/XPolicyLab.git {candidate}"
        )
    return candidate
