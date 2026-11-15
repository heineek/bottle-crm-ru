# Обзор архитектуры

Этот раздел для разработчиков, которые расширяют или проверяют BottleCRM, а не для администраторов,
которые её разворачивают: для них есть раздел «Развёртывание на своём сервере». Здесь описано, как
устроен бэкенд: что выполняется до того, как запрос попадёт во view, за что отвечает каждое
Django-приложение и где искать подробности о мультитенантности, аутентификации, правах доступа,
модели данных и фоновых задачах.

## Три клиента {#the-three-clients}

Веб-приложение на SvelteKit (`frontend/`), мобильное приложение на Flutter (`mobile/`) и любая
сторонняя интеграция обращаются к одному и тому же бэкенду на Django REST Framework (`backend/`)
через один и тот же JSON API: отдельного мобильного API или набора эндпоинтов только для веба нет.
`crm/urls.py` подключает весь API под `/api/` и делит его на `common.app_urls` (аутентификация,
управление организациями и профилями, команды, теги, уведомления, документы, дополнительные поля и
по одному маршруту в `accounts`, `contacts`, `leads`, `opportunity`, `tasks`, `cases`, `invoices`,
доски, рабочие часы и макросы) и `invoices.public_urls` для анонимных эндпоинтов клиентского
портала. Поскольку все клиенты используют один API, правило авторизации, проверяемое во view,
защищает сразу все три клиента. И наоборот, правило, проверяемое только в интерфейсе SvelteKit, не
защищает ни одного из них: скрипт или изменённая сборка мобильного приложения обращаются к API
напрямую.

## Жизненный цикл запроса {#request-lifecycle}

Тенант определяется в middleware, ещё до выполнения кода любого view, в фиксированном порядке,
заданном в `MIDDLEWARE` в `backend/crm/settings.py`:

```python
MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
    "corsheaders.middleware.CorsMiddleware",
    "crum.CurrentRequestUserMiddleware",
    "common.middleware.get_company.GetProfileAndOrg",
    "common.middleware.rls_context.RequireOrgContext",
]
```

Два middleware, важных для мультитенантности, выполняются последними, в таком порядке:

1. **`GetProfileAndOrg`** (`backend/common/middleware/get_company.py`) определяет, кто вызывает
   API и от имени какой организации. Для запроса с персональным токеном доступа он сначала
   разбирает токен, намеренно до ветки JWT, чтобы PAT никогда не попал в декодер JWT. Для запроса с
   JWT он декодирует access-токен, читает claim `org_id` из подписанного payload (никогда из
   заголовка или тела запроса, см. [Аутентификация](authentication.md#claims)) и ищет активный
   `Profile` для пары `user_id`/`org_id`; только если такой профиль существует, он устанавливает
   `request.profile` и `request.org`. Для запроса с API-ключом организации он сопоставляет ключ с
   первым активным профилем `ADMIN` этой организации. В любом случае организация в запросе
   является фактом, который сервер вывел и проверил сам, а не значение, принятое от клиента как есть.
2. **`RequireOrgContext`** (`backend/common/middleware/rls_context.py`) выполняется следующим и
   делает две вещи. Он отклоняет с кодом 403 любой запрос к неисключённому пути, если
   `request.org` не был установлен на предыдущем шаге. И (именно этот шаг на деле включает изоляцию
   тенантов) он устанавливает переменную сессии PostgreSQL `app.current_org` в id этой организации
   через `SELECT set_config('app.current_org', %s, false)` и сбрасывает её в пустую строку после
   ответа. Каждая политика Row-Level Security в схеме опирается на эту одну переменную сессии;
   подробнее в разделе [Мультитенантность и RLS](multi-tenancy-and-rls.md).

Итак, порядок такой: сначала из JWT определяются и проверяются пользователь и организация, и только
после успеха база данных узнаёт, строки какой организации доступны остальной части запроса. View
никогда не выполняется раньше, чем завершатся оба шага: `RequireOrgContext` стоит в списке выше
после `GetProfileAndOrg` и при отсутствии контекста сам возвращает ответ (403), не вызывая
`get_response`, поэтому запрос, для которого не удалось определить тенант, никогда не доходит до
маршрутизации URL.

Уровнем выше middleware собственная аутентификация DRF выполняется при диспетчеризации view
(`DEFAULT_AUTHENTICATION_CLASSES` в `REST_FRAMEWORK`: `PATAuthentication`, затем
`JWTAuthentication` из simplejwt, затем `APIKeyAuthentication`) и заполняет `request.user` для
`IsAuthenticated` и подобных классов прав. Это второй, независимый проход по тем же учётным
данным. `PATAuthentication` повторно использует PAT, уже разобранный middleware (сохранённый как
`request._pat`), чтобы не искать его второй раз, а вот JWT декодируется дважды: middleware для
контекста организации и `JWTAuthentication` для `request.user`. У каждого view по-прежнему должны
быть правильно заданы `permission_classes`: аутентификация лишь устанавливает личность, но не то,
что этой личности разрешено. См. [Права и роли](permissions-and-roles.md).

## Структура бэкенда {#backend-layout}

```
backend/
├── crm/            # Project config: settings.py, urls.py, celery.py
├── common/         # Cross-cutting: User/Org/Profile, middleware, RLS config, permissions,
│                   # auth views, personal access tokens, notifications, tags, teams, custom
│                   # fields, documents, packs, security audit log
├── accounts/       # Account (company/customer) records
├── contacts/       # Contact (person) records
├── leads/          # Leads, lead pipelines/stages, lead-to-account conversion
├── opportunity/     # Sales pipeline: Opportunity, line items, stage aging, sales goals
├── cases/          # Support tickets: Case, SLAs, CSAT, escalation/routing, inbound email
├── tasks/          # Task management and Kanban boards (Board/BoardColumn/BoardTask)
├── invoices/        # Billing: invoices, estimates, recurring invoices, products, payments,
│                    # and the anonymous client-portal views (invoices.public_urls)
├── orders/          # Sales orders and order line items
├── business_hours/  # Per-org working-hours calendars that SLA timers honor
└── macros/          # Canned responses / saved replies
```

Приложение `common` единственное, от которого все остальные зависят в самом механизме
мультитенантности. Ему принадлежат модели `User`/`Org`/`Profile`, конфигурация RLS
(`common/rls/`), классы прав (`common/permissions.py`) и все пути аутентификации
(`common/views/auth_views.py`, `common/pat_auth.py`, `common/external_auth.py`). *Модели* каждого
предметного приложения строятся поверх `common` (`BaseModel`/`BaseOrgModel` из `common.base`,
`Org`/`Profile` из `common.models`), но никогда наоборот. Однако это одностороннее правило не
распространяется на собственные *views* `common`: некоторые из них сквозные по своей природе и
напрямую импортируют модели предметных приложений. Дашборд (`common/views/dashboard_views.py`),
глобальный поиск (`common/search_views.py`), подсчёт использования тегов
(`common/views/tags_views.py`) и применение отраслевых пакетов (`common/packs/applier.py`)
подтягивают `Lead`, `Opportunity`, `Case` и другие модели, потому что агрегация по всем
предметным приложениям и есть назначение этих views. Строго односторонним остаётся только уровень
моделей.

Django-приложения `teams`, упоминаемого в некоторых старых документах и комментариях, больше не
существует как отдельного приложения: `Teams` теперь модель в `common/models.py`, а в
`INSTALLED_APPS` в `backend/crm/settings.py` есть закомментированная строка
`# "teams",  # Merged into common app`, отмечающая, где оно раньше было.
