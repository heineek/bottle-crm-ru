# Права и роли

Аутентификация (см. раздел [Аутентификация](authentication.md)) устанавливает, кто выполняет
запрос. Эта страница посвящена отдельному вопросу, на который каждый view всё равно должен ответить
сам: разрешено ли этой личности конкретное действие над конкретным объектом? Классы прав DRF
отвечают на первую, грубую половину вопроса; проверки на уровне объекта внутри view отвечают на
остальное.

## Роли {#roles}

`Profile.role` (`backend/common/models.py`) является `CharField` с двумя значениями:
`common.utils.ROLES = (("ADMIN", "ADMIN"), ("USER", "USER"))`, по умолчанию `USER`. Это роль
человека *внутри одной организации*: пользователь с профилями в двух организациях может быть
`ADMIN` в одной и `USER` в другой, потому что роль хранится в `Profile` (строке членства
пользователя в организации), а не в самом `User`.

Рядом существует второй, независимый флаг: `Profile.is_organization_admin`, обычный boolean,
доступный как свойство `.is_admin`. Это действительно отдельное от `role` поле, ничто не
обеспечивает их согласованность, и немалая часть кода проверки прав считает любое из них
достаточным признаком того, что «этот человек администратор»:

```python
# common/permissions.py. IsOrgAdmin
return request.profile.role == "ADMIN" or request.profile.is_organization_admin
```

```python
# cases/access.py
def is_org_admin(profile):
    """True for the two ways this codebase spells "admin"."""
    return profile.role == "ADMIN" or bool(getattr(profile, "is_admin", False))
```

Когда пишете новую проверку администратора, проверяйте оба поля, как эти две функции: проверка,
которая смотрит только на `role == "ADMIN"`, молча откажет тому, чей статус администратора выдан
только через `is_organization_admin`, и наоборот.

Отдельно от любой роли в организации `IsSuperAdmin` (`backend/common/permissions.py`) открывает
доступ на уровне платформы по `User.is_superuser`. Это явный флаг, устанавливаемый через
`manage.py createsuperuser`, админку Django или другой путь с аудитом, и он никогда не выводится
из адреса email или домена. Собственный docstring класса объясняет, почему это важно: вывод
статуса суперадминистратора из домена email отдал бы доступ ко всей платформе (каждой организации,
каждому пользователю) любому, кто сможет завести учётную запись на этом домене, превратив обычную
регистрацию в вертикальное повышение привилегий. Этот флаг никак не связан с `Profile.role`; `User`
может быть `is_superuser` вообще без членства в какой-либо организации.

## Классы прав {#permission-classes}

`backend/common/permissions.py` определяет строительные блоки, из которых составляется каждый
view:

