# Adding a string

Every user-facing string goes through its layer's catalog. Write the English exactly as a user
should read it, and add every other shipped language at the same time: the [checks](index.md#the-checks)
fail on a key that is missing in any language. Use the terms of the language's glossary (for
Russian, the [Russian glossary](glossary-ru.md)).

## API {#api}

Wrap the text in `gettext` (inside a function) or `gettext_lazy` (at module or class level), with
named placeholders: `_("No team named %(name)s") % {"name": name}`. Use `ngettext` for counts and
`pgettext_lazy` when the same English word needs a different form by entity, as status labels do
(`pgettext_lazy("ticket status", "Closed")`). Templates use `{% translate %}` and
`{% blocktranslate trimmed %}`. Mail sent outside a request (Celery) picks its language with
`common.locale.language_for_user(user)` or `language_for_org(org)`.

Then, from `backend/`:

```bash
uv run python manage.py update_messages            # refresh every app's catalogs
# translate the new entries in <app>/locale/<lang>/LC_MESSAGES/django.po
uv run python manage.py update_messages --compile  # build the .mo files the server reads
```

Commit the `.po` and the `.mo` together. Do not run `makemessages` from inside an app directory: an
app's own `tasks.py` hides the `tasks` app there. `update_messages` sets Django up first and skips
everything outside the project's own apps.

## Web {#web}

Add the key to `frontend/messages/<module>/en.json` and every other locale file beside it, then
call it: `import { m } from '#lib/paraglide/messages.js'` and `m.leads_list_empty_title()`. Keys
are global, so prefix them with the module. Counts are plurals:

```json
"leads_count": [{
  "declarations": ["input count", "local countPlural = count: plural", "local countShown = count: number"],
  "selectors": ["countPlural"],
  "match": { "countPlural=one": "{countShown} lead", "countPlural=other": "{countShown} leads" }
}]
```

Each language lists the plural forms it needs (Russian: `one`, `few`, `many`, `other`); the test
reads them from `Intl.PluralRules`, so a missing form fails it.

- Never call `m.*()` at module load: a constant built that way keeps the language of the first
  request. Use a function or a getter.
- To style part of a sentence (a number in `v2-num`, a bold name), pass `slot('name')` as the
  placeholder and render `messageParts(text)` from `#lib/utils/message-parts.js`, instead of
  splitting the sentence into fragments. Word order differs between languages; a sentence glued
  from pieces cannot follow it.
- Dates and numbers go through `#lib/v2/format.js`, which formats with the active locale.
- `pnpm i18n` rebuilds the generated code in `src/lib/paraglide/` (git-ignored); `pnpm check` and
  `pnpm test` run it first, and the Vite plugin does it during `pnpm dev` and `pnpm build`.

## Mobile {#mobile}

Add the key to `mobile/lib/l10n/parts/<module>/en.json` (with its `@key` metadata for
placeholders) and the other locale files beside it, then rebuild:

```bash
dart run tool/l10n_merge.dart && flutter gen-l10n
```

Commit the merged `lib/l10n/app_<lang>.arb` files; the generated Dart is git-ignored. Read the
string with `context.l10n.leadsListEmptyTitle` in a widget, or `appL10n` where there is no
`BuildContext` (model labels, provider messages), at the moment the text is needed.

- Never keep a `DateFormat` or `NumberFormat` in a `static final`: build dates with
  `localDateFormat(english, skeleton)` from `lib/services/app_language.dart`.
- Do not send a translated label to the API: send the code.

## Things that look like strings but are not {#things-that-look-like-strings-but-are-not}

Leave these in English and out of the catalogs: error `code` values, enum and choice codes, field
names in payloads, webhook payloads and log lines.
