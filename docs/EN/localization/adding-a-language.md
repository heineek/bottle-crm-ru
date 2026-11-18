# Adding a language

This page walks through bringing BottleCRM into a new language, with Persian (`fa`) as the running
example. A new language is translation work plus a handful of one-line registrations, since the
infrastructure is in place on all three layers. Expect roughly 1,900 API strings (about 260 of them
country and currency names), 4,600 web strings and 4,000 mobile strings.

Read [Localization](index.md) first for how a language is chosen, and [Adding a string](adding-strings.md)
for the catalog formats. If the language is written right to left, also read
[Right-to-left languages](right-to-left.md): the layout needs work beyond the translation.

## Before you start {#before-you-start}

1. **Open an issue** saying which language you are adding and whether you will cover the web app,
   the mobile app or both, so two people do not translate the same thing. If you only do the web
   app, say so: the mobile side is then tracked separately.
2. **Pick the language code.** Use the plain ISO 639-1 code (`fa`, `de`, `pt`), the same one in
   all three layers. Add a region only where the language really differs by region (`pt-BR` next to
   `pt`). The code is what `User.language` stores and what `Accept-Language` is matched against;
   a regional request (`fa-IR`) falls back to its base language automatically.
3. **Write a glossary.** Create `docs/EN/localization/glossary-<code>.md` (add it to the nav in
   `mkdocs.yml`; the [Russian glossary](glossary-ru.md) is a model) and fill in the terms before
   translating screens: lead, deal, account, ticket, pipeline, stage, status words and their
   grammatical gender if the language has one. A glossary agreed up front is what keeps four
   thousand strings, translated over weeks, saying the same thing.

## 1. API {#1-api}

Register the language in `backend/crm/settings.py`, under its own name, so the picker shows it in
that language whatever the interface is in:

```python
LANGUAGES = [("en", "English"), ("ru", "Русский"), ("fa", "فارسی")]
```

Then create and fill the catalogs:

```bash
cd backend
uv run python manage.py update_messages -l fa       # creates <app>/locale/fa/LC_MESSAGES/django.po
# translate every msgstr in each django.po
uv run python manage.py update_messages --compile   # builds the .mo files
```

- **Plural forms.** Set the `Plural-Forms` header of every new `.po` file to the language's rule
  (Persian: `nplurals=2; plural=(n > 1);`, the GNU gettext rule for the language) and give every
  `msgid_plural` entry that many `msgstr[n]` forms.
- **Contexts.** Entries with a `msgctxt` (`"ticket status"`, `"deal outcome"`) exist because some
  language needs a different word by entity. Translate each one for its entity even when the words
  come out the same in your language.
- **Emails.** Templates under `<app>/templates/` are translated through the same catalogs; check
  the subject lines too, they are separate entries.
- **Countries and currencies** are entries in `common`'s catalog (they feed `GET /api/org/locales/`).
- **No migration** is needed: `User.language` and `Org.default_language` are validated against
  `LANGUAGES`, not stored as choices.

`common/tests/test_translations.py` fails until every entry is translated and no entry is fuzzy.

## 2. Web {#2-web}

Add the code to `locales` in `frontend/project.inlang/settings.json`. Then copy every
`frontend/messages/**/en.json` to `fa.json` beside it and translate the values:

```bash
cd frontend
for f in messages/en.json messages/*/en.json; do cp "$f" "${f%en.json}fa.json"; done
```

- Keep the keys and the `{placeholders}` exactly; translate only the text.
- **Plurals.** A message that has `"match"` branches needs a branch for each plural category of the
  language. `Intl.PluralRules('fa')` has `one` and `other`; Polish has `one`, `few`, `many` and
  `other`; Arabic has six. `messages.test.js` reads the categories from `Intl` and fails on a
  missing one. A language may turn a plain message into a plural where English does not need one.
- **The language's own name** goes in `language_name` in `messages/fa.json` (`"فارسی"`). The
  profile picker shows each language through this key.
