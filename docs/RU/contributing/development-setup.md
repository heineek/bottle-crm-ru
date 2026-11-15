# Настройка окружения разработки

Эта страница помогает запустить локально для разработки все три проекта BottleCRM из клона
репозитория (`backend/`, `frontend/`, `mobile/`). Точные требуемые версии (Python, PostgreSQL,
Node, pnpm) приведены в разделе [Требования](../self-hosting/requirements.md); здесь предполагается,
что они у вас уже установлены. Пошаговая установка с нуля (включая создание базы данных и `.env`)
описана в [Ручной установке](../getting-started/manual-setup.md): эта страница посвящена тому, что
важно именно для участия в разработке: запуску тестов, добавлению зависимостей и запуску мобильного
приложения вместе с двумя другими проектами.

## Бэкенд {#backend}

Бэкенд управляется через [`uv`](https://docs.astral.sh/uv/), а не через pip или вручную
активированное виртуальное окружение. `uv sync` читает `backend/pyproject.toml` и `backend/uv.lock`
и создаёт `backend/.venv/` с точно зафиксированными версиями зависимостей; после этого каждая
команда выполняется через `uv run <cmd>`, который сам находит это окружение, активировать его не
нужно.

```bash
cd backend
uv sync
cp .env.example .env
uv run python manage.py migrate
uv run python manage.py runserver
```

Сначала отредактируйте `.env`, если роль PostgreSQL, имя базы данных или URL Redis у вас
отличаются от значений по умолчанию. См. [Ручную установку](../getting-started/manual-setup.md) и
[Переменные окружения](../self-hosting/environment-variables.md).

Запускайте тесты из `backend/`. Флаги для быстрых итераций и значение маркеров описаны в разделе
[Тестирование](testing.md):

```bash
uv run pytest
```

Чтобы добавить зависимость, используйте `uv add`, а не ручную правку `pyproject.toml`: `uv add`
подбирает версию, записывает её в `pyproject.toml` и заново фиксирует `uv.lock` за один шаг, так
что два файла никогда не расходятся:

```bash
uv add <package>                # runtime dependency, added to [project.dependencies]
uv add --group dev <package>    # dev-only dependency (tests, tooling), added to [dependency-groups]
```

Чтобы обновить все зафиксированные версии в рамках текущих ограничений `pyproject.toml`, не добавляя
и не удаляя зависимости (например, чтобы получить исправление безопасности в транзитивной
зависимости), используйте `uv lock --upgrade`: он заново разрешает зависимости и перезаписывает
`uv.lock` на месте.

Сейчас `backend/pyproject.toml` объявляет две группы зависимостей: `dev` (`pytest`,
`pytest-django`, `pytest-cov`) и `docs` (`mkdocs-material`). `uv` считает `dev` группой по
умолчанию, поэтому `uv sync` без аргументов устанавливает её; `uv sync --group docs` устанавливает
`docs` **в дополнение к** `dev`, а не вместо неё. Поэтому задача CI `docs-build`, которая
выполняет ровно `uv sync --frozen --group docs`, может запустить `uv run pytest ...` на следующем
же шаге (см. [Pull request](pull-requests.md#what-ci-runs)). Прежде чем выполнять
`uv add black` или что-то подобное, прочитайте [Стиль кода](code-style.md): в этом репозитории
всё не так просто, как кажется.

## Фронтенд {#frontend}

Фронтенд использует [pnpm](https://pnpm.io/), в CI закреплена мажорная версия 10
(`.github/workflows/tests.yml`).

```bash
cd frontend
pnpm install
pnpm run dev
```

`pnpm run dev` запускает dev-сервер Vite на `http://localhost:5181`. В `frontend/vite.config.js`
не настроен прокси dev-сервера (записи `server.proxy` там нет), поэтому браузер обращается к
Django API напрямую, кросс-доменно: `frontend/src/lib/api.js` строит базовый URL из
`PUBLIC_DJANGO_API_URL`, а если переменная не задана, использует `http://localhost:8000/api`.
Значит, `CORS_ALLOWED_ORIGINS` вашего бэкенда должен включать `http://localhost:5181` (в
`backend/.env.example` это так по умолчанию: см. [Ручную установку](../getting-started/manual-setup.md)),
иначе каждый запрос с dev-сервера завершится ошибкой CORS, а не 404 или отказом в соединении, и
это легко ошибочно принять за проблему бэкенда.

## Мобильное приложение {#mobile}

```bash
cd mobile
flutter pub get
flutter run
```

Так приложение соберётся и запустится на подключённом эмуляторе или устройстве, но **с вашим
локальным бэкендом оно не будет работать, пока вы не измените константу времени компиляции**.
Если вы хотите проверять реальные вызовы API, а не только убедиться, что приложение собирается,
сначала прочитайте [Сборку и настройку](../mobile/build-and-configure.md) и
[Подключение к своему серверу](../mobile/connect-to-self-hosted.md).

## Запуск всего вместе {#running-everything}

Самый быстрый способ поднять весь стек (PostgreSQL, Redis, Django API, воркер Celery, планировщик
Celery beat и dev-сервер фронтенда) одновременно: Docker Compose из корня репозитория:

```bash
docker compose up --build
```

Что делает каждый сервис и как к нему обратиться, описано в разделе [Docker](../self-hosting/docker.md).
Если же запускать компоненты нативно, чтобы быстрее итерировать над бэкендом или фронтендом, нужно
самостоятельно запустить PostgreSQL и Redis, а затем каждую из этих команд в отдельном терминале:

```bash
# Terminal 1: API
cd backend && uv run python manage.py runserver

# Terminal 2: background jobs (recurring invoices, SLA scans, notification emails, ...)
cd backend && uv run celery -A crm worker --loglevel=INFO

# Terminal 3: frontend
cd frontend && pnpm run dev
```

Воркер Celery не обязателен для проверки большинства CRUD-эндпоинтов, но несколько функций
отправляют через него письма или выполняют запланированную работу. Что где выполняется, описано в
разделе [Фоновые задачи](../architecture/background-jobs.md); учтите, что `celery -A crm beat`
(планировщик, который на самом деле запускает десять описанных там периодических задач) является
четвёртым, отдельным процессом: Docker Compose запускает его за вас, а описанный выше нативный
способ нет.