- **`HasOrgContext`**: требует, чтобы `request.profile` и `request.org` были установлены (middleware,
  описанным в разделе [Обзор архитектуры](overview.md#request-lifecycle)), а `request.profile.is_active` был
  истинным. Именно эта проверка превращает ситуацию «в JWT нет действительного claim организации»
  в аккуратный 403 с сообщением «Organization context is required. Please login again.» на уровне
  view, повторяя то, что `RequireOrgContext` уже обеспечивает на уровне middleware.
- **`IsOrgAdmin`**: `role == "ADMIN"` или `is_organization_admin`, как показано выше.
- **`IsSuperAdmin`**: `user.is_superuser`, как показано выше.

Стандартная комбинация почти на каждом view в кодовой базе, привязанном к организации:

```python
permission_classes = (IsAuthenticated, HasOrgContext)
```

Например, `CaseListView`, `CaseAttachmentView` и `CaseCommentView` в `backend/cases/views.py` или
`TagsListView` в `backend/common/views/tags_views.py`. Обратите внимание, чего эта комбинация *не*
делает: она не проверяет роль и не проверяет, к какому конкретному объекту относится запрос.
`IsAuthenticated` + `HasOrgContext` дают лишь «запрос выполняет реальный активный участник этой
организации», и ничего конкретнее. Проверки роли (`request.profile.role == "ADMIN"`) и проверки на
уровне объекта добавляются внутри самих методов view: декларативный список `permission_classes` в
DRF не видит объект, над которым выполняется действие, пока view его не загрузил, поэтому
авторизация на уровне объекта должна жить в коде. Об этом следующий раздел.

## Проверки на уровне объекта {#object-level-checks}

`backend/cases/access.py` является самым наглядным примером в кодовой базе авторизации на уровне
объекта, сделанной осознанно и в одном месте, а не реализованной заново в каждом view. Docstring
модуля объясняет, какую проблему он решает: до его появления на вопрос «кто может читать, менять и
удалять обращение» отвечали независимо в пяти разных местах вызова, и ответы случайно разошлись в
три разных варианта. Наблюдатель видел своё обращение в списке, но получал 403 при его открытии,
потому что queryset view списка включал наблюдателей, а проверка прав view детальной страницы нет.
Вот последствие отказа от централизации таких проверок: действия молча противоречат друг другу, а
замечает это пользователь, упёршийся в стену, которой продукт не задумывал.

Теперь модуль формулирует три явных, разных правила и применяет их из одного места:

```python
def is_org_admin(profile):
    return profile.role == "ADMIN" or bool(getattr(profile, "is_admin", False))

def has_case_write_access(profile, case):
    if is_org_admin(profile):
        return True
    if profile.user_id == case.created_by_id:
        return True
    return profile.id in {p.id for p in case.assigned_to.all()}

def assert_case_delete_access(profile, case):
    """Narrower than writing on purpose: an assignee is somebody the work was
    handed to, which is a reason to let them work the ticket and not a reason
    to let them erase it."""
    if is_org_admin(profile):
        return
    if profile.user_id == case.created_by_id:
        return
    raise PermissionDenied(_DENIED)
```

В `has_case_write_access` стоит заметить две вещи. Сравнение выглядит как `profile.user_id ==
case.created_by_id`, то есть id `User` сравнивается с id `User`, а не `profile ==
case.created_by`. `Case.created_by` (из `AuditModel` в `common/mixins.py`, которую почти каждая
модель наследует транзитивно через `BaseModel`; немногие исключения перечислены в разделе
[Модель данных](data-model.md#conventions)) является внешним ключом на `User`, а не на `Profile`.
Прямое сравнение экземпляра `Profile` с внешним ключом на `User` всегда даёт `False`. Такое
сравнение проходит проверку типов в Python, но никогда не бывает истинным, и тихо превращает
задуманную проверку «создатель или администратор» в проверку «только администратор», без единой
ошибки.

Docstring метода `CaseAttachmentView.delete` в `backend/cases/views.py` фиксирует, что до
исправления в этом эндпоинте жили два отдельных дефекта: непривязанный поиск `objects.get(pk=pk)`
(вообще без фильтра по организации) и то же несовпадение типов `created_by`. Его последняя строка
говорит лишь, что «the same one-line **lookup** bug is still open in `leads`, `tasks` and
`opportunity`». Это предложение относится именно к дефекту с отсутствующим фильтром по
организации, а не к сравнению `created_by`, и, если проверить его по текущему исходному коду всех
трёх приложений, а не верить docstring на слово, для одного из трёх оно уже устарело:

- **`leads`** (`leads/views/lead_interactions.py`). Непривязанный поиск всё ещё не исправлен
  (`.objects.get(pk=pk)` в строке 204, без `org=`). Однако сравнение `created_by` здесь корректно:
  `request.profile.user == self.object.created_by` (строка 208) сравнивает `User` с `User`, а не
  `Profile` с `User`, поэтому проверка `created_by` в этом эндпоинте работает.
- **`tasks`** (`tasks/views/task_views.py`). Оба дефекта исправлены: поиск отфильтрован по
  организации (`.filter(pk=pk, org=request.profile.org)`, строки 975-977), а сравнение имеет вид
  `request.profile.user_id == self.object.created_by_id` (строка 987), с комментарием в строках
  982-984, объясняющим причину. Утверждение docstring из cases, что ошибка поиска «всё ещё не
  исправлена» в `tasks`, устарело.
- **`opportunity`** (`opportunity/views/opportunity_interactions.py` и `kanban_views.py`). Оба
  дефекта не исправлены, а несовпадение типов встречается в двух разных местах вызова:
  `request.profile == self.object.created_by` при удалении вложения
  (`opportunity_interactions.py:158` для непривязанного поиска, `:162` для сравнения) и ещё раз как
  `is_owner = request.profile == opportunity.created_by` в эндпоинте перемещения по Kanban
  (`kanban_views.py:162`).

Итак, на момент написания: сама ошибка несовпадения типов `created_by` не исправлена только в
`opportunity` (два места вызова); отдельная ошибка непривязанного поиска не исправлена в `leads` и
`opportunity`. Ни один из дефектов эта документация не исправляет. Они отмечены здесь точно,
потому что docstring, перечисляющий, в каких приложениях ещё есть ошибка, устаревает так же, как
любой другой комментарий, и правильный выход в таком случае: проверить текущий исходный код самому,
как сделано в этом абзаце, а не доверять ни docstring, ни прежнему его пересказу. Когда пишете
сравнение с `created_by`, сравнивайте `profile.user_id` с `obj.created_by_id` и напишите тест,
доказывающий, что проверка может вернуть и `True`, и `False`.

## Читать широко, менять узко {#read-wide-write-narrow}

В кодовой базе достаточно часто повторяется шаблон, чтобы дать ему имя: для данного вида ресурса
круг тех, кто может его *читать*, шире круга тех, кто может его *менять*, а тот, в свою очередь,
шире круга тех, кто может его *удалить*. Две конкретные формы этого шаблона:

**Доступ к отдельному объекту**, как в `cases/access.py` выше:

```
read    admin · creator · assignee · watcher
write   admin · creator · assignee
delete  admin · creator
```

Наблюдение за обращением означает подписку на обновления, а не получение ключей от него, поэтому
условие для наблюдателя, расширяющее доступ на *чтение*, намеренно не переносится на *изменение*
и *удаление*. Каждое действие формулирует своё правило; ни одно не выводится из другого.

**Общая конфигурация уровня организации** (теги, отраслевые пакеты и подобные настройки
организации) следует более простой, но столь же осознанной версии той же формы: читать её может
любой активный участник организации, менять только администратор. `TagsListView`
(`backend/common/views/tags_views.py`) служит чистым примером: у `get` нет дополнительной проверки
сверх стандартной `(IsAuthenticated, HasOrgContext)`, а `post` явно ограничен:

```python
def post(self, request, *args, **kwargs):
    """Create a new tag (admin only)."""
    if request.profile.role != "ADMIN" and not request.user.is_superuser:
        return Response(
            {"error": True, "errors": "Only admins can create tags"},
            status=status.HTTP_403_FORBIDDEN,
        )
```

`common/views/pack_views.py` формулирует ту же форму в комментарии ещё до первой строки кода: «any
authenticated member may list packs; only an org ADMIN may apply one or clear sample data». Когда
вы добавляете новый эндпоинт для чего-то действительно общего, конфигурации уровня организации, а
не записи с конкретным владельцем, по умолчанию выбирайте именно это: не ограничивайте чтение
ничем, кроме членства в организации, а каждое изменение и удаление закрывайте явной проверкой
администратора во view, а не записью в `permission_classes`, которая заблокировала бы и чтение.
