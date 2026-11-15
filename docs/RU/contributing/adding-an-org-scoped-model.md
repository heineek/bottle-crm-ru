# Добавление модели с привязкой к организации

Эта страница проводит через добавление новой модели, принадлежащей тенанту, от начала до конца на
разобранном примере: модели `CallLog`, которая хранит звонки по `Lead`. Поэтому каждый блок кода
можно действительно положить в дерево, это не псевдокод. Предполагается, что вы прочитали
[Мультитенантность и RLS](../architecture/multi-tenancy-and-rls.md), где объясняется, *зачем*
нужен каждый из этих шагов; эта страница является чек-листом того, *как* их выполнить.

## Чек-лист {#the-checklist}

1. **Наследуйтесь от `BaseOrgModel`** (`common.base`), чтобы модель получила внешний ключ `org`,
   первичный ключ UUID и поля аудита.
2. **Добавьте имя таблицы из `db_table` в `ORG_SCOPED_TABLES`** в `backend/common/rls/__init__.py`.
3. **Напишите миграцию**, которая вызывает `get_enable_policy_sql('your_table')` внутри операции
   `RunPython`, с записью в `dependencies`, гарантирующей, что таблица уже существует к моменту её
   выполнения.
4. **Фильтруйте каждый queryset**, затрагивающий модель, по `org=request.profile.org`.
5. **Передавайте `org=...` явно** в каждом `create()` / `serializer.save()` и никогда не доверяйте
   организации, присланной клиентом.
6. **Напишите тест и на разрешённый, и на запрещённый путь**: запрос внутри организации, который
   проходит, и запрос из другой организации, который не видит строку или не может её записать.

