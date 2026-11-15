# Пример на Python

## Что делает пример {#what-this-does}

Полный готовый к запуску скрипт, который работает с REST API BottleCRM на чистом Python: получает
токен доступа, выводит список лидов организации и создаёт лид.

«Получает токен» здесь означает чтение **персонального токена доступа** (`bcrm_pat_…`) из окружения,
а не прохождение одного из интерактивных сценариев входа из раздела
[Аутентификация](../api/authentication.md). PAT BottleCRM выдаёт именно для того, чтобы скрипту не
нужны были браузер, секрет OAuth-клиента или обмен письмами со ссылкой для входа ради простых вызовов
API. Как он аутентифицирует и что наследует, описано в разделе
[Токены и API-ключи](../api/tokens-and-api-keys.md#personal-access-tokens). Создать его можно двумя
способами, и подходящий зависит от вашей роли: **администратор** может сделать это на странице CRM
**Настройки → API-токены** (`/settings/api-tokens`). Эта страница доступна только администраторам (на
ней перечислены все токены организации, а не только ваши), поэтому пользователь без прав
администратора видит «Только для администраторов» и до формы создания не доходит. **Любая роль** может вместо этого
напрямую вызвать `POST /api/profile/tokens/`: это тот же эндпоинт самообслуживания, в который
отправляет данные форма создания на странице настроек. Этот вариант подходит, если вы не
администратор или просто хотите получить токен без интерфейса. Для локального бэкенда, который вы
запускаете сами, быстрее всего воспользоваться Django shell:

```bash
cd backend
uv run python manage.py shell -c "
from common.models import Profile, PersonalAccessToken
p = Profile.objects.filter(role='ADMIN', is_active=True).first()
print(PersonalAccessToken.generate(p, 'python-sample')[0])
"
```

Команда один раз выводит исходный токен `bcrm_pat_…`. Скопируйте его: получить его повторно позже
невозможно.

## Скрипт {#the-script}

```python
#!/usr/bin/env python3
"""List an org's leads and create one, using a BottleCRM personal access token.

Usage:
    BCRM_BASE_URL=http://localhost:8000 BCRM_TOKEN=bcrm_pat_... python leads_sample.py

See docs/api/tokens-and-api-keys.md for how to mint BCRM_TOKEN, and
docs/api/leads.md for the shape of the /api/leads/ responses this script reads.
"""

import os
import sys
import time

import requests

BASE_URL = os.environ.get("BCRM_BASE_URL", "http://localhost:8000").rstrip("/")
TOKEN = os.environ.get("BCRM_TOKEN")

if not TOKEN:
    sys.exit(
        "Set BCRM_TOKEN to a bcrm_pat_... personal access token "
        "(see docs/api/tokens-and-api-keys.md)."
    )

session = requests.Session()
session.headers.update(
    {
        "Authorization": f"Bearer {TOKEN}",
        "Accept": "application/json",
    }
)


def list_leads():
    """GET /api/leads/, the response splits leads into open/closed sections
    rather than one flat list; see docs/api/leads.md#list-leads."""
    resp = session.get(f"{BASE_URL}/api/leads/")
    resp.raise_for_status()
    data = resp.json()
    open_section = data["open_leads"]
    leads = open_section["open_leads"]
    print(
        f"{len(leads)} open lead(s) on this page "
        f"(of {open_section['leads_count']} total open):"
    )
    for lead in leads:
        name = f"{lead.get('first_name') or ''} {lead.get('last_name') or ''}".strip()
        print(
            f"  - {name or '(no name)'} <{lead.get('email') or 'no email'}> "
            f"[{lead.get('status')}]"
        )
    return data


def create_lead():
    """POST /api/leads/. A 200 with {"error": false, ...} is success; the
    response does not echo the created record, so we look it up afterward."""
    email = f"sample.lead+{int(time.time())}@example.com"
    payload = {
        "first_name": "Sample",
        "last_name": "Lead",
        "email": email,
        "status": "assigned",
        "source": "other",
    }
    resp = session.post(f"{BASE_URL}/api/leads/", json=payload)
    body = resp.json()
    if resp.status_code >= 400 or body.get("error"):
        sys.exit(f"Create failed ({resp.status_code}): {body}")
    print(f"Create response: {body}")
    return email


def find_by_email(email):
    """GET /api/leads/?email=...; `email` is a case-insensitive contains
    filter (docs/api/conventions.md#filtering-and-search), which is fine here
    since the address we just created is unique in this org."""
    resp = session.get(f"{BASE_URL}/api/leads/", params={"email": email})
    resp.raise_for_status()
    matches = resp.json()["open_leads"]["open_leads"]
    if matches:
        print(f"Found the new lead: id={matches[0]['id']}")
    else:
        print("New lead not on this page (increase limit/offset to find it).")


if __name__ == "__main__":
    print("Listing existing leads...")
    list_leads()
    print("\nCreating a lead...")
    new_email = create_lead()
    print("\nConfirming it was created...")
    find_by_email(new_email)
```

## Запуск {#running-it}

Сохраните скрипт как `leads_sample.py`. Вам нужен доступный бэкенд BottleCRM (локальный или
развёрнутый на своём сервере) и персональный токен доступа для профиля в нужной организации, созданный так, как
описано [выше](#what-this-does).

`requests` не входит в зависимости ни этого сайта документации, ни фронтенда самой CRM. Проще всего
запустить скрипт, ничего не устанавливая в проект, через `uv run` с зависимостью, указанной прямо в
команде:

```bash
BCRM_BASE_URL=http://localhost:8000 \
BCRM_TOKEN=bcrm_pat_... \
  uv run --with requests python leads_sample.py
```

Или в обычном virtualenv: `pip install requests`, а затем `python leads_sample.py` с теми же двумя
переменными окружения.

**О проверке:** этот скрипт проверен статически: каждый URL и каждое поле сверены с разделами
[Лиды](../api/leads.md) и [Соглашения](../api/conventions.md), а весь скрипт проверен на корректность
синтаксиса Python. На живой базе данных он не запускался, чтобы не записывать строку в общий
экземпляр, который эта документация не создавала. Пример вывода ниже иллюстративный, а не снятый с
реального запуска:

```text
Listing existing leads...
3 open lead(s) on this page (of 3 total open):
  - Jordan Blake <jordan.blake@example.com> [assigned]
  - Priya Shah <priya.shah@example.com> [in process]
  - (no name) <no email> [assigned]

Creating a lead...
Create response: {'error': False, 'message': 'Lead Created Successfully'}

Confirming it was created...
Found the new lead: id=3f2a1c9e-....
```

Ошибка валидации (например, если запустить скрипт дважды в одну и ту же секунду и сгенерированный
email совпадёт) возвращается как `400`, и скрипт завершается с телом ошибки, которое вернул
BottleCRM, согласно разделу [Ошибки](../api/errors.md#validation-errors):

```text
Create failed (400): {'error': True, 'errors': {'email': ['Another lead in this organisation already uses that email address.']}}
```
