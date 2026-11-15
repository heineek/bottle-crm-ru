"""Every message catalog is complete, and its compiled .mo matches it.

English is the source language, so a missing or fuzzy entry does not fail a
request: the English text is shown instead, in a Russian interface, and nobody
notices. This makes it a test failure. The CI step "Check message catalogs are
up to date" covers the other half, a wrapped string with no entry at all.

A stale .mo is the same failure one step later: the .po is right, the server
reads the .mo. Compared entry by entry rather than by rebuilding it, because
msgfmt versions do not produce identical bytes.
"""

import ast
import gettext

import pytest
from django.conf import settings

from common.management.commands.update_messages import app_dirs_with_locale

TARGET_LANGUAGES = [
    code for code, _name in settings.LANGUAGES if code != settings.LANGUAGE_CODE
]


def parse_po(path):
    """``[(msgctxt, msgid, msgid_plural, [msgstr...], fuzzy)]`` for the live entries.

    Just enough of the format makemessages writes: one entry per blank-line
    separated block, obsolete (``#~``) blocks skipped, the header left out.
    """
    entries = []
    for block in path.read_text(encoding="utf-8").split("\n\n"):
        lines = [line.strip() for line in block.splitlines() if line.strip()]
        if not lines or all(line.startswith("#") for line in lines):
            continue
        fuzzy = any(line.startswith("#,") and "fuzzy" in line for line in lines)
        fields = {}
        current = None
        for line in lines:
            if line.startswith("#"):
                continue
            if line.startswith('"'):
                fields[current] += ast.literal_eval(line)
                continue
            key, _sep, value = line.partition(" ")
            current = key
            fields[key] = ast.literal_eval(value)
        if not fields.get("msgid"):
            continue
        strs = [fields[k] for k in sorted(k for k in fields if k.startswith("msgstr"))]
        entries.append(
            (
                fields.get("msgctxt"),
                fields["msgid"],
                fields.get("msgid_plural"),
                strs,
                fuzzy,
            )
        )
    return entries


def _catalogs():
    return [
        pytest.param(
            root / "locale" / language / "LC_MESSAGES" / "django.po",
            id=f"{root.name}-{language}",
        )
        for root in app_dirs_with_locale()
        for language in TARGET_LANGUAGES
    ]


CATALOGS = _catalogs()


def test_there_are_catalogs():
    assert CATALOGS, "no app has a locale/ directory"


@pytest.mark.parametrize("language", TARGET_LANGUAGES)
def test_apps_agree_on_shared_strings(language):
    """Django merges every app's catalog into one, so a msgid two apps
    translate differently gets whichever one loads first, everywhere. Give the
    same English the same translation, or a context (pgettext) if it really
    means different things."""
    seen = {}
    conflicts = []
    for root in app_dirs_with_locale():
        po = root / "locale" / language / "LC_MESSAGES" / "django.po"
        if not po.exists():
            continue
        for ctxt, msgid, plural, strs, fuzzy in parse_po(po):
            key = (ctxt, msgid, plural)
            if key in seen and seen[key][1] != strs:
                conflicts.append(f"{msgid!r}: {seen[key][0]} vs {root.name}")
            seen.setdefault(key, (root.name, strs))
    assert not conflicts, "\n".join(conflicts)


@pytest.mark.parametrize("po", CATALOGS)
def test_catalog_is_complete(po):
    assert po.exists(), (
        f"{po} is missing: run makemessages -l {po.parts[-3]} in the app"
    )
    problems = []
    for ctxt, msgid, plural, strs, fuzzy in parse_po(po):
        if fuzzy:
            problems.append(f"fuzzy: {msgid!r}")
        elif not strs or any(not s for s in strs):
            problems.append(f"untranslated: {msgid!r}")
        elif any("\u2014" in s for s in strs):
            problems.append(f"em dash (house rule): {msgid!r}")
    assert not problems, "\n".join(problems[:20])


@pytest.mark.parametrize("po", CATALOGS)
def test_compiled_catalog_matches(po):
    mo = po.with_suffix(".mo")
    assert mo.exists(), f"{mo} is missing: run compilemessages in the app"
    with mo.open("rb") as fh:
        compiled = gettext.GNUTranslations(fh)
    stale = []
    for ctxt, msgid, plural, strs, fuzzy in parse_po(po):
        if fuzzy or not strs or not all(strs):
            continue
        if plural is None:
            got = compiled.pgettext(ctxt, msgid) if ctxt else compiled.gettext(msgid)
            if got != strs[0]:
                stale.append(msgid)
        else:
            for n in range(200):
                expected = strs[compiled.plural(n)]
                got = (
                    compiled.npgettext(ctxt, msgid, plural, n)
                    if ctxt
                    else compiled.ngettext(msgid, plural, n)
                )
                if got != expected:
                    stale.append(msgid)
                    break
    assert not stale, f"{mo} is stale, run compilemessages: {stale[:10]}"
