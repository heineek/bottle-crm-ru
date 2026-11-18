# Сделки

Маршруты в `backend/opportunity/urls.py`, представления разделены между
`opportunity/views/opportunity_views.py` (список и детальный просмотр) и
`opportunity/views/kanban_views.py` (доска этапов и перемещение). Правила пагинации, фильтрации и
структуры ответа, которые здесь подразумеваются и не повторяются, описаны в разделе
[Соглашения](conventions.md).

## Список сделок {#list-opportunities}

`GET /api/opportunities/` (`OpportunityListView.get`, `backend/opportunity/views/opportunity_views.py:272-274`)
возвращает один постраничный список и общие для организации `totals`, вычисленные по всему
отфильтрованному queryset, а не только по текущей странице (`get_totals`, `:73-110`):

```json
{
  "opportunities_count": 23,
  "totals": {
    "count": 23,
    "amount_sum": "184500.00",
    "weighted_sum": "97250.00",
    "by_currency": [{"currency": "USD", "amount_sum": "184500.00", "weighted_sum": "97250.00"}],
    "stalled_count": 2
  },
  "offset": 10,
  "per_page": 10,
  "page_number": [1],
  "opportunities": [ { "...": "OpportunitySerializer" } ],
  "accounts_list": [ { "...": "AccountSerializer" } ],
  "contacts_list": [ { "...": "ContactSerializer" } ],
  "tags": [ { "...": "..." } ],
  "stage": [["PROSPECTING", "Prospecting"], ["QUALIFICATION", "Qualification"]],
  "lead_source": [["call", "Call"], ["web form", "Web form"]],
  "currency": [["USD", "USD, Dollar"]]
}
```

