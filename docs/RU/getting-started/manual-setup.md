# Ручная установка

Запуск бэкенда, базы данных, Redis, Celery и фронтенда прямо на вашей машине, без Docker. Это
удобно, если вам нужна более быстрая итерация над кодом бэкенда, чем даёт контейнер с
примонтированным каталогом, или если вы настраиваете хост, где Docker недоступен.

## Требования {#prerequisites}

- **Python 3.12 или новее**: `backend/pyproject.toml` объявляет `requires-python = ">=3.12"`, а
  `backend/.python-version` фиксирует `3.12`.
- **[uv](https://docs.astral.sh/uv/)**: бэкенд управляется через uv, а не pip или созданное
  вручную виртуальное окружение. `uv sync` читает `backend/pyproject.toml` и `backend/uv.lock` и
  создаёт для вас `.venv/`; каждая команда бэкенда в этом руководстве выполняется через
  `uv run <cmd>`, который находит это окружение автоматически. Установите uv один раз для всей
  системы:

  ```bash
  curl -LsSf https://astral.sh/uv/install.sh | sh
  # or, on macOS: brew install uv
  ```
- **PostgreSQL**: единственный поддерживаемый бэкенд базы данных (`django.db.backends.postgresql`
  в `backend/crm/settings.py`); от него зависит Row-Level Security.
- **Redis**: используется как брокер Celery и хранилище результатов.
- **Node.js и [pnpm](https://pnpm.io/)**: для фронтенда на SvelteKit в `frontend/`.

## Бэкенд {#backend}

Из `backend/`:

```bash
cd backend
uv sync
```

Команда создаёт `.venv/` и устанавливает всё, что перечислено в `dependencies` файла
`pyproject.toml` (Django, DRF, Celery, `djangorestframework-simplejwt`, `weasyprint` и т. д.), в
версиях, зафиксированных в `uv.lock`.

Скопируйте пример файла окружения и настройте его под вашу локальную базу данных и Redis:

```bash
cp .env.example .env
```

`backend/crm/settings.py` загружает этот файл через `python-dotenv` (`load_dotenv()` при импорте),
поэтому всё, что вы запишете в `.env`, будет подхвачено при следующем запуске команды управления.
Как минимум сверьте `DBNAME`, `DBUSER`, `DBPASSWORD`, `DBHOST`, `DBPORT` с ролью базы данных,
которую вы создадите в следующем разделе.

Когда `.env` указывает на доступную базу данных, примените миграции:

```bash
uv run python manage.py migrate
```

И запустите dev-сервер:

```bash
uv run python manage.py runserver
```

По умолчанию он слушает `http://127.0.0.1:8000`.

## База данных {#database}

Настройка Django `DATABASES` (`backend/crm/settings.py`) читает `DBNAME`, `DBUSER`,
`DBPASSWORD`, `DBHOST` и `DBPORT` из окружения и, если они не заданы, по умолчанию подключается к
локальному суперпользователю `postgres`. Не оставляйте это значение по умолчанию: **роль, под
которой подключается Django, не должна быть суперпользователем PostgreSQL**, иначе Row-Level
Security обходится для каждого запроса этой роли, что бы ни говорили политики RLS.

Создайте отдельную роль без прав суперпользователя и базу данных, например:

```bash
sudo -u postgres psql
```

```sql
CREATE DATABASE crm_db;
CREATE USER crm_user WITH PASSWORD 'crm_password';
GRANT ALL PRIVILEGES ON DATABASE crm_db TO crm_user;
\connect crm_db;
GRANT ALL ON SCHEMA public TO crm_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO crm_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO crm_user;
```

Затем укажите её в `.env` (`DBNAME=crm_db`, `DBUSER=crm_user`, `DBPASSWORD=crm_password`,
`DBHOST=localhost`, `DBPORT=5432`) и выполните `uv run python manage.py migrate`.

Убедиться, что роль настроена правильно, можно командой управления RLS:

```bash
uv run python manage.py manage_rls --status
uv run python manage.py manage_rls --verify-user
```

## Redis и Celery {#redis-and-celery}

Redis должен быть доступен по URL из `CELERY_BROKER_URL` / `CELERY_RESULT_BACKEND` (в
`.env.example` оба по умолчанию `redis://localhost:6379/0`). Установите его локально через
менеджер пакетов или запустите тот же образ, что использует установка через Docker:

```bash
docker run -p 6379:6379 redis:7-alpine
```

Когда Redis доступен, запустите воркер Celery из `backend/`:

```bash
uv run celery -A crm worker --loglevel=INFO
```

`backend/crm/celery.py` также определяет набор периодических задач (генерация регулярных счетов,
проверки просроченных счетов и истёкших коммерческих предложений, проверки застрявших сделок и
достигнутых этапов целей, поиск нарушений SLA, очистка уведомлений и refresh-токенов) с
расписанием в стиле cron. Чтобы они запускались по расписанию, нужен ещё Celery beat в отдельном
терминале:

```bash
uv run celery -A crm beat --loglevel=INFO
```

Ни один из этих процессов не нужен, чтобы сам API отвечал на запросы. Они важны только для
фоновой и плановой работы.

## Фронтенд {#frontend}

Из `frontend/`:

```bash
cd frontend
pnpm install
```

Скопируйте пример файла окружения:

```bash
cp .env.example .env
```

Как минимум `PUBLIC_DJANGO_API_URL` должен указывать на ваш бэкенд (`http://localhost:8000`, если
вы используете порты из этого руководства). Затем запустите dev-сервер:

```bash
pnpm run dev
```

Он отдаёт приложение SvelteKit на `http://localhost:5181` (под капотом `vite dev`, согласно скрипту
`dev` в `frontend/package.json`).

## Запуск всех трёх {#running-all-three}

Полный локальный стек состоит из четырёх долгоживущих процессов в (как минимум) трёх терминалах,
и все они запускаются из описанного выше состояния:

```bash
# Terminal 1: from backend/
uv run python manage.py runserver

# Terminal 2: from backend/
uv run celery -A crm worker --loglevel=INFO

# Terminal 3: from frontend/
pnpm run dev
```

Redis и PostgreSQL должны уже работать до запуска любого из них (установленные локально или
запущенные как отдельные контейнеры, как показано выше). Добавьте четвёртый терминал для
`uv run celery -A crm beat --loglevel=INFO` из `backend/`, если нужно, чтобы срабатывали задачи по
расписанию.

Когда всё это запущено, перейдите к разделу [Первый вход](first-sign-in.md), чтобы получить
аутентифицированную сессию, и к разделу [Демоданные и отраслевые пакеты](demo-data.md), чтобы загрузить
примеры данных.
