# Правила безопасности

BottleCRM является мультитенантным приложением, в котором данные каждой организации лежат в той же
базе данных, в тех же таблицах, рядом с данными всех остальных организаций. Правила на этой странице
существуют потому, что два способа всё испортить (один тенант читает или пишет данные другого, а
пользователь без прав администратора добирается до действий уровня администратора или платформы)
являются теми двумя исходами, которые каждое изменение, затрагивающее аутентификацию, разрешения или
сериализаторы, должно исключить до мёржа.

## Граница доверия {#the-trust-boundary}

Бэкенд (`backend/`) является единственной границей доверия в этой системе.
[Обзор архитектуры](../architecture/overview.md#the-three-clients) объясняет, почему это должно
выполняться на уровне устройства системы, а не только как правило: веб-приложение на SvelteKit,
мобильное приложение на Flutter и любая сторонняя интеграция обращаются к *одному и тому же* API на
Django REST Framework через одни и те же JSON-эндпоинты. Отдельного, более доверенного внутреннего
API нет. Правило, которое соблюдается только в интерфейсе SvelteKit (отключённая кнопка, скрытое
поле формы, проверка на клиенте), не защищает ни одного из трёх клиентов, потому что консоль
DevTools в браузере, изменённая сборка мобильного приложения или простой запрос `curl` попадают на
тот же эндпоинт напрямую, минуя всё, что предотвратил бы интерфейс. Каждое значимое ограничение
должно соблюдаться в представлении или сериализаторе DRF, и точка.

## Идентичность определяет сервер {#identity-is-server-derived}

Кто выполняет запрос, в какой организации он действует и какая у него роль: это факты, которые
сервер устанавливает и заново проверяет при каждом запросе, и они никогда не берутся из тела
запроса, строки запроса или собственного заголовка. В разделе
[Аутентификация](../architecture/authentication.md#claims) показан конкретный механизм: claim
`org_id` внутри подписанного JWT вызывающего не принимается на веру, middleware, который его
разрешает, заново сверяет его с активной строкой `Profile` при каждом запросе:

```python
profile = Profile.objects.select_related("org").get(
    user_id=user_id, org_id=org_id, is_active=True
)
```

Если поиск не удался (членство отозвано, профиль деактивирован), запрос получает 403 с просьбой
войти заново, вместо того чтобы продолжить по устаревшему claim. Практическое правило для любого
представления или сериализатора, которые вы пишете: идентичность берётся из `request.user` и
`request.profile`, которые middleware задаёт до запуска вашего кода (см.
[Обзор архитектуры](../architecture/overview.md#request-lifecycle)), и никогда из поля, присланного клиентом.
В частности, `role` в payload JWT служит лишь для удобства отображения; каждая настоящая проверка
разрешений читает `request.profile.role` свежим из базы данных, а не из токена.

## Ограничение по тенанту {#tenant-scoping}

Сопровождайте каждую проверку разрешений явным фильтром по организации. Это два независимых
механизма контроля, и ни один не заменяет другой. `HasOrgContext` (`backend/common/permissions.py`)
является стандартным классом разрешений почти в каждом представлении с привязкой к организации:

```python
class HasOrgContext(permissions.BasePermission):
    def has_permission(self, request, view):
        if not hasattr(request, "profile") or request.profile is None:
            return False
        if not hasattr(request, "org") or request.org is None:
            return False
        if not request.profile.is_active:
            return False
        return True
```

Он устанавливает, что «запрос выполняет реальный активный участник этой организации». Он не
фильтрует, какие строки возвращает представление. Каждый queryset всё равно должен сам добавлять
`Model.objects.filter(org=request.profile.org)`, а каждый `create()` / `serializer.save()` должен
явно передавать `org=request.profile.org` и никогда не принимать его из тела запроса. RLS
(PostgreSQL Row-Level Security) подстраховывает это на уровне базы данных, но это страховочная сеть
на случай, когда фильтр забыт, а не замена ему. Почему нужны оба уровня, см. в разделе
[Двухуровневый контракт](../architecture/multi-tenancy-and-rls.md#the-two-layer-contract), а полный
чек-лист для представления совершенно новой модели в разделе
[Добавление модели с привязкой к организации](adding-an-org-scoped-model.md).

## Поля, которыми владеет сервер {#server-owned-fields}

Любое поле, которое должен определять сервер (`org`, `created_by`, `profile`, флаг публикации или
видимости), никогда не должно задаваться из `request.data`. В этом коде для этого есть два
настоящих механизма, а не один:

**Объявите поле с `read_only=True` или перечислите его в `read_only_fields`.**
`TeamCreateSerializer` в `backend/common/serializer.py` объявляет
`read_only_fields = ("created_at", "created_by", "org")`; `leads/serializer.py` задаёт
`read_only_fields = ("id", "created_at", "updated_at", "org")` в `LeadStageSerializer` и
`LeadPipelineSerializer`; а `TimeEntrySerializer` (`backend/cases/serializer.py`) объявляет само
поле доступным только для чтения, `profile = ProfileSerializer(read_only=True)`, ровно по той
причине, с которой начинается этот раздел: `profile` означает того, кто записал время, и это должен
быть факт, который задаёт сервер, а не тот, который запрашивает клиент.

**Или вообще не принимайте поле через сериализатор и задавайте его явно в месте вызова.**
Docstring самого `TimeEntryCreateSerializer` говорит об этом прямо: «`case`, `profile`, and `org`
are injected by the view and not accepted from the client», и действительно, ни одного из трёх нет в
его `Meta.fields`. Представление (`backend/cases/time_views.py`) это подкрепляет:

```python
entry = TimeEntry.objects.create(
    org=request.profile.org,
    case=case,
    profile=request.profile,
    **serializer.validated_data,
)
```

`serializer.validated_data` может содержать только поля, которые сериализатор объявил изначально,
поэтому клиенту здесь нечего переопределить, даже угадывая имена полей. Это эквивалент извлечения
ключа из `request.data` перед `save()`, но обеспечивается он тем, чего нет в кортеже `fields`
сериализатора, а не извлечением во время выполнения.

Самый наглядный пример того, *почему* это важно, это `is_sample`: флаг, общий через одну
импортируемую константу `SAMPLE_DATA_HELP_TEXT` для восьми моделей: `Lead`, `Account`, `Contact`,
`Case`, `Opportunity`, `Task`, `Project` и `TimeEntry` (`grep -rl SAMPLE_DATA_HELP_TEXT backend/` находит её в `models.py`
каждого приложения, а также в `common/base.py`, где она определена один раз). `leads/serializer.py`
объявляет `read_only_fields = ("is_sample",)`. Сам текст подсказки, определённый один раз в
`backend/common/base.py` и общий для всех моделей с этим полем, формулирует обоснование как
инвариант безопасности, а не как документацию:

```python
SAMPLE_DATA_HELP_TEXT = (
    "True only for demo rows created by common.packs.applier._apply_sample_data. "
    "Server-set exclusively, never expose this as a writable field on any "
    "serializer. It is the sole key common.packs.applier.clear_sample_data uses "
    "to decide what to delete, so a client-writable path here would let a user "
    "mark an arbitrary real record as sample and have it deleted."
)
```

Если бы такое поле было доступно для записи, враждебному запросу вообще не понадобилась бы ошибка в
логике удаления. Достаточно было бы выставить флаг на чужой реальной записи, и законное действие
«очистить демонстрационные данные» удалило бы её само. Добавляя поле, которым должен владеть
сервер, спрашивайте себя, чего мог бы добиться клиент, задав его напрямую, а не только нужно ли
успешному сценарию, чтобы поле было доступно только для чтения.

## Докажите, что проверка разрешений может не пройти {#prove-permission-checks-can-fail}

Проверка разрешений, которая всегда даёт один и тот же ответ, не является проверкой. Это мёртвый
код в форме проверки, и в этом коде хорошо задокументирована история того, как ровно так и
случалось по ошибке. `Case.created_by` (как и `created_by` почти любой модели) является внешним
ключом на `User`, а не на `Profile`. Сравнение экземпляра `Profile` напрямую с ним,

```python
request.profile == self.object.created_by  # always False: Profile compared to a User FK
```

проходит проверку типов в Python и никогда не бросает исключение, но и никогда не равно `True`, что
молча превратило задуманную проверку «автор или администратор» в «только администратор» без
единой ошибки где-либо. В этом коде это не гипотеза: `git log -L` по `CaseAttachmentView.delete` в
`backend/cases/views.py` показывает коммит (`c9250dd`), diff которого заменяет именно это,

```diff
-            request.profile.role == "ADMIN"
-            or request.profile.is_admin
-            or request.profile == self.object.created_by
+            is_org_admin(request.profile)
+            or request.profile.user_id == self.object.created_by_id
```

Это подтверждает по реальной истории коммитов, а не по описывающему её комментарию, что сравнение
`Profile` с `User` было рабочим кодом, пока его не заменили на корректное по типам
`request.profile.user_id == self.object.created_by_id`.

Раздел [Права и роли](../architecture/permissions-and-roles.md#object-level-checks) подробно
описывает этот шаблон, в том числе в каких приложениях его исправили, а в каких, по последней
сверке этой страницы с исходниками, ещё нет; прочитайте его, прежде чем писать новое сравнение с
`created_by`, и сравнивайте `profile.user_id` с `obj.created_by_id`, а не `profile` с
`obj.created_by` напрямую.

Единственный способ узнать, что проверка может не пройти, это написать тест, который заставит её не
пройти. `leads/tests/test_lead_access_and_totals.py` формулирует правило, которому следуют его
тесты: «Every permission test asserts both directions. A check that can only return False is
indistinguishable from a check that is never reached». На практике это означает пару тестов, а не
один, например `opportunity/tests/test_sales_goals.py`:

```python
def test_create_goal_admin(self, admin_client, org_a):
    ...
    response = admin_client.post(self.GOALS_URL, data, format="json")
    assert response.status_code == 201

def test_create_goal_non_admin_forbidden(self, user_client):
    ...
    response = user_client.post(self.GOALS_URL, data, format="json")
    assert response.status_code == 403
```

Одиночный тест, проверяющий только случай `403`, прошёл бы одинаково и тогда, когда проверка
администратора работает правильно, и тогда, когда она из-за ошибки вроде описанной выше отказывает
*всем*, включая администратора. Только парный тест на `True` это ловит. Команды для быстрых
итераций см. в разделе [Тестирование](testing.md), а то же правило парных тестов применительно к
изоляции тенантов в разделе
[Добавление модели с привязкой к организации](adding-an-org-scoped-model.md#the-tests).