`weighted_sum` представляет собой прогноз, `SUM(amount * probability / 100)`, в отличие от
`amount_sum`, то есть номинальной стоимости всех открытых и закрытых сделок в отфильтрованном наборе.
Сделки в разных валютах никогда не складываются, поскольку курсов обмена нет: обе величины содержат
простую сумму, если в отфильтрованных сделках не больше одной валюты, и `null`, если их несколько, а
`by_currency` перечисляет `{currency, amount_sum, weighted_sum}` по каждой валюте в порядке кодов.
Сделка без валюты учитывается в валюте организации по умолчанию. `stalled_count` использует те же
пороги устаревания по этапам, что и `?rotten=true` ниже и `Opportunity.get_aging_status()`; см.
[Этапы](#stages). Вызывающий без прав администратора видит только сделки, которые он создал или за
которые отвечает (`:119-131`).

Фильтры: `name`, `search` (оба `icontains` только по `name`; `search` здесь **не** объединяет через
OR несколько полей, как в [лидах](leads.md#list-leads)); `account` (точное совпадение); `stage`
(**`__contains`, а не точное совпадение**. Почему это важно, см. в разделе [Этапы](#stages));
`lead_source` (точный ключ, как у `source` лида; до django-crm 1.26.0 искалось вхождение подстроки);
`tags`, `assigned_to` (можно повторять, списки id); `created_at__gte/lte`,
`closed_on__gte/lte`, `amount__gte/lte`; `cf_<key>`; `pipeline` (id воронки, точное совпадение); и
два булевых флага: `open=true` (исключает этапы выигрыша и проигрыша) и `rotten=true` (только
застрявшие сделки). См. [Этапы](#stages). Ключ `stage` в ответе перечисляет этапы воронки по
умолчанию в виде пар `[code, label]`.

## Создание сделки {#create-an-opportunity}

`POST /api/opportunities/` (`OpportunityListView.post`, `opportunity_views.py:292-413`) проверяется
сериализатором `OpportunityCreateSerializer` (`opportunity/serializer.py:199-297`); см.
[Поля](#fields). При успехе (`200`):

```json
{"error": false, "message": "Opportunity Created Successfully", "id": "<uuid>"}
```

**`name` должно быть уникальным в пределах организации без учёта регистра** (`validate_name`,
`opportunity/serializer.py:213-228`). Сериализатор также обеспечивает на уровне API два правила,
которые `Opportunity.clean()` формулирует на уровне модели. Сделкам на этапе выигрыша или проигрыша
нужна дата закрытия, а сделкам на этапе выигрыша нужна сумма (`validate()`; см. [Этапы](#stages)),
потому что `ModelSerializer` из DRF никогда не вызывает `Model.clean()`, и без этого собственные
правила модели проверялись бы только модульными тестами модели, но никогда через API.
`contacts`, `tags`, `teams` и `assigned_to` разрешаются из тела запроса тем же способом списка id,
что и у [лидов](leads.md#create-a-lead) и [компаний](accounts.md#create-an-account)
(`opportunity_views.py:317-376`); `opportunity_attachment` принимается как multipart-файл.

## Получение, изменение, удаление {#retrieve-update-delete}

`GET /api/opportunities/{id}/` (`OpportunityDetailView.get`, `opportunity_views.py:661-736`) ищет
сделку только в организации вызывающего. В отличие от лидов, компаний и контактов, этот поиск
возвращает `None`, а не выбрасывает исключение, поэтому отсутствующий id или id из другой
организации возвращается как явный ответ `404` (`"error": true, "errors": "Opportunity not found."`,
`:663-667`), а не через `get_object_or_404` из Django. Затем `assert_deal_access` (`:423-447`)
требует, чтобы вызывающий был администратором, создателем сделки или одним из ответственных, иначе
запрос отклоняется с `403`. Ответ вкладывает запись под ключ `opportunity_obj` и также возвращает
`comments`, `attachments`, `contacts`, `users`, `stage` (этапы собственной воронки сделки в виде пар
`[code, label]`), `lead_source`, `currency`, `comment_permission`, `users_mention` и
`custom_field_definitions`.

`PUT /api/opportunities/{id}/` (`:464-596`) и `PATCH /api/opportunities/{id}/` (`:831-953`) оба
проверяют `assert_deal_access` и оба записывают `closed_by = request.profile` и сохраняют его явным
`.save()` всякий раз, когда запрос указывает этап типа «выигрыш» или «проигрыш», поэтому у сделки,
переведённой на закрытый этап, всегда записано, кто её закрыл. Оба очищают и заново добавляют
`contacts`/`tags`/`teams`/`assigned_to` из тела запроса так же, как это делает создание.
Успех: `{"error": false, "message": "Opportunity Updated Successfully"}`.

`DELETE /api/opportunities/{id}/` (`:612-637`) разрешён администратору, суперпользователю или
создателю сделки (`request.profile.user != self.object.created_by`, сравнение `User` с `User`,
`:624-632`). Все остальные получают `403`.

## Этапы {#stages}

**Этапы принадлежат воронке, и каждая организация настраивает свои.** `DealPipeline` и `DealStage`
(`opportunity/models.py`) ограничены организацией и защищены RLS. У этапа есть `code` (строка,
которая хранится в `Opportunity.stage`, уникальна в пределах воронки, выводится из названия при
создании этапа и после этого никогда не меняется; [отраслевое приложение](../features/industry-apps.md#deal-pipelines)
задаёт коды своих этапов само, в нижнем регистре), `label`, `order`, `kind` (`open`, `won` или
`lost`) и пороги устаревания `expected_days` и `warning_days` (оба пусты у этапа, который никогда не
устаревает, и всегда пусты у этапов выигрыша и проигрыша). У каждой сделки есть `pipeline` и код
`stage` этой воронки.

У каждой организации есть одна воронка по умолчанию: для существующих организаций её создаёт
миграция `opportunity/0020`, а для новых она создаётся лениво при первом использовании. В ней шесть
этапов, которые были в приложении всегда: `PROSPECTING`, `QUALIFICATION`, `PROPOSAL`, `NEGOTIATION`
(открытые), `CLOSED_WON` (выигрыш) и `CLOSED_LOST` (проигрыш). Сделка, сохранённая без воронки,
попадает в неё, и именно поэтому клиенты, появившиеся до воронок, продолжают работать.

**Всё, что считает выигрыши, смотрит на тип этапа, а не на код.** Цели, дашборд, сводные показатели
компаний и контактов, `?open=true` и проверка при выставлении счёта по сделке считают сделку
выигранной, если тип её этапа `won`, как бы этап ни назывался (`stage_kind_q`,
`opportunity/models.py`). Переход на этап выигрыша или проигрыша требует `closed_on`; переход на этап
выигрыша требует также `amount`. `probability` заполняется автоматически, если равно `0` или не
задано: 100 для этапа выигрыша, 0 для этапа проигрыша и значение по умолчанию для каждого кода у
предустановленных открытых этапов (`stage_probability`, `opportunity/workflow.py`).

**Фильтр по этапу ищет вхождение подстроки, а не точное совпадение**: `?stage=` превращается в
`__contains`, в отличие от `Lead.status`, где совпадение точное (см. [Лиды](leads.md#list-leads)). Поэтому `?stage=CLOSED` находит и `CLOSED_WON`, и `CLOSED_LOST`, а
`?stage=closed` (в нижнем регистре) не находит ни одного, потому что `__contains` для `CharField`
учитывает регистр.

`aging_status` становится `yellow`, когда сделка провела на открытом этапе `warning_days` (или, если
его нет, `expected_days`) полных дней, и `red` (застряла, устарела) при
`ceil(expected_days * 1.5)` (`aging_thresholds`, `workflow.py`). `?rotten=true` и `stalled_count` в
`totals` используют те же пороги, что и `Opportunity.get_aging_status()`, как отсечки в queryset
(`opportunity/stages.py`, `aging_q`).

Ежедневное письмо о застрявших сделках (`check_stale_opportunities` в `opportunity/tasks.py`,
запускается Celery beat) использует тот же порог `red`. Оно приходит ответственным за каждую
застрявшую сделку, а если ответственных нет, администраторам организации. О сделке пишут примерно
один раз на каждом этапе: каждый запуск перечисляет только сделки, ставшие красными за сутки с
предыдущего запуска (целыми часами, чтобы ежедневные запуски стыковались без пропусков), а более
старые застрявшие сделки получателя считает, не перечисляя. О сделке, которая уже была красной при
первом запуске планировщика, письма не будет никогда, поэтому поздний старт не отправляет накопленное,
а пропущенный планировщиком день не наверстывается. Письмо пропускает демонстрационные сделки пакета
(`is_sample`) и любую организацию, которой никто не пользовался последние 30 дней: ни активности, ни
входа участников.

### Администрирование воронок {#pipeline-administration}

Чтение доступно каждому участнику организации; любая запись доступна только администратору (иначе
`403`). Id из другой организации даёт `404`. Всё это находится в
`opportunity/views/pipeline_views.py`.

| Эндпоинт | Метод | Тело | Ответ |
| --- | --- | --- | --- |
| `/api/opportunities/pipelines/` | GET | | `{"pipelines": [pipeline, ...]}`, сначала воронка по умолчанию |
| `/api/opportunities/pipelines/` | POST | `{"name"}` | `201`, воронка с шестью этапами по умолчанию |
| `/api/opportunities/pipelines/{id}/` | GET, PATCH, DELETE | PATCH `{"name"}` | DELETE возвращает `204` либо `400` для воронки по умолчанию или пока в воронке есть хотя бы одна сделка |
| `/api/opportunities/pipelines/{id}/stages/` | POST | `{"label", "kind", "expected_days"?, "warning_days"?}` | `201`, вся воронка; этап добавляется последним |
| `/api/opportunities/pipelines/{id}/stages/reorder/` | POST | `{"stage_ids": [...]}` | воронка; `400`, если список не содержит каждый этап воронки ровно один раз |
| `/api/opportunities/stages/{id}/` | PATCH, DELETE | PATCH любые из полей POST | PATCH возвращает воронку; DELETE возвращает `204` |

Воронка имеет вид `{"id", "name", "is_default", "stages": [{"id", "code", "label", "order", "kind",
"expected_days", "warning_days"}]}`. В каждой воронке остаётся хотя бы один открытый этап, один этап
выигрыша и один этап проигрыша: удаление последнего этапа какого-либо типа или изменение его типа
даёт `400`. То же для удаления этапа или изменения его типа, пока на нём есть сделки, для названия,
которое уже есть у другого этапа этой воронки, и для количества дней вне диапазона от 1 до 3650.

`GET /api/opportunities/aging-config/` и `PUT` появились раньше воронок и по-прежнему работают: они
читают и записывают дни устаревания для открытых этапов воронки по умолчанию с ключами по коду
`stage`.

### Доска и перемещение {#board-and-move}

`GET /api/opportunities/kanban/?pipeline={id}` (`OpportunityKanbanView.get`) возвращает по одному
столбцу на каждый этап этой воронки (воронки по умолчанию, если `pipeline` не передан). Id воронки
другой организации даёт `404`. Начиная с django-crm 1.13.0 доска строится от `deal_list_queryset`,
функции, на которой основаны `GET /api/opportunities/`, его итоги и выгрузка в CSV, поэтому она
принимает **все** фильтры списка, описанные в разделе [Список сделок](#list-opportunities) (`name`,
`search`, `account`, `stage`, `lead_source`, `tags`, `assigned_to`, `created_at__gte/lte`,
`closed_on__gte/lte`, `amount__gte/lte`, `cf_<key>`, `open=true`, `rotten=true`), с тем же правилом
видимости, и фильтр сужает доску и список одинаково. До 1.13.0 она принимала только `search`,
`account`, `assigned_to`, `tags` и `closed_on__gte/lte`. В каждом столбце не более 100 карточек;
`item_count` содержит полное число записей в столбце.

```json
{
  "mode": "status",
  "pipeline": {"id": "<uuid>", "name": "Sales", "is_default": true},
  "columns": [
    {"id": "PROSPECTING", "name": "Prospecting", "order": 1, "kind": "open", "color": "#3B82F6", "stage_type": "open", "expected_days": 14, "warning_days": null, "is_status_column": true, "wip_limit": null, "item_count": 4, "items": [ { "...": "OpportunityKanbanCardSerializer" } ]}
  ],
  "total_items": 23
}
```

Каждая карточка (`OpportunityKanbanCardSerializer`) содержит `id`, `name`, `pipeline`, `stage`,
`stage_label`, `stage_kind`, `amount`, `opportunity_amount`, `currency`, `probability`, `closed_on`,
`kanban_order`, `account` (`{id, name}`), `assigned_to`, `tags`, `line_items`, `days_in_stage`,
`aging_status`, `stage_changed_at`, `next_activity`, `can_move`, `created_at` и `updated_at`.
`tags`, `line_items`, `stage_changed_at` и `updated_at` появились в 1.13.0 для доски в мобильном
приложении, которое тоже читает этот эндпоинт. `line_items` карточки представляют собой простые
строки (`id`, `name`, `quantity`, `unit_price`, `discount_type`, `discount_value`), а не полную
позицию, которую возвращает детальный просмотр. `can_move` показывает, может ли вызывающий
перемещать карточку, по тому же правилу, которое применяет эндпоинт перемещения.

`PATCH /api/opportunities/{id}/move/` (`OpportunityMoveView.patch`) требует `column_id`, код этапа
собственной воронки сделки (всё остальное даёт `400`; доска никогда не переносит сделку между
воронками, это делает форма редактирования). `above_id`/`below_id` или явный `kanban_order` задают
положение карточки внутри столбца. Доступ проверяется по тому же правилу, что и у детального
просмотра (администратор, создатель или ответственный). Перетаскивание на этап выигрыша или
проигрыша записывает `closed_by` (и `closed_on`, если у сделки его не было); перетаскивание закрытой
сделки обратно на открытый этап очищает `closed_by`. Перетаскивание на этап выигрыша без суммы даёт
`400`.

## Поля {#fields}

`OpportunityCreateSerializer.Meta.fields` (`opportunity/serializer.py:270-289`) определяет, что
принимают `POST /api/opportunities/`, `PUT /api/opportunities/{id}/` и
`PATCH /api/opportunities/{id}/`. На уровне модели обязательно только `name`
(`opportunity/models.py:46`, без `blank=True`).

| Поле | Тип | Обязательно | Примечания |
| --- | --- | --- | --- |
| `name` | string | **обязательно** | Уникально в пределах организации без учёта регистра |
| `account` | uuid | необязательно | Компания в организации вызывающего, которую вызывающий может открыть (администратор может открыть любую). Всё остальное, включая неизвестный id, даёт 400 `"No such account."`. При редактировании компания, которая уже есть у сделки, сохраняется, кто бы ни сохранял |
| `pipeline` | uuid | необязательно | Одна из воронок организации. По умолчанию текущая воронка сделки или, при создании, воронка организации по умолчанию. Для изменения требуется также `stage` |
| `stage` | код этапа воронки сделки | необязательно | При создании по умолчанию первый открытый этап воронки; см. [Этапы](#stages) |
| `opportunity_type` | одно из `OPPORTUNITY_TYPES` | необязательно | `NEW_BUSINESS`, `EXISTING_BUSINESS`, `RENEWAL`, `UPSELL`, `CROSS_SELL` |
| `currency` | одно из `CURRENCY_CODES` | необязательно | Если не передано, берётся из `default_currency` организации |
| `amount` | decimal | **обязательно для этапа выигрыша** | Иначе необязательно; неотрицательное (ограничение БД) |
| `probability` | integer, 0-100 | необязательно | Заполняется автоматически по `stage`, если `0` или не задано. См. [Этапы](#stages) |
| `closed_on` | date | **обязательно для этапа выигрыша или проигрыша** | Иначе необязательно |
| `lead_source` | ключ из [источников лидов](leads.md#lead-sources) организации | необязательно | Тот же список и то же правило, что для `source` лида: неизвестные ключи, ключи другой организации и выведенные из использования дают `400`, а уже сохранённый ключ принимается всегда. Старые значения в верхнем регистре перенесены миграцией (`WEBSITE` стал `web form`, `NONE` стал пустым) |
| `source_detail` | string, не более 100 | необязательно | Копируется из лида при конвертации |
| `source_ref` | string, не более 255 | необязательно | Копируется из лида при конвертации |
| `description` | text | необязательно | |
| `is_active` | boolean | необязательно | По умолчанию `true` |

Не входят в сериализатор, но принимаются в том же запросе и разрешаются представлением (см.
[Создание сделки](#create-an-opportunity)): `contacts`, `tags`, `teams`, `assigned_to` (каждое список
id, ограниченный организацией) и `opportunity_attachment` (multipart-файл).

`GET /api/opportunities/` и `GET /api/opportunities/{id}/` дополнительно возвращают, но никогда не
принимают на вход: `id`, `closed_by`, `created_by`, `created_at`, `org` (вложенный),
`created_on_arrow`, `amount_source` (`MANUAL` или `CALCULATED`, вычисляется на сервере в
`recalculate_amount()` в зависимости от наличия у сделки позиций, `opportunity/models.py:68-73,185-202`;
через этот сериализатор не записывается), `stage_label`, `stage_kind`, `stage_changed_at`,
`days_in_stage`, `aging_status` (`green`/`yellow`/`red`, из `Opportunity.get_aging_status()`),
`line_items`, `line_items_total` и `custom_fields` (проверяется отдельно по строкам
`CustomFieldDefinition` организации).
