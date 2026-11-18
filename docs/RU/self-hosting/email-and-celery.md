# Почта и Celery

BottleCRM отправляет почту (приветственные сообщения, вход по ссылке из письма, упоминания в
комментариях) через почтовый фреймворк Django и выполняет фоновую и плановую работу (регулярные
счета, сканирование SLA, очистка токенов) через Celery. Эта страница описывает настройку обоих и
единственное правило, которому должна следовать каждая фоновая задача, работающая с данными тенантов.

## Почтовый бэкенд {#email-backend}

`backend/crm/settings.py` строит `MAILERS["default"]` из `EMAIL_BACKEND`, значение которого по
умолчанию `django.core.mail.backends.console.EmailBackend`: исходящая почта печатается в stdout
процесса, а не доставляется куда-либо. `.env.example` явно задаёт `EMAIL_BACKEND` этим консольным
бэкендом; `.env.docker` вообще не задаёт `EMAIL_BACKEND` (в нём лишь комментарий о том, что для
локальной разработки активен консольный бэкенд), то есть он полагается на то же значение по умолчанию.
Чтобы отправлять настоящую почту, задайте `EMAIL_BACKEND` рабочим почтовым бэкендом Django: SMTP (см.
[SMTP и Mailtrap](#smtp-and-mailtrap) ниже) или `django_ses.SESBackend` (см.
[Amazon SES](#amazon-ses)); `django_ses` всегда присутствует в `INSTALLED_APPS`, поэтому пакет
доступен независимо от выбранного бэкенда.

Есть и второй, более грубый способ, которым бэкенд переключается на SES: если задать
`ENV_TYPE=prod`, импортируется `backend/crm/server_settings.py`, который безусловно жёстко задаёт
`MAILERS = {"default": {"BACKEND": "django_ses.SESBackend"}}`, перекрывая любое значение
`EMAIL_BACKEND`, заданное вами напрямую. `ENV_TYPE=prod` также требует, чтобы `AWS_BUCKET_NAME`,
`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SES_REGION_NAME`, `AWS_SES_REGION_ENDPOINT` и
`SENTRY_DSN` уже были заданы (если какой-то нет, при импорте возникает обычный `KeyError`), и жёстко
задаёт `SESSION_COOKIE_DOMAIN = ".bottlecrm.io"`. Все последствия описаны в разделе
[Развёртывание в продакшене](production-deploy.md#static-files). Если вам нужен только SES для
почты без побочных эффектов `ENV_TYPE=prod` (S3, Sentry, домен cookie), задайте напрямую
`EMAIL_BACKEND=django_ses.SESBackend` и оставьте `ENV_TYPE=dev`.

`DEFAULT_FROM_EMAIL` (по умолчанию `noreply@localhost`) это адрес отправителя для каждого исходящего
сообщения; `ADMIN_EMAIL` (по умолчанию `admin@localhost`) с ним не связан: его использует
`manage.py create_default_admin` для создаваемой учётной записи администратора, это не почтовая
настройка.

## SMTP и Mailtrap {#smtp-and-mailtrap}

Задайте `EMAIL_BACKEND=django.core.mail.backends.smtp.EmailBackend`, чтобы отправлять почту через
любой SMTP-сервер. `EMAIL_HOST`, `EMAIL_PORT`, `EMAIL_HOST_USER`, `EMAIL_HOST_PASSWORD`,
`EMAIL_USE_TLS`, `EMAIL_USE_SSL` и `EMAIL_TIMEOUT` читаются в `MAILERS["default"]["OPTIONS"]`;
незаданные `EMAIL_PORT` и `EMAIL_TIMEOUT` вообще не попадают в `OPTIONS`, а не передаются как `0`,
поэтому порт Django выбирает сам: 465 с `EMAIL_USE_SSL`, 587 с `EMAIL_USE_TLS`, иначе 25. Незаданный
или пустой `EMAIL_HOST` означает `localhost`, то есть локальный релей. Как описано выше,
`ENV_TYPE=prod` всё равно принудительно включает SES независимо от этих переменных, поэтому SMTP
действует только с `ENV_TYPE=dev` (по умолчанию). Чтобы запустить продакшен-установку на SMTP,
оставьте `ENV_TYPE` незаданным и задайте `EMAIL_BACKEND` напрямую, так же как для SES без побочных
эффектов `ENV_TYPE=prod`.

Mailtrap лишь один из SMTP-провайдеров; ничто в кодовой базе не завязано на Mailtrap, это просто
разобранный пример с реальными значениями хоста и порта.

### Mailtrap Email Sandbox (разработка и staging) {#mailtrap-email-sandbox-development-and-staging}

Sandbox перехватывает исходящую почту в ящик, который вы просматриваете в интерфейсе Mailtrap, вместо
доставки реальному получателю. Это удобно для общего dev- или staging-развёртывания, где тестовые
письма не должны доходить до реальных адресов клиентов. Из SMTP-настроек ящика Sandbox:

```bash
EMAIL_BACKEND="django.core.mail.backends.smtp.EmailBackend"
EMAIL_HOST="sandbox.smtp.mailtrap.io"
EMAIL_PORT=2525
EMAIL_HOST_USER="<inbox username>"
EMAIL_HOST_PASSWORD="<inbox password>"
EMAIL_USE_TLS=True
EMAIL_TIMEOUT=10
```

Когда почта начнёт приходить в ящик, стоит прогнать почтовые шаблоны проекта (приветствие, ссылка для
входа, вход в портал, ответ по обращению) через вкладки HTML Check и Spam Analysis, поскольку они
проверяют отображение в большем числе почтовых клиентов, чем предпросмотр в браузере. Используйте
отдельный ящик Sandbox для каждого окружения (dev, staging, CI), а не общий, иначе сообщения одного
окружения перемешаются с сообщениями другого.

### Mailtrap Email Sending (продакшен) {#mailtrap-email-sending-production}

Email Sending доставляет почту реальному получателю и требует предварительно подтвердить домен
отправителя в панели Mailtrap; задайте `DEFAULT_FROM_EMAIL` адресом на этом подтверждённом домене,
иначе провайдер отклонит отправку. Его SMTP-настройки:

```bash
EMAIL_BACKEND="django.core.mail.backends.smtp.EmailBackend"
EMAIL_HOST="live.smtp.mailtrap.io"
EMAIL_PORT=587
EMAIL_HOST_USER="api"
EMAIL_HOST_PASSWORD="<API token>"
EMAIL_USE_TLS=True
```

Как и с любым SMTP-провайдером, `send_welcome_email`, `send_magic_link_email` и
`send_portal_login_email` в `backend/common/tasks.py` записывают сбой SMTP в лог, а не выбрасывают
исключение (см. ниже), поэтому, если ожидаемое письмо так и не пришло, смотрите логи воркера, а не
ответ API.

## Amazon SES {#amazon-ses}

Когда `MAILERS["default"]["BACKEND"]` разрешается в `django_ses.SESBackend` (каким бы из двух
описанных выше путей вы к этому ни пришли), `crm/settings.py` читает `AWS_SES_REGION_NAME` (по
умолчанию `ap-south-1`) и `AWS_SES_REGION_ENDPOINT` (по умолчанию
`email.{AWS_SES_REGION_NAME}.amazonaws.com`, вычисляется из заданного вами региона). Учётные данные AWS
`django-ses`/`boto3` неявно читают из `AWS_ACCESS_KEY_ID` и `AWS_SECRET_ACCESS_KEY`, если вы их
задали; если нет, `boto3` переходит к учётным данным IAM-роли, и это предполагаемый путь при работе
внутри AWS (роль экземпляра EC2/ECS) вместо долгоживущих ключей доступа в окружении.

Задачи Celery, которые фактически отправляют почту (`send_welcome_email`, `send_magic_link_email` и
`send_portal_login_email` в `backend/common/tasks.py`), перехватывают `botocore.exceptions.ClientError`
и `OSError` (что покрывает `smtplib.SMTPException` и сбои соединения SMTP-бэкенда выше) вокруг вызова
`msg.send()` и записывают сбой в лог, не давая задаче выбросить исключение. Сделано это именно потому,
что почтовый провайдер может отклонить отправку (неподтверждённый отправитель, адрес получателя в
списке подавления, выход за пределы SES sandbox, неверные учётные данные SMTP) по причинам, которые
являются проблемой провайдера, а не ошибкой в задаче. Если ожидаемое письмо так и не пришло, смотрите
логи воркера, а не результат задачи Celery.

## Брокер и бэкенд результатов {#broker-and-result-backend}

`CELERY_BROKER_URL` и `CELERY_RESULT_BACKEND` в `crm/settings.py` по умолчанию равны
`redis://localhost:6379/0`, и `.env.example`, и `.env.docker` оставляют их такими (в Docker Compose
значение указывает на имя хоста сервиса `redis` вместо `localhost`). Обоим нужен доступный экземпляр
Redis: `backend/crm/celery.py` создаёт `Celery("crm")` и вызывает
`app.config_from_object("django.conf:settings", namespace="CELERY")`, поэтому Celery подключается
именно по этим двум настройкам Django; отдельного конфигурационного файла Celery нет.

## Запуск воркера {#running-a-worker}

```bash
cd backend
uv run celery -A crm worker --loglevel=INFO
```

Этот процесс выполняет задачи, поставленные в очередь API: отправку описанных выше писем, уведомления
об упоминаниях, распространение членства в командах и многое другое. Для всего, что работает по
расписанию, нужен отдельный процесс `celery beat`: `backend/crm/celery.py` регистрирует
`app.conf.beat_schedule` с пятнадцатью периодическими записями, включая генерацию регулярных счетов
и проверки просроченных и истёкших коммерческих предложений (ежедневно), повторные попытки
исходящих вебхуков и [напоминание об ожидающих лидах](../features/lead-alerts.md#the-waiting-reminder)
(каждую минуту), сканирование нарушений SLA по обращениям (каждые 5 минут), очистку зависших
таймеров (каждые 30 минут), счета по ретейнерам (ежечасно, в 20 минут каждого часа: месяц каждого
ретейнера проекта формируется в черновик в течение часа после полуночи организации) и ночную
очистку прочитанных уведомлений, истёкших записей refresh-токенов, логов доставки вебхуков и
запусков автоматизаций:

```bash
cd backend
uv run celery -A crm beat --loglevel=INFO
```

Ни один из этих процессов не нужен, чтобы сам API отвечал на запросы; они нужны только для того,
чтобы фоновая и плановая работа действительно выполнялась. Запущенный `beat` сохраняет расписание, с
которым стартовал, поэтому перезапустите его после обновления, добавляющего запись, иначе новая
задача никогда не сработает. `docker-compose.yml` запускает оба как
отдельные сервисы, `celery-worker` и `celery-beat`, рядом с `backend`.

## RLS в фоновых задачах {#rls-in-background-tasks}

Воркеры Celery никогда не проходят через request middleware Django, поэтому ничто не задаёт для них
сессионную переменную PostgreSQL `app.current_org` так, как `RequireOrgContext` делает это для
HTTP-запроса. Полный механизм описан в разделе
[PostgreSQL и RLS](postgresql-and-rls.md#verifying-isolation). Каждая задача в
`backend/common/tasks.py`, которая обращается к таблице в рамках организации, первой строкой вызывает
`set_rls_context(org_id)`, определённую в том же модуле:

```python
from common.tasks import set_rls_context

@shared_task
def my_task(data_id, org_id):
    set_rls_context(org_id)  # required before any org-scoped query
    ...
```

Если пропустить этот вызов, задача выполняется с тем RLS-контекстом, который случайно оказался у
подключения воркера к базе данных; на свежем подключении он пуст, а это (согласно fail-safe дизайну,
описанному в разделе [PostgreSQL и RLS](postgresql-and-rls.md#why-rls)) означает, что запрос вернёт
ноль строк, а не строки другой организации. Но это всё равно ошибка: задача, которая должна работать с
реальными данными, незаметно ничего не делает. `flush_expired_refresh_tokens` представляет законный
случай, когда контекст вообще не нужен: она работает с таблицей `OutstandingToken` из simplejwt,
которой нет в `ORG_SCOPED_TABLES` и у которой нет столбца `org_id`, так что фильтровать по организации
там изначально нечего.

`purge_read_notifications` не относится к такому случаю, несмотря на утверждение в её собственном
docstring, что «RLS does not need a per-org context here». `notification` **входит** в
`ORG_SCOPED_TABLES` (`backend/common/rls/__init__.py`) и получает ту же политику
`FORCE ROW LEVEL SECURITY`, что и любая другая таблица в рамках организации, а эта задача никогда не
вызывает `set_rls_context`. Поэтому на роли базы данных без прав суперпользователя, которую требует
проект, она выполняется с пустым RLS-контекстом, и её `DELETE` затрагивает ноль строк: вместо очистки
старых прочитанных уведомлений во всех организациях она незаметно не удаляет ничего. Это ровно тот
сбой, что описан выше, а не исключение из него: действующая ошибка в собственной плановой задаче
кодовой базы, о которой стоит знать, если вы рассчитываете, что она не даст таблице `notification`
расти без ограничений.
