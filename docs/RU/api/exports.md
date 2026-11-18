# Экспорт в CSV

Шесть списков выгружаются в CSV-файл: лиды, контакты, компании, сделки, обращения и счета. Каждый
экспорт представляет собой `GET` под корнем своего списка и обслуживается подклассом `RecordExportView`
(`backend/common/csv_export.py`). Общие для списков правила строки запроса описаны в разделе
[Соглашения](conventions.md), а формы ответов при отказе в разделе [Ошибки](errors.md).

| Эндпоинт | Представление | Имя файла | Откуда берутся строки |
| --- | --- | --- | --- |
| `GET /api/leads/export/` | `LeadExportView` (`leads/views/export_views.py`) | `leads-YYYY-MM-DD.csv` | `lead_list_queryset` (`leads/views/lead_views.py`) |
| `GET /api/contacts/export/` | `ContactExportView` (`contacts/export_views.py`) | `contacts-YYYY-MM-DD.csv` | `contact_list_queryset` (`contacts/views.py`) |
| `GET /api/accounts/export/` | `AccountExportView` (`accounts/export_views.py`) | `accounts-YYYY-MM-DD.csv` | `account_list_queryset` (`accounts/views.py`) |
| `GET /api/opportunities/export/` | `DealExportView` (`opportunity/views/export_views.py`) | `deals-YYYY-MM-DD.csv` | `deal_list_queryset` (`opportunity/views/opportunity_views.py`) |
| `GET /api/cases/export/` | `CaseExportView` (`cases/export_views.py`) | `tickets-YYYY-MM-DD.csv` | `case_list_queryset` (`cases/views.py`) |
| `GET /api/invoices/export/` | `InvoiceExportView` (`invoices/export_views.py`) | `invoices-YYYY-MM-DD.csv` | `filter_invoices` поверх `visible_invoices_qs` (`invoices/api_views.py`) |

Дата в имени файла соответствует текущему дню в часовом поясе организации (`export_filename`).

## Кто может экспортировать и какие строки {#who-may-export-and-which-rows}

Экспортировать может любой участник организации (`permission_classes = (IsAuthenticated,
HasOrgContext)`), и он получает ровно те строки, которые соответствующий список показал бы ему при той
же строке запроса, со всех страниц. Это гарантируется тем, что `get_queryset` каждого экспорта вызывает
ту же функцию, которой список строит свой queryset (она указана в таблице выше), и никогда не фильтрует
самостоятельно. Поэтому правило чтения, скрывающее лид коллеги от участника в `GET /api/leads/`, скрывает
его и в файле, а обращение, которое вызывающий не может открыть, не попадает в `tickets-*.csv`.

Для персональных токенов доступа и API-ключа организации экспорт относится к ресурсу списка:
`GET /api/leads/export/` требует `leads:read`, тот же scope, что и `GET /api/leads/`
(см. [Токены и API-ключи](tokens-and-api-keys.md#scopes)).

## Параметры запроса {#query-parameters}

Экспорт принимает параметры запроса своего списка с тем же смыслом и игнорирует пагинацию: `limit` и
`offset` не сужают файл, в нём всегда все подходящие строки. Например,
`GET /api/cases/export/?status=New&status=Pending&priority=High` записывает все обращения с высоким
приоритетом в статусе New или Pending, которые видит вызывающий. Параметры каждого списка перечислены на
его собственной странице ([Лиды](leads.md#list-leads), [Контакты](contacts.md), [Компании](accounts.md),
[Сделки](opportunities.md), [Обращения](cases.md), [Счета и коммерческие предложения](invoices.md)), и
это тот же набор, который может хранить [сохранённое представление](saved-views.md).

Два списка отвечают половинами, которых у файла нет, поэтому нужная половина указывается в запросе:

- Лиды: список возвращает открытые и закрытые лиды отдельно. `?open=true` экспортирует только открытые,
  как показывает веб-список; без него записываются обе половины.
- Компании и контакты: `?is_active=true` или `?is_active=false` экспортирует одну половину. Без него
  записываются и активные, и неактивные строки.

Некорректное значение фильтра (id, не являющийся UUID, несуществующий день, число, которое не является
числом) даёт `400` с указанием параметра и возвращается до первого байта файла:

```json
{"assigned_to": ["'x' is not a valid id."]}
```

## Ответ {#the-response}

`200` представляет собой потоковое тело `text/csv; charset=utf-8` с заголовком
`Content-Disposition: attachment; filename="<prefix>-<YYYY-MM-DD>.csv"`. Отправляйте `Accept: text/csv`
или не отправляйте `Accept` вовсе; обслуживаются оба варианта (`CSV_RENDERERS`, `common/renderers.py`).
Файл:

- начинается с метки порядка байтов UTF-8, чтобы Excel правильно читал имена с диакритикой;
- содержит одну строку заголовка, затем по одной строке на запись в порядке самого списка;
- записывает людей их адресом email, а несколько значений в одной ячейке списком через `; `
  (владельцы, теги, связанные компании);
- записывает даты как `YYYY-MM-DD`, а временные метки как ISO 8601 в часовом поясе организации;
- добавляет `'` перед любой текстовой ячейкой, которая начинается с `=`, `+`, `-`, `@`, табуляции или
  возврата каретки (в том числе после ведущих пробелов), чтобы запись с именем `=HYPERLINK(...)` была в
  таблице текстом, а не формулой (`safe_cell`). Числа, отформатированные сервером, записываются как есть.

Тело формируется по мере передачи, уже после того как middleware запроса завершили работу, поэтому
представление заново устанавливает контекст row-level security и часовой пояс организации ровно на время
своей работы (`csv_response`).

## Столбцы {#columns}

| Файл | Столбцы |
| --- | --- |
| Лиды | ID, First name, Last name, Company, Job title, Email, Phone, Status, Source, Rating, Industry, Amount, Currency, Probability, Close date, Last contacted, Next follow-up, City, Country, Assigned to, Tags, Created |
| Контакты | ID, First name, Last name, Email, Phone, Title, Department, Organization, Account, Linked accounts, City, State, Country, Do not call, Active, Assigned to, Tags, Created |
| Компании | ID, Name, Industry, Email, Phone, Website, City, State, Country, Employees, Annual revenue, Currency, Active, Assigned to, Tags, Created |
| Сделки | ID, Name, Account, Pipeline, Stage, Amount, Currency, Probability, Close date, Type, Lead source, Assigned to, Tags, Created |
| Обращения | ID, Subject, Status, Priority, Type, Account, Assigned to, Tags, Created, First response, Resolved, Closed on |
| Счета | ID, Number, Title, Status, Account, Client name, Client email, Issue date, Due date, Total, Paid, Due, Currency, Assigned to, Created |

Названия столбцов приведены так, как они записываются в файл. Поля с выбором записываются своими
подписями (`In Process`, а не `in process`), а этап сделки записывается подписью этого этапа в
собственной воронке сделки. Списки столбцов задаёт метод `columns` каждого представления; если эта
таблица и файл когда-нибудь разойдутся, верен именно он.
