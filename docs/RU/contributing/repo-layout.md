# Структура репозитория

Эта страница является картой, а не руководством. Она подсказывает, где искать, и ссылается на
страницы, которые объясняют, *почему* каждая часть устроена именно так.

## Верхний уровень {#top-level}

```
Django-CRM/
├── backend/             # Django REST Framework API. See Backend apps below
├── frontend/            # SvelteKit web app. See Frontend below
├── mobile/              # Flutter app. See Mobile below
├── docs/                # This documentation site (MkDocs Material)
├── docker/              # Docker-specific config: docker/postgres/init-rls-user.sql (creates the
│                        #   non-superuser RLS role) and docker/backend/entrypoint.sh. That's the
│                        #   whole directory, no Redis config lives here
├── mkdocs.yml           # Docs site config and nav
├── docker-compose.yml   # Full local stack. See Self-hosting → Docker
├── CONTRIBUTING.md      # The short version of this Contributing section
├── RLS_SETUP.md         # Stubbed pointer to PostgreSQL and RLS, kept only so links made before
│                        #   this documentation site existed still resolve; not a setup guide
│                        #   itself anymore
└── schema.yml           # Generated OpenAPI schema (drf-spectacular), not hand-maintained
```

Английская документация находится в `docs/EN/` и является источником истины, русский перевод
лежит в `docs/RU/` с теми же путями файлов; меняя страницу, обновляйте обе версии. Кроме того, в
`docs/` хранятся внутренние спецификации и планы в `docs/superpowers/` и `docs/EN/design/`. Они
исключены из собранного сайта (`exclude_docs` в `mkdocs.yml`) и не входят в опубликованную
документацию.

## Приложения бэкенда {#backend-apps}

`INSTALLED_APPS` в `backend/crm/settings.py` перечисляет Django-приложения проекта в таком порядке
(без записей Django, DRF и сторонних пакетов):

| Приложение | Отвечает за |
|---|---|
| `common` | Модели `User`/`Org`/`Profile`, настройку RLS, классы разрешений, все пути аутентификации (JWT, персональные токены доступа, API-ключи организации), уведомления, теги, команды, дополнительные поля, документы и отраслевые пакеты |
| `accounts` | Записи компаний (клиентов) |
| `cases` | Обращения в поддержку: `Case`, SLA, CSAT, эскалация и маршрутизация, входящая почта |
| `contacts` | Записи контактов (людей) |
| `leads` | Лиды, воронки и этапы лидов, конвертацию лида в компанию |
| `opportunity` | Воронку продаж: `Opportunity`, позиции, динамику этапов, цели и квоты продаж |
| `tasks` | Управление задачами и канбан-доски (`Board`/`BoardColumn`/`BoardTask`) |
| `invoices` | Биллинг (счета, коммерческие предложения, регулярные счета, товары, платежи) и анонимные представления клиентского портала |
| `orders` | Заказы и позиции заказов |
| `business_hours` | Календари рабочего времени организации, которые учитывают таймеры SLA |
| `macros` | Шаблонные ответы (сохранённые ответы) |

`common` является единственным приложением, от которого все остальные зависят в вопросах
мультитенантности: ему принадлежат `BaseModel` и `BaseOrgModel` (`common/base.py`: абстрактные
базовые классы, на которых строится каждая модель с привязкой к организации, см.
[Добавление модели с привязкой к организации](adding-an-org-scoped-model.md)), middleware
мультитенантности (`GetProfileAndOrg` из `common/middleware/get_company.py` и
`RequireOrgContext` из `common/middleware/rls_context.py`) и утилиты RLS
(`common/rls/__init__.py`; `ORG_SCOPED_TABLES`, `get_enable_policy_sql` и остальные генераторы
SQL). Как эти части работают вместе при обработке запроса, см. в
[Обзоре архитектуры](../architecture/overview.md#backend-layout), а саму модель
мультитенантности в разделе [Мультитенантность и RLS](../architecture/multi-tenancy-and-rls.md).

Каждое предметное приложение устроено похоже: `models.py` (или пакет `models/` в крупных
приложениях), `serializer.py`, один или несколько модулей представлений, `migrations/` и `tests/`.
`common` больше и менее единообразно, чем остальные, потому что в нём также находятся сквозные
представления: дашборд, глобальный поиск, счётчики использования тегов. Они подтягивают модели из
всех предметных приложений; почему однонаправленное правило для слоя моделей не распространяется
на представления, см. в [Обзоре архитектуры](../architecture/overview.md#backend-layout).

## Фронтенд {#frontend}

```
frontend/src/
├── lib/
│   ├── api.js, api-helpers.js   # API client (fetch/axios wrappers)
│   ├── components/              # Shared UI components (shadcn-svelte based)
│   ├── server/                  # Server-side load-function helpers
│   ├── shell/                   # App shell (nav, layout chrome)
│   ├── stores/                  # Svelte stores
│   └── v2/                      # Shared v2 design-system pieces (components, styles, formatters)
└── routes/
    ├── (app)/         # Authenticated routes, leads, accounts, contacts, opportunities
    │                  #   (as "pipeline"), tasks, tickets ("support"), invoices, and more
    ├── (no-layout)/   # Public routes, login and the rest of the pre-auth flow
    └── api/           # SvelteKit server routes (not the Django API)
```

Каждая страница в `routes/(app)/` читает и записывает данные через Django API, описанный в
остальной части этого сайта. Отдельной модели данных только для фронтенда нет.

## Мобильное приложение {#mobile}

```
mobile/lib/
├── config/     # API base URL and other compile-time configuration
├── core/       # Cross-cutting utilities
├── data/       # Data layer
├── providers/  # State management
├── routes/     # App routing
├── screens/    # UI screens
├── services/   # API and auth service classes
├── widgets/    # Shared widgets
└── main.dart   # Entry point
```

Как приложение подключается к бэкенду, см. в [Сборке и настройке](../mobile/build-and-configure.md),
а как получить подписанную сборку, в разделе [Релизные сборки](../mobile/release-builds.md).
