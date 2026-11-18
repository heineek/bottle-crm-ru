# Localization

The interface ships in English, the source language. The API, the web app and the mobile app all
go through message catalogs, agree on which language to use, and are ready for a translation.
This section is for developers who want to add a string, fix a translation, or bring in a new
language.

| Page | Read it when |
|---|---|
| [Adding a string](adding-strings.md) | You add or change any text a user reads, in any of the three layers |
| [Adding a language](adding-a-language.md) | You want to translate BottleCRM into a language it does not ship yet |
| [Right-to-left languages](right-to-left.md) | The new language is written right to left (Persian, Arabic, Hebrew, Urdu) |

## What is translated

| Layer | Catalogs | Tooling |
|---|---|---|
| API | `backend/<app>/locale/<lang>/LC_MESSAGES/django.po` (and the compiled `.mo`), one per Django app | Django `gettext`, `manage.py update_messages` |
| Web | `frontend/messages/<module>/<lang>.json`, plus `frontend/messages/<lang>.json` for shared strings | [Paraglide JS](https://inlang.com/m/gerre34r/library-inlang-paraglideJs) (`project.inlang/settings.json`) |
| Mobile | `mobile/lib/l10n/parts/<module>/<lang>.json`, merged into `lib/l10n/app_<lang>.arb` | Flutter `gen-l10n` (`mobile/l10n.yaml`) |

API error messages, validation messages, emails, PDFs, choice labels (statuses, priorities) and
every screen of both clients go through these catalogs. Dates, numbers and money are formatted by
the locale (`Intl` on the web, `intl` on mobile), never by hand.

Catalogs are split by module so that two people translating different modules never edit the same
file, and so that a module can be reviewed, and shipped, on its own.

## Which language is used {#which-language-is-used}

One order on every layer, written three times so each layer can apply it without a round trip:

1. The user's own choice, `User.language`. Set on the profile page (web) or the Language screen
   under Profile (mobile), through `PATCH /api/profile/` with `{"language": "en"}`; an empty string
   clears it. It is shared by every organization the user belongs to.
2. The client's languages: the browser's or the phone's, sent as `Accept-Language`.
3. The organization's default, `Org.default_language`, which an admin sets on the organization
   settings page.
4. English.

| Layer | Where the order lives |
|---|---|
| API | `backend/common/locale.py` (`resolve_language`), activated per request by `GetProfileAndOrg` |
| Web | `frontend/src/lib/i18n/locale.ts` (`resolveLocale`), applied in `src/hooks.server.ts` |
| Mobile | `mobile/lib/services/app_language.dart` (`resolveLanguage`), applied by `languageProvider` |

The clients read the user's choice and the org default from the access token's `language` and
`org_settings.default_language` claims, so choosing a language refreshes the token. Both clients
send `Accept-Language` on every API call, so an error the API writes is in the same language as the
page around it. The web sets `lang` and `dir` on `<html>` from the chosen locale; Flutter sets the
text direction from the app locale itself.

Mail follows its reader: a member gets their own language (falling back to the org default), and a
customer (invoices, estimates, CSAT surveys, the portal) always gets the org default, since a
contact has no `User` to carry a choice. PDFs are always in the org default. Celery tasks pick the
language with `common.locale.language_for_user` or `language_for_org`.

Countries, currencies and the language list for pickers come from `GET /api/org/locales/`, already
named in the request's language, so neither client keeps its own translated country list.

## What is never translated {#what-is-never-translated}

Anything a tenant typed (record names, stage names, custom field labels, tags, `Org.terminology`
overrides from an industry pack), stored text such as audit log and activity rows, webhook
payloads, error `code` values, and log lines. A translation must never change what the API stores
or sends to another system: clients send codes, not translated labels.

## The checks {#the-checks}

These run in CI and fail on a half-done translation, so a missing string shows up in review rather
than as an English word in a translated screen.

| Check | What it catches |
|---|---|
| `backend/common/tests/test_language_lists.py` | The three layers offer different languages |
| `backend/common/tests/test_translations.py` | An untranslated or fuzzy `.po` entry, a stale `.mo`, an em dash, one English string translated two ways |
| CI "Check message catalogs are up to date" | A wrapped string with no catalog entry |
| `frontend/src/lib/i18n/messages.test.ts` | Missing keys, changed placeholders, a plural without the forms the language needs, a key two modules define |
| `frontend/src/lib/i18n/strategy.test.ts` | The Vite plugin and `pnpm i18n` compiled with different locale strategies |
| `mobile/test/unit/app_language_test.dart` | Missing keys or placeholders, an empty message, the language order |
| `mobile/test/unit/l10n_merge_test.dart` | ARB files that are stale against the fragments, a key two modules define |
