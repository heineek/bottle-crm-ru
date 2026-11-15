"""docs/EN/ and docs/RU/ hold internal specs and plans beside published pages.

MkDocs copies every file under docs_dir into the built site, including files no
nav entry references. Without an explicit exclusion, implementation plans would
be published to a public documentation site. This test is the guard.
"""

import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest
from django.conf import settings

REPO_ROOT = Path(settings.BASE_DIR).parent
# English, and the Russian translation that inherits it.
MKDOCS_CONFIGS = [REPO_ROOT / "mkdocs.yml", REPO_ROOT / "mkdocs.ru.yml"]
INTERNAL_PREFIXES = ("superpowers", "design")


def _build_site(config: Path, destination: Path) -> None:
    subprocess.run(
        [
            "mkdocs",
            "build",
            "--strict",
            "-f",
            str(config),
            "-d",
            str(destination),
        ],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )


@pytest.mark.skipif(shutil.which("mkdocs") is None, reason="mkdocs not installed")
@pytest.mark.parametrize("config", MKDOCS_CONFIGS, ids=lambda p: p.name)
def test_built_site_contains_no_internal_artifacts(config):
    with tempfile.TemporaryDirectory() as tmp:
        destination = Path(tmp) / "site"
        _build_site(config, destination)
        leaked = sorted(
            str(p.relative_to(destination))
            for p in destination.rglob("*")
            if p.is_file() and p.relative_to(destination).parts[0] in INTERNAL_PREFIXES
        )
    assert not leaked, (
        "Internal artifacts were published to the docs site:\n"
        + "\n".join(leaked)
        + f"\n\nAdd the directory to `exclude_docs` in {config.name}."
    )


@pytest.mark.skipif(shutil.which("mkdocs") is None, reason="mkdocs not installed")
@pytest.mark.parametrize("config", MKDOCS_CONFIGS, ids=lambda p: p.name)
def test_strict_build_succeeds(config):
    # --strict turns broken internal links and missing nav targets into errors,
    # so this doubles as the link check for every page in the nav.
    with tempfile.TemporaryDirectory() as tmp:
        _build_site(config, Path(tmp) / "site")