Шаги 2 и 3 обязательны оба, и ни один не заменяет другой: если зарегистрировать таблицу без
миграции, которая действительно вызывает `get_enable_policy_sql`, у таблицы вообще не будет
политик, а если миграция вызывает `get_enable_policy_sql` без регистрации таблицы в
`ORG_SCOPED_TABLES`, `manage_rls --status` никогда не сможет о ней сообщить, и пробел останется
невидимым для единственного инструмента, который должен его ловить. Оба сценария отказа подробнее
описаны в разделе [Типичные ошибки](../self-hosting/postgresql-and-rls.md#common-mistakes).

## Модель {#the-model}

```python
# backend/leads/models.py
from django.db import models

from common.base import BaseOrgModel

class CallLog(BaseOrgModel):
    """A record of an outbound or inbound call made against a lead."""

    DIRECTION_CHOICES = (
        ("OUTBOUND", "Outbound"),
        ("INBOUND", "Inbound"),
    )

    lead = models.ForeignKey(Lead, on_delete=models.CASCADE, related_name="call_logs")
    direction = models.CharField(max_length=10, choices=DIRECTION_CHOICES)
    notes = models.TextField(blank=True, default="")
    duration_seconds = models.PositiveIntegerField(default=0)

    class Meta:
        verbose_name = "Call Log"
        verbose_name_plural = "Call Logs"
        db_table = "call_log"
        ordering = ("-created_at",)
        indexes = [models.Index(fields=["org", "-created_at"])]
```

`BaseOrgModel` абстрактная, и здесь легко ошибиться: в этом коде есть живой пример такой ошибки.
Собственный класс `Meta` подкласса **не** наследует автоматически `indexes` абстрактного родителя
только потому, что модель наследуется от `BaseOrgModel`. `Order` (`backend/orders/models.py`, одна
из немногих моделей здесь, которая действительно наследуется от `BaseOrgModel`, а не объявляет
внешний ключ `org` вручную) объявляет собственный `Meta` с `db_table`, `verbose_name` и
`ordering`, но без `indexes`, поэтому во время выполнения `Order._meta.indexes` равен `[]`, а не
индексу `["org", "-created_at"]`, который определяет `BaseOrgModel.Meta`.
`backend/orders/migrations/0003_remove_order_orders_org_id_9026a7_idx_and_more.py` служит
доказательством: она удаляет именно этот индекс из `order` и `order_line_item`, таблиц, в которых
все остальные запросы фильтруются по `org`. `PersonalAccessToken` (`backend/common/models.py`)
является реальным примером правильного подхода в этом коде: его собственный `Meta` явно заново
объявляет `indexes = [models.Index(fields=["org", "-created_at"])]`, а не полагается на
наследование, и именно это копирует пример `CallLog` выше. `BaseOrgModel` надёжно даёт вам `id`
(первичный ключ UUID), `org`, `created_at`, `updated_at`, `created_by` и `updated_by` независимо
от того, объявляет ли ваша модель собственный `Meta`. Это поля и переопределённый `save()` в самом
классе, а не то, чем управляет `Meta`. Индекс `["org", "-created_at"]` является единственным в
`BaseOrgModel`, что ваш собственный `Meta` может молча потерять, поэтому объявляйте его заново (как
выше) каждый раз, когда вашей модели нужен собственный `Meta` для `db_table`, `ordering` или
чего-то ещё.

## Регистрация таблицы {#registering-the-table}

Добавьте имя таблицы из `db_table` (`call_log`, совпадает с `Meta.db_table` выше) в
`ORG_SCOPED_TABLES` в `backend/common/rls/__init__.py`. Сейчас в этом списке 61 запись (текущее
число смотрите в самом файле: оно меняется по мере роста проекта, так что не полагайтесь на число,
скопированное из документации); новая запись выглядит как любая другая:

```python
# backend/common/rls/__init__.py
ORG_SCOPED_TABLES = [
    ...
    "task",
    "invoice",
    "call_log",  # CallLog. Call records against a lead
    # Supporting entities
    "comment",
    ...
]
```

## Миграция RLS {#the-rls-migration}

Напишите отдельную миграцию для политик новой таблицы по образцу уже существующей в дереве,
`backend/opportunity/migrations/0012_enable_rls_sales_goal.py`:

```python
# backend/leads/migrations/0017_enable_rls_call_log.py
from django.db import connection, migrations

from common.rls import get_disable_policy_sql, get_enable_policy_sql

TABLE = "call_log"


def enable_rls(apps, schema_editor):
    if connection.vendor != "postgresql":
        return
    with connection.cursor() as cursor:
        cursor.execute(get_enable_policy_sql(TABLE))


def disable_rls(apps, schema_editor):
    if connection.vendor != "postgresql":
        return
    with connection.cursor() as cursor:
        cursor.execute(get_disable_policy_sql(TABLE))


class Migration(migrations.Migration):
    atomic = False

    dependencies = [
        ("leads", "0016_call_log"),  # the migration that actually creates call_log
    ]

    operations = [
        migrations.RunPython(enable_rls, disable_rls),
    ]
```

`atomic = False` совпадает со всеми миграциями RLS в этом коде: `DROP`/`CREATE POLICY` каждая
берёт блокировку `ACCESS EXCLUSIVE`, поэтому фиксация после каждого оператора вместо одной долгой
транзакции делает каждую блокировку короткой. `get_enable_policy_sql` сам начинается с
`DROP POLICY IF EXISTS` перед созданием любой из политик, поэтому миграция идемпотентна, если её
когда-нибудь запустят повторно.

!!! warning "Зависимость не для красоты. Ошибётесь в ней, и миграция молча ничего не сделает"
    `dependencies = [("leads", "0016_call_log")]` выше гарантирует, что Django применит эту
    миграцию *после* той, что выполняет `CreateModel` для `CallLog`. Если бы этой зависимости не
    было или она указывала бы на более раннюю миграцию, Django мог бы применить эту первой, и
    `ALTER TABLE "call_log" ENABLE ROW LEVEL SECURITY` для ещё не существующей таблицы вызвал бы
    явную ошибку, а не тихий сбой, *если только* миграция не написана защитно, с предварительной
    проверкой существования. `backend/common/migrations/0034_rls_pipeline_tables.py` написана
    именно в таком защитном стиле. Она проверяет `get_check_table_exists_sql()` перед обработкой
    каждой таблицы, потому что регистрирует шесть таблиц из трёх разных приложений в одной миграции
    и не может выразить одну чистую цепочку зависимостей для всех. Её собственный комментарий
    объясняет цену: ошибитесь там в зависимостях, и проверка молча напечатает
    `Skipping <table> (table does not exist)` и пойдёт дальше. Миграция «успешна», CI зелёный, а
    таблица просто никогда не получает политику. Для одной новой модели в одном приложении
    предпочитайте простую форму `opportunity/0012` выше (жёсткая зависимость, без проверки
    существования, настоящая ошибка, если порядок когда-либо нарушится), а не копирование
    защитного шаблона `0034`: громкий сбой во время разработки обходится гораздо дешевле политики,
    которая тихо так и не была создана.

## Представление {#the-view}

Каждому представлению, работающему с новой моделью, нужны и стандартные классы разрешений, и явный
фильтр по организации. RLS является страховочной сетью, а не контрактом (см.
[Двухуровневый контракт](../architecture/multi-tenancy-and-rls.md#the-two-layer-contract)):

```python
# backend/leads/views/call_log_views.py
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from common.permissions import HasOrgContext
from leads.models import Lead, CallLog
from leads.serializer import CallLogSerializer


class CallLogListView(APIView):
    permission_classes = (IsAuthenticated, HasOrgContext)

    def get(self, request, lead_id, format=None):
        lead = get_object_or_404(Lead, id=lead_id, org=request.profile.org)
        logs = CallLog.objects.filter(org=request.profile.org, lead=lead)
        return Response(CallLogSerializer(logs, many=True).data)

    def post(self, request, lead_id, format=None):
        lead = get_object_or_404(Lead, id=lead_id, org=request.profile.org)
        serializer = CallLogSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        serializer.save(org=request.profile.org, lead=lead, created_by=request.user)
        return Response(serializer.data, status=status.HTTP_201_CREATED)
```

Обратите внимание на две вещи: сам поиск `Lead` отфильтрован по организации
(`get_object_or_404(Lead, id=lead_id, org=request.profile.org)`), поэтому вызывающий из другой
организации получает 404 на родительском объекте ещё до запроса к `CallLog`, а `org` передаётся в
`serializer.save()` явно, а не берётся из `request.data`: это то же правило
[полей, которыми владеет сервер](security-rules.md#server-owned-fields), что действует везде.

## Тесты {#the-tests}

Пишите тесты в обе стороны, используя общие фикстуры из `backend/conftest.py` (`org_a`, `org_b`,
`admin_client`, `org_b_client` и остальные), по образцу реальной пары в
`opportunity/tests/test_sales_goals.py`. `org_a`, `org_b`, `admin_client` и `org_b_client` являются
настоящими общими фикстурами, уже определёнными в `backend/conftest.py`; `lead_in_org_a` ниже нет.
Это локальная фикстура уровня файла, которую определяет сам пример, так же как в
`leads/tests/test_lead_access_and_totals.py` есть собственный локальный помощник `_lead()`, а не
общий (общей фикстуры `Lead` с привязкой к организации для всего набора тестов нет, потому что
нужные тесту поля `Lead` слишком различаются, чтобы такую фикстуру имело смысл делать общей):

```python
import pytest

from leads.models import CallLog, Lead


@pytest.fixture
def lead_in_org_a(org_a):
    return Lead.objects.create(
        first_name="Ada",
        last_name="Lovelace",
        email="ada@example.com",
        status="in process",
        company_name="Analytical Engines",
        org=org_a,
    )


@pytest.mark.django_db
def test_admin_can_create_call_log(admin_client, org_a, lead_in_org_a):
    response = admin_client.post(
        f"/api/leads/{lead_in_org_a.id}/call-logs/",
        {"direction": "OUTBOUND", "notes": "Left voicemail"},
        format="json",
    )
    assert response.status_code == 201
    assert CallLog.objects.filter(lead=lead_in_org_a, org=org_a).exists()


@pytest.mark.django_db
def test_org_b_cannot_read_org_a_call_logs(org_b_client, org_a, lead_in_org_a):
    """The denied path: mirrors test_org_isolation in test_sales_goals.py."""
    CallLog.objects.create(lead=lead_in_org_a, org=org_a, direction="OUTBOUND")

    response = org_b_client.get(f"/api/leads/{lead_in_org_a.id}/call-logs/")

    # The parent Lead lookup is org-scoped, so a foreign org gets a 404 on the
    # lead itself, before the CallLog query ever runs.
    assert response.status_code == 404
```

Настоящую пользу приносит второй тест: набор тестов, который проверяет только разрешённый путь,
может проходить со 100% покрытием, даже если фильтра по организации выше нет вовсе. Почему именно
эта пара тестов к тому же единственное, что доказывает корректность фильтра ORM независимо от того,
действует ли RLS в окружении, где запускается тест, см. в разделе
[Тестирование](testing.md#the-sqlite-caveat).