- **Formatting.** `intlLocale` in `src/lib/i18n/locale.ts` maps a UI locale to the `Intl` tag used
  for dates and numbers. An unknown locale is used as is, which is right for most languages
  (`fa` gives Persian digits and the Persian calendar). Add an entry only to pin a region (`pt` to
  `pt-BR`, for example).
- **Direction.** `textDirection` in the same file already knows the right-to-left languages and
  sets `dir="rtl"` on `<html>` for them.

Run `pnpm run check`, `pnpm run lint` and `pnpm test`; open the pages you translated and check
them at 390px (the phone breakpoint), where a longer language overflows first.

## 3. Mobile {#3-mobile}

Copy every fragment and drop the `@key` metadata entries from the copy (only the template keeps
them):

```bash
cd mobile
for f in lib/l10n/parts/*/en.json; do
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); json.dump({k:v for k,v in d.items() if not k.startswith("@")}, open(sys.argv[2],"w"), ensure_ascii=False, indent=2)' "$f" "${f%en.json}fa.json"
done
# translate lib/l10n/parts/*/fa.json, including "languageName" in parts/core
dart run tool/l10n_merge.dart && flutter gen-l10n
```

Plurals use ICU syntax (`{count, plural, =1{...} other{...}}`) and need the language's categories,
as on the web. `flutter_localizations` already translates Flutter's own widgets (date pickers,
copy/paste menus) for every major language and sets the text direction from the locale. Run
`flutter analyze` and `flutter test`, and add `*_fa_test.dart` screen tests that render the
busiest screens in the new language at phone width (the `*_ru_test.dart` tests are a template).

## 4. Register it everywhere at once {#4-register-it-everywhere-at-once}

`common/tests/test_language_lists.py` requires `settings.LANGUAGES`, the web `locales` and the
mobile fragments to offer exactly the same languages. A language offered by one client and not the
other would show a choice the other cannot render.

That decides how to split the work into pull requests, since the catalogs are checked for
completeness file by file:

1. **One PR per web module** (Leads, Contacts, Accounts, Deals, Tickets, Settings and so on), each
   adding that module's `messages/<module>/fa.json`, fully translated. These files are checked for
   completeness as soon as they exist, but nothing shows them until the language is registered.
2. **One PR for the API catalogs**, `<app>/locale/fa/`, not yet listed in `LANGUAGES`.
3. **One PR for the mobile fragments together with the registration**: `LANGUAGES`,
   `project.inlang` `locales` and `lib/l10n/parts/*/fa.json`, so the three lists change in the
   same commit and the language appears everywhere on the same day.

If you only translate the web app, stop after step 1 and say so in the issue: registering the
language then waits for the API and mobile catalogs.

## 5. Review {#5-review}

- Have a native speaker read the screens, not just the catalog files: a word that is right in a
  list can be wrong on a button.
- Check the glossary terms across all three layers: the same English word must not come out two
  ways (`test_translations.py` checks that within the API).
- Look at the longest screens at 390px: tables turned into cards, the tab bar, buttons with long
  labels, and the Today dashboard. Include a screenshot of the Leads page at that width in the
  first pull request.
- No em dash in any translation: the tests on all three layers reject it.

## Checklist {#checklist}

- [ ] Issue opened, glossary page added under `docs/EN/localization/`.
- [ ] API: language in `LANGUAGES`, every `django.po` translated, `.mo` compiled and committed.
- [ ] Web: code in `project.inlang/settings.json`, every `messages/**/<code>.json` translated, `language_name` set.
- [ ] Mobile: every `lib/l10n/parts/*/<code>.json` translated, ARBs merged and committed.
- [ ] Right-to-left: layout checked as in [Right-to-left languages](right-to-left.md).
- [ ] `pnpm run check`, `pnpm run lint`, `pnpm test`, `uv run pytest`, `flutter test` pass.
- [ ] Screenshots at 390px in the pull request.
