# Добавление строки

Каждая строка, которую видит пользователь, проходит через каталог своего уровня. Пишите английский
текст ровно так, как его должен прочитать пользователь, и сразу добавляйте все остальные языки из
поставки: [проверки](index.md#the-checks) падают на ключе, которого нет хотя бы в одном языке.
Используйте термины из глоссария языка (для русского это [Русский глоссарий](glossary-ru.md)).

## API {#api}

Оборачивайте текст в `gettext` (внутри функции) или `gettext_lazy` (на уровне модуля или класса), с
именованными плейсхолдерами: `_("No team named %(name)s") % {"name": name}`. Для количеств
используйте `ngettext`, а `pgettext_lazy`, когда одному английскому слову нужна разная форма в
зависимости от сущности, как у подписей статусов (`pgettext_lazy("ticket status", "Closed")`). В
шаблонах используются `{% translate %}` и `{% blocktranslate trimmed %}`. Письма, отправляемые вне
запроса (Celery), выбирают язык через `common.locale.language_for_user(user)` или
`language_for_org(org)`.

Затем из `backend/`:

```bash
uv run python manage.py update_messages            # refresh every app's catalogs
# translate the new entries in <app>/locale/<lang>/LC_MESSAGES/django.po
uv run python manage.py update_messages --compile  # build the .mo files the server reads
```

Коммитьте `.po` и `.mo` вместе. Не запускайте `makemessages` из каталога приложения: собственный
`tasks.py` приложения перекрывает там приложение `tasks`. `update_messages` сначала настраивает
Django и пропускает всё, что лежит вне собственных приложений проекта.

## Веб {#web}

Добавьте ключ в `frontend/messages/<module>/en.json` и во все остальные файлы локалей рядом с ним,
затем вызовите его: `import { m } from '#lib/paraglide/messages.js'` и
`m.leads_list_empty_title()`. Ключи глобальные, поэтому начинайте их с префикса модуля. Количества
оформляются как множественное число:

```json
"leads_count": [{
  "declarations": ["input count", "local countPlural = count: plural", "local countShown = count: number"],
  "selectors": ["countPlural"],
  "match": { "countPlural=one": "{countShown} lead", "countPlural=other": "{countShown} leads" }
}]
```

Каждый язык перечисляет нужные ему формы множественного числа (русский: `one`, `few`, `many`,
`other`); тест берёт их из `Intl.PluralRules`, поэтому пропущенная форма его роняет.

- Никогда не вызывайте `m.*()` при загрузке модуля: константа, построенная так, сохранит язык
  первого запроса. Используйте функцию или геттер.
- Чтобы оформить часть предложения (число в `v2-num`, имя жирным), передайте `slot('name')` как
  плейсхолдер и выведите `messageParts(text)` из `#lib/utils/message-parts.js`, вместо того чтобы
  разбивать предложение на фрагменты. Порядок слов в языках разный, и предложение, склеенное из
  кусков, не может ему следовать.
- Даты и числа проходят через `#lib/v2/format.js`, который форматирует их по активной локали.
- `pnpm i18n` пересобирает сгенерированный код в `src/lib/paraglide/` (в git-ignore); `pnpm check`
  и `pnpm test` сначала запускают его, а плагин Vite делает это во время `pnpm dev` и `pnpm build`.

## Мобильное приложение {#mobile}

Добавьте ключ в `mobile/lib/l10n/parts/<module>/en.json` (с метаданными `@key` для плейсхолдеров)
и в остальные файлы локалей рядом с ним, затем пересоберите:

```bash
dart run tool/l10n_merge.dart && flutter gen-l10n
```

Коммитьте объединённые файлы `lib/l10n/app_<lang>.arb`; сгенерированный Dart-код в git-ignore.
Читайте строку через `context.l10n.leadsListEmptyTitle` в виджете или через `appL10n` там, где нет
`BuildContext` (подписи моделей, сообщения провайдеров), в тот момент, когда текст нужен.

- Никогда не храните `DateFormat` или `NumberFormat` в `static final`: стройте даты через
  `localDateFormat(english, skeleton)` из `lib/services/app_language.dart`.
- Не отправляйте в API переведённую подпись: отправляйте код.

## Что похоже на строки, но ими не является {#things-that-look-like-strings-but-are-not}

Оставляйте на английском и вне каталогов: значения `code` ошибок, коды перечислений и вариантов
выбора, имена полей в payload, payload вебхуков и строки логов.
