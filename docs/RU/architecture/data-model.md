# Модель данных

На этой странице описаны общая форма, которой следует каждая модель в кодовой базе, несколько
способов, которыми связаны основные сущности CRM, и ряд соглашений, которые легко принять на веру
вместо того, чтобы проверить. Именно поэтому они записаны здесь вместе с файлом и строкой, которые
делают каждое из них истинным.

## Основные сущности {#core-entities}

- **Lead** (`backend/leads/models.py`), лид: потенциальный клиент, ещё не прошедший квалификацию.
  `LeadPipeline`/`LeadStage` дают каждой организации собственные настраиваемые колонки Kanban.
- **Account** (`backend/accounts/models.py`), компания или клиент. `AccountEmail`/
  `AccountEmailLog` поддерживают входящие почтовые ящики, привязанные к компании.
- **Contact** (`backend/contacts/models.py`), человек, при необходимости связанный с `Account`.
- **Opportunity** (`backend/opportunity/models.py`). Сделка в процессе продажи.
  `OpportunityLineItem` хранит товары из предложения; `DealPipeline`/`DealStage` задают
  настраиваемые этапы сделок организации, причём каждый этап несёт свой тип (открыта, выиграна,
  проиграна) и пороги «застревания», то есть сколько дней на этапе уже слишком много; `SalesGoal`:
  план или цель, отслеживаемые по данным `Opportunity`.
- **Case** (`backend/cases/models.py`), обращение в поддержку. Безусловно самый крупный набор
  вспомогательных моделей: `CaseWatcher`, `CsatSurvey`, `Solution` (база знаний),
  `CasePipeline`/`CaseStage`, `ReopenPolicy`, `EscalationPolicy`, `InboundMailbox`/`EmailMessage`
  (обращения из почты), `RoutingRule`/`RoutingRuleState` и `TimeEntry`.
  `Case.account` является прямым внешним ключом (а не допускающей null связью через промежуточную
  таблицу); поля SLA (`sla_first_response_hours`, `sla_resolution_hours`, `first_response_at`,
  `resolved_at`) хранятся прямо в модели обращения.
- **Task** (`backend/tasks/models.py`). Задача со своими настраиваемыми
  `TaskPipeline`/`TaskStage` и отдельным семейством `Board`/`BoardColumn`/`BoardTask`/`BoardMember`
  для свободных Kanban-досок, не связанных с воронкой задач.
