"""Every client offers the languages the API serves, and no other.

`settings.LANGUAGES` is the list the API answers in and serves at
`/api/org/locales/`. The web compiles its own list from
`frontend/project.inlang/settings.json`, and the phone from the ARB files
`mobile/tool/l10n_merge.dart` builds from `mobile/lib/l10n/parts/`. A
language added to one of the three and not the others shows a choice the
other two cannot render, so the three lists are compared here. See
`docs/EN/localization/adding-a-language.md`.
"""

import json
from pathlib import Path

import pytest
from django.conf import settings

REPO_ROOT = Path(settings.BASE_DIR).parent
WEB_SETTINGS = REPO_ROOT / "frontend" / "project.inlang" / "settings.json"
MOBILE_PARTS = REPO_ROOT / "mobile" / "lib" / "l10n" / "parts"

API_LANGUAGES = sorted(code for code, _name in settings.LANGUAGES)


def test_api_languages_include_the_source():
    assert settings.LANGUAGE_CODE in API_LANGUAGES


@pytest.mark.skipif(not WEB_SETTINGS.exists(), reason="no web client in this checkout")
def test_web_offers_the_api_languages():
    web = json.loads(WEB_SETTINGS.read_text(encoding="utf-8"))
    assert sorted(web["locales"]) == API_LANGUAGES
    assert web["baseLocale"] == settings.LANGUAGE_CODE


@pytest.mark.skipif(
    not MOBILE_PARTS.exists(), reason="no mobile client in this checkout"
)
def test_mobile_offers_the_api_languages():
    mobile = sorted({fragment.stem for fragment in MOBILE_PARTS.glob("*/*.json")})
    assert mobile == API_LANGUAGES
