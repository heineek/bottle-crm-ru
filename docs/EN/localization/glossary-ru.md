# Russian glossary

This page fixes how each CRM term is translated into Russian, so the web app, the mobile app, API
errors and emails say the same thing. A translation that disagrees with this page is a bug,
whichever client it is in. Each language has its own glossary page; this one is the model for a
new one (see [Adding a language](adding-a-language.md#before-you-start)).

## How to use it

- Translate the **concept**, not the English word: the left column is the code key or the English
  label as it appears in the UI.
- A term an org renamed through a vertical pack (`Org.terminology`, for example "Enquiries" for
  leads) is tenant text and is shown as is, in whatever language the org wrote it.
- Data users typed (stage names, custom field labels, tags, product names) is never translated.

## Style rules for Russian

- Address the user as **«вы»**, lowercase, polite and short.
- Buttons and menu actions use the **infinitive**: «Сохранить», «Удалить», «Создать сделку».
- Write **«ё»** where it belongs: «Счёт», «Отменён», «Ещё».
- Quotes are **«ёлочки»**; nested quotes are „лапки“.
- **No em dashes**, as everywhere in this repository. Russian definitions that would normally take
  one get a colon or two sentences: «Лид: потенциальный клиент», not a dash.
- Statuses **agree in gender and number with their entity**: a deal is «закрыта», a lead is
  «закрыт», a ticket is «закрыто». So a status label is keyed per entity
  (`lead.status.closed`, `ticket.status.closed`), never shared as one `common.closed` string.
- Counts always go through plural rules (one, few, many, other): «1 сделка», «2 сделки»,
  «5 сделок», «21 сделка». Never build them as a number plus a fixed word.
- Numbers, money and dates are formatted by the locale (`Intl` on the web, `intl` on mobile), not
  by hand: «1 234,50 ₽», «10 нояб. 2026».
- Abbreviations that are standard in Russian CRM and helpdesk products stay in Latin letters:
  SLA, CSAT, API, CSV, IMAP.

## Modules and entities

| Key / English | Russian (singular, plural) | Gender | Notes |
|---|---|---|---|
| Lead / Leads | Лид, Лиды | m | Not «Зацепка», not «Потенциальный клиент» in labels. |
| Deal, Opportunity / Deals | Сделка, Сделки | f | `opportunity` in the API is the same thing. |
| Pipeline (module `deals`) | Воронка | f | The deals module label. A stage list is «этапы воронки». |
| Stage | Этап | m | |
| Account / Accounts | Компания, Компании | f | The customer organization, not a user account. |
| Contact / Contacts | Контакт, Контакты | m | |
| Ticket, Case / Tickets | Обращение, Обращения | n | `case` in the API. Not «Тикет», not «Заявка». |
| Task / Tasks | Задача, Задачи | f | |
| Goal / Goals | Цель, Цели | f | Sales targets. |
| Knowledge base, Solution | База знаний; Статья | f | A solution is one article in the knowledge base. |
| Document / Documents | Документ, Документы | m | |
| Invoice / Invoices | Счёт, Счета | m | |
| Recurring invoice | Регулярный счёт | m | |
| Estimate / Estimates | Коммерческое предложение, Коммерческие предложения | n | Short form «КП» only where space forces it. |
| Order / Orders | Заказ, Заказы | m | |
| Product / Products | Товар, Товары | m | |
| Timesheet | Учёт времени | m | |
| Object (custom object) | Объект | m | |
| Activity / Activities | Активность, Активности | f | |
| Notification | Уведомление | n | |
| Today (dashboard) | Сегодня | | |
| Organization (Org) | Организация | f | The tenant. |
| Profile | Профиль | m | The signed-in user's own page. |
| Team | Команда | f | |
| Admin | Администратор | m | |
| User, Member | Пользователь, Участник | m | |
| Owner | Владелец | m | |
| Assigned to | Ответственный | m | As a field label. The verb form is «Назначить». |
| Tag | Тег | m | |
| Custom field | Дополнительное поле | n | |
| Saved view | Сохранённое представление | n | |
| Macro | Макрос | m | Helpdesk canned reply. |
| Web form | Веб-форма | f | |
| Webhook | Вебхук | m | |
| Automation rule | Правило автоматизации | n | |
| Duplicate | Дубликат | m | |
| Customer portal | Клиентский портал | m | |
| Personal access token | Персональный токен доступа | m | |
| API key | API-ключ | m | |
| Comment | Комментарий | m | |
| Attachment | Вложение | n | |
| Approval (of a ticket) | Согласование | n | Approve «Согласовать», approved «Согласовано», rejected «Отклонено». Not «одобрение», not «подтверждение». A knowledge base article's own review status stays «Одобрена». |
| Line item | Позиция | f | On invoices and estimates. Not «строка». |
| Agent (support) | Сотрудник | m | The person working tickets. «ИИ-агент» only for software agents. |
| User account | Учётная запись | f | The signed-in person's account. «Аккаунт Google» is fine for the Google one. |
| Submission (web form) | Заявка | f | What a visitor sends through a web form. Not «отправка». |
| Billable | Оплачиваемое | n | Time that is billed. Not «к оплате». |
| Assignee | Ответственный | m | Same as "Assigned to". Not «исполнитель». |

## Statuses and choices

Lead status (`LEAD_STATUS`), masculine:

| Code | English | Russian |
|---|---|---|
| `assigned` | Assigned | Назначен |
| `in process` | In process | В работе |
| `converted` | Converted | Конвертирован |
| `recycled` | Recycled | Возвращён в работу |
| `closed` | Closed | Закрыт |

Ticket status (`STATUS_CHOICE`), neuter:

| Code | English | Russian |
|---|---|---|
| `New` | New | Новое |
| `Assigned` | Assigned | Назначено |
| `Pending` | Pending | Ожидает |
| `Closed` | Closed | Закрыто |
| `Rejected` | Rejected | Отклонено |
| `Duplicate` | Duplicate | Дубликат |

Invoice status, masculine (estimate statuses are neuter, matching «предложение»):

| English | Invoice | Estimate |
|---|---|---|
| Draft | Черновик | Черновик |
| Sent | Отправлен | Отправлено |
| Viewed | Просмотрен | Просмотрено |
| Paid | Оплачен | |
| Partially paid | Оплачен частично | |
| Overdue | Просрочен | |
| Pending | Ожидает | |
| Cancelled | Отменён | |
| Accepted | | Принято |
| Declined | | Отклонено |
| Expired | | Истекло |

Priority (masculine, «приоритет»). Tickets use Low, Normal, High, Urgent; tasks use Low, Medium,
High:

| English | Russian |
|---|---|
| Low | Низкий |
| Normal | Обычный |
| Medium | Средний |
| High | Высокий |
| Urgent | Срочный |

Deal outcome and aging (feminine, about the deal):

| English | Russian |
|---|---|
| Won | Выиграна |
| Lost | Проиграна |
| On pace | В графике |
| Past expected | Дольше обычного |
| Stalled | Застряла |
| Slipping | Отстаёт |

## Common actions

| English | Russian |
|---|---|
| Save | Сохранить |
| Cancel | Отмена |
| Delete | Удалить |
| Edit | Изменить |
| Create, New | Создать |
| Add | Добавить |
| Search | Поиск |
| Filter | Фильтр |
| Export | Экспорт |
| Import | Импорт |
| Sign in | Войти |
| Sign out | Выйти |
| Assign | Назначить |
| Convert (a lead) | Конвертировать |
| Close (a record) | Закрыть |
| Reopen | Открыть снова |