- **Invoice** (`backend/invoices/models.py`): выставление счетов, вместе с `Estimate`,
  `RecurringInvoice`, `Product`, `Payment` и `InvoiceTemplate` в том же приложении. Этому
  приложению также принадлежат анонимные views клиентского портала (см.
  [Мультитенантность и RLS](multi-tenancy-and-rls.md#portal-tokens)).
- **Order** (`backend/orders/models.py`), `Order`/`OrderLineItem`.

## Связи {#relationships}

Путь от лида к клиенту представляет собой однократную конвертацию, а не постоянный внешний ключ.
`leads.services.convert_lead_to_account(lead_obj, request, create_opportunity=True)`
(`backend/leads/services.py`) выполняется как побочный эффект, когда `status` лида меняется на
`"converted"` через обычные views обновления лида (`backend/leads/views/lead_views.py`).
Отдельного эндпоинта для конвертации нет. Функция:

1. Выполняет `get_or_create` для `Account` (совпадение по имени без учёта регистра в пределах
   организации).
2. Выполняет `get_or_create` для `Contact` по email лида, если он есть, и связывает контакт с
   компанией и прямым FK, и через `Account.contacts`.
3. Создаёт `Opportunity`, если это запрошено и у лида достаточно данных, копируя
   `assigned_to`/`teams`/`tags`.
4. Переносит строки `Comment`/`Attachments` лида (пары generic-relation `ContentType`/`object_id`)
   с лида на новую компанию.
5. Устанавливает `lead_obj.status = "converted"`.

Сохранённой обратной ссылки от созданных `Account`/`Contact`/`Opportunity` на исходный `Lead`
намеренно нет, и файл модели `Lead` прямо это документирует: прежние поля `converted_account`/
`converted_contact`/`converted_opportunity`/`conversion_date` удалили, потому что они «never
populated, conversion just sets status». Если нужно проследить запись до лида, из которого она
появилась, в схеме нет ничего, за что можно зацепиться; совпасть, скорее всего, будут только имя
компании или контакта либо email.

`Contact` и `Account` связаны одновременно двумя независимыми способами: `Contact.account`
является внешним ключом, допускающим null (`on_delete=SET_NULL`), а `Account.contacts`:
независимая связь многие-ко-многим. Конвертация лида заполняет обе. Код, которому нужны «контакты
этой компании», должен осознанно выбрать, какую из двух связей он имеет в виду, а не считать, что
они всегда согласованы.

`Opportunity.account` является внешним ключом на `Account`, допускающим null;
`Opportunity.contacts` задаёт связь многие-ко-многим с `Contact`. `Case.account` является
внешним ключом на `Account`, на практике обязательным (blank/null разрешены, но
`on_delete=CASCADE`), а `Case.contacts` задаёт связь многие-ко-многим с `Contact`.

## Соглашения {#conventions}

Почти каждая модель в кодовой базе наследует `BaseModel` (`backend/common/base.py`), который через
`AuditModel` (`backend/common/mixins.py`) даёт:

- `id`: первичный ключ `UUIDField` (`default=uuid.uuid4`), а не автоинкрементное целое.
- `created_at`/`updated_at`: заполняются автоматически (`auto_now_add`/`auto_now`).
- `created_by`/`updated_by`: внешние ключи на **`User`**, а не на `Profile`, которые
  заполняются из `crum.get_current_user()` в `BaseModel.save()`. Здесь стоит быть точным:
  проверка прав, сравнивающая `request.profile` напрямую с `some_object.created_by`, сравнивает
  экземпляр `Profile` с внешним ключом на `User` и всегда даёт `False`. Класс ошибок, к которому
  это приводит, и правильный способ сравнения (`profile.user_id == obj.created_by_id`) описаны в
  разделе [Права и роли](permissions-and-roles.md#object-level-checks).

Три модели полностью отказываются от этого и наследуют обычный `models.Model`: `User`
(`backend/common/models.py:34`), `MagicLinkToken` (`:524`) и `PortalAccessToken` (`:910`). Все
три по-прежнему вручную объявляют свой `id = models.UUIDField(default=uuid.uuid4, primary_key=True)`,
так что соглашение о первичном ключе UUID соблюдается и для них, но ни у одной нет полей
`created_at`/`updated_by`/`created_by`. Это логично: `User` появился раньше модели членства в
организациях и находится полностью вне её (привязан к организации как раз `Profile`), а
`MagicLinkToken`/`PortalAccessToken` представляют собой короткоживущие строки для начальной
аутентификации, у которых нет осмысленного «кто последним их менял».

Модели, привязанные к организации, добавляют ещё одно поле: внешний ключ `org` на `common.Org`,
унаследованный от `BaseOrgModel` или (что в этой кодовой базе встречается чаще) объявленный
вручную поверх `BaseModel`. Какие модели как это делают и почему оба варианта допустимы, если
таблица также зарегистрирована для RLS и для неё есть миграция, описано в разделе
[Мультитенантность и RLS](multi-tenancy-and-rls.md#baseorgmodel).

**У каждого типа записей с доской есть этапы на уровне организации, но `Opportunity.stage`
хранится иначе, чем у трёх остальных.** `Lead.stage`, `Case.stage` и `Task.stage` являются
внешними ключами, допускающими null, на строку `LeadStage`/`CaseStage`/`TaskStage` организации
(которая сама принадлежит `LeadPipeline`/`CasePipeline`/`TaskPipeline`). У `Opportunity` есть
внешний ключ `pipeline` на `DealPipeline` и `CharField` `stage` с одним из значений
`DealStage.code` этой воронки, поэтому в API передаётся стабильная строка (`PROSPECTING`,
`CLOSED_WON` или код, присвоенный этапу администратором), а не id строки; код после создания этапа
не меняется, а название может. Смысл этапа сделки (открыта, выиграна, проиграна) задаётся
`DealStage.kind`, и именно по нему считают отчёты и цели. Три остальные модели вдобавок хранят
отдельное поле `status` с фиксированным набором значений (`Lead.status`, `Case.status`,
`Task.status`) рядом с настраиваемым FK `stage`. Поле этапа `maps_to_status` поддерживает их
согласованность, когда запись переходит между этапами. У сделки второго такого поля нет: тип её
этапа уже говорит, открыта она, выиграна или проиграна.

Несколько моделей (среди них `Lead`, `Opportunity`, `Case`) содержат `custom_fields = JSONField()`,
значения которого проверяются по `common.CustomFieldDefinition`: это механизм расширения схемы на
уровне организации, который не требует миграции, чтобы добавить поле для одной организации.

Наконец, одна ловушка валидации, о которой стоит знать, прежде чем полагаться на `Model.clean()`:
`ModelSerializer` в DRF вызывает `instance.save()`, а не `instance.full_clean()`, поэтому метод
`clean()` модели вызывается через API, только если собственный `save()` этой модели явно вызывает
`self.full_clean()`, а большинство моделей этого не делают. `Lead.clean()`, `Opportunity.clean()`
и `Case.clean()` (`backend/cases/models.py:180`) задают таким образом реальные правила валидации,
и по умолчанию эти правила молча не применяются через API, потому что ни `Lead.save()`, ни
`Opportunity.save()`, ни `Case.save()` не вызывает `full_clean()`. Несколько других моделей
вызывают его из своего `save()`, поэтому их правила `clean()` доходят до API как Django
`ValidationError`, то есть как 500 (если view случайно его не перехватит), а не как аккуратный
ответ DRF 400: `Task.save()` (`backend/tasks/models.py:403`) и `Comment.save()`/`Attachments.save()`
(`backend/common/models.py:316-318` и `:430-432`, оба именно для того, чтобы `org` комментария или
вложения совпадал с организацией записи, к которой он прикреплён). Общего правила, какие модели так
делают, нет: проверяйте конкретный метод `save()`, а не предполагайте. Там, где неприменяемое
правило `clean()` оказалось важным для API, его заново реализовали прямо в сериализаторе, а не
полагаются на `full_clean()`: `validate()` в `opportunity/serializer.py` дублирует два правила из
`Opportunity.clean()` именно по этой причине, как сказано в его собственном комментарии. Если вы
добавляете метод `clean()` в модель, проверьте, вызывает ли `save()` этой модели `full_clean()`,
прежде чем считать, что правило где-либо применяется, кроме модульного теста, который вызывает
`full_clean()` напрямую.
