# Тестирование

## Запуск тестов {#running-tests}

Из `backend/`:

```bash
uv run pytest
```

`backend/pytest.ini` задаёт в `addopts` покрытие по умолчанию,
`--cov=. --cov-config=../.coveragerc --cov-report=term-missing --cov-report=html:htmlcov
--cov-report=xml:coverage.xml`, вместе с `--strict-markers --tb=short -v`. Поэтому обычный
`uv run pytest` всегда считает покрытие и записывает `backend/htmlcov/` и `backend/coverage.xml`,
даже для одного тестового файла.

Ограничить запуск одним приложением, одним файлом или ключевым словом можно так же, как в любом
проекте на pytest:

```bash
uv run pytest accounts/tests/                    # one app's test package
uv run pytest leads/tests/test_leads_kanban.py    # one file
uv run pytest -k "test_org_isolation"             # by keyword: matches the cross-tenant
                                                   #   isolation test present in most API test
                                                   #   modules (leads, cases, contacts, ...)
```

## Быстрые итерации {#fast-iteration}

Сбор покрытия и три формата отчётов выше заметно замедляют запуск. В цикле «правка, запуск,
правка» отключите покрытие и останавливайтесь на первой ошибке:

```bash
uv run pytest --no-cov -x
```

`--strict-markers` (тоже заданный в `addopts`) означает, что опечатка в **собственном** маркере
сразу роняет запуск, а не игнорируется молча. Каждый собственный маркер, который вы используете,
должен быть объявлен в списке `markers` в `pytest.ini`. Это не касается маркеров, которые
регистрирует сам плагин, например `@pytest.mark.django_db` (из `pytest-django`). Они работают, вообще
не упоминаясь в `pytest.ini`, поэтому все примеры на этой странице свободно используют `django_db`
вместе с единственным объявленным маркером.

## Маркеры {#markers}

`pytest.ini` объявляет один собственный маркер:

```ini
markers =
    postgres_only: marks tests that require PostgreSQL
```

`postgres_only` помечает тесты, которым нужен настоящий PostgreSQL: состояние политик RLS,
поведение изоляции под ролью, на которую действует RLS, и состояние соединения на уровне сессии.
Посмотреть их список можно командой `uv run pytest -m postgres_only --collect-only -q`.

## Оговорка про SQLite {#the-sqlite-caveat}

`crm.test_settings` (`backend/crm/test_settings.py`) является модулем настроек, на который
указывает `pytest.ini`, и его `DATABASES` жёстко задан как SQLite в памяти: он не читается из
переменной окружения и ни от чего не зависит. Docstring модуля прямо объясняет почему: «RLS
(Row-Level Security) is PostgreSQL-only and is skipped on SQLite». Это значит, что **запуск
`uv run pytest` по умолчанию не проверяет ни одной политики RLS**. Каждый тест работает с
движком базы данных, в котором вообще нет понятия безопасности на уровне строк. Всё, что обычно
должен ловить RLS, включая ошибку в фильтре по организации, этому набору тестов по умолчанию не
видно; проверяется только явный `Model.objects.filter(org=...)` в коде приложения. О том, почему
этот фильтр ORM должен быть корректен сам по себе, независимо от RLS, см.
[Мультитенантность и RLS](../architecture/multi-tenancy-and-rls.md#the-two-layer-contract).

Тесты `postgres_only` закрывают часть этого пробела. Под SQLite почти все они пропускаются, так
что зелёный запуск по умолчанию ничего о них не говорит. По-настоящему их запускают с
`crm.test_settings_postgres`, который меняет только базу данных и читает те же переменные `DB*`,
что и приложение:

```bash
DJANGO_SETTINGS_MODULE=crm.test_settings_postgres DBUSER=<role> DBPASSWORD=<password> \
  uv run pytest --no-cov -m postgres_only
```

**Роль не должна быть суперпользователем или иметь `BYPASSRLS`.** Любое из этого обходит все
политики, и проверки изоляции проходят независимо от того, существует политика или нет. Роли
нужен `CREATEDB`, чтобы pytest-django мог создать тестовую базу данных. Как настроить такую роль,
описано в разделе [PostgreSQL и RLS](../self-hosting/postgresql-and-rls.md#verifying-isolation);
там же описана команда `manage.py manage_rls --test`, которая проверяет изоляцию на реальной базе
данных вне набора тестов.

## Что запускает CI {#what-ci-runs}

`.github/workflows/tests.yml` запускает тесты бэкенда тремя способами:

1. **SQLite**: быстрый запуск, который считает покрытие, после проверки миграций:
   ```bash
   uv run python manage.py makemigrations --check --dry-run
   uv run pytest -m "not postgres_only" --tb=short -v
   ```
2. **PostgreSQL под суперпользователем**: весь набор без `postgres_only`, для того, чего не видит
   SQLite (объявленные длины строк, ограничения, настоящее приведение типов). Под
   суперпользователем RLS не действует, поэтому этот запуск ничего не доказывает об изоляции.
3. **PostgreSQL под `crm_ci`**, ролью `NOSUPERUSER NOBYPASSRLS`, только тесты `postgres_only`.
   Именно этот запуск проверяет изоляцию тенантов.

Разделение нужно потому, что общие фикстуры вставляют строки без заданного `app.current_org`, а
роль, на которую действуют политики, такое отклоняет. Проверка миграций роняет сборку, когда у
изменения модели нет миграции; что это означает для вашей работы, см. в разделе
[Pull request](pull-requests.md#what-ci-runs).
