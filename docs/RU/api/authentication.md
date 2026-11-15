# Аутентификация

На этой странице описаны вызовы, которыми клиент входит в систему и сохраняет сессию: что отправить,
что придёт в ответ и что означает каждая ошибка. Устройство этих эндпоинтов (время жизни токенов,
claims, почему ротация реализована вручную, зачем рядом с JWT существуют персональные токены доступа и
API-ключи организации) описано в разделе [Архитектура: аутентификация](../architecture/authentication.md);
эта страница его не повторяет и ему не противоречит. Пошаговое руководство по выбору способа входа
при локальной разработке: [Первый вход](../getting-started/first-sign-in.md).

Все три интерактивных способа входа ниже (Google OAuth, Google ID token и оба эндпоинта проверки
magic link) выпускают токены через один и тот же хелпер `OrgAwareRefreshToken.for_user_and_org()` и
являются публичными: `permission_classes = []`, `authentication_classes = []`
(`backend/common/views/auth_views.py`). Ни один из них не требует уже имеющегося токена.

Всё, что описано на этой странице, выполняет вход пользователя **вашей** стороны организации. Клиент,
входящий в клиентский портал поддержки, использует другой набор эндпоинтов и совершенно другие
учётные данные, и токен одной области не работает в другой; см. [Клиентский портал](customer-portal.md).

## Google OAuth (веб) {#google-oauth-web}

`POST /api/auth/google/callback/` (`GoogleOAuthCallbackView`,
`backend/common/views/auth_views.py:52-198`) завершает обмен authorization code по PKCE для
фронтенда на SvelteKit.

Тело запроса:

```json
{
  "code": "<authorization code from Google's redirect>",
  "code_verifier": "<PKCE verifier the frontend generated>",
  "redirect_uri": "<the redirect_uri used in the initial authorize request>"
}
```

`redirect_uri` берётся из этого поля, а не из какой-либо серверной настройки; серверной настройки
redirect URI просто нет. Настройки, которые действительно важны, описаны в разделе
[Google OAuth](../self-hosting/google-oauth.md).
Представление обменивает эти значения у Google, декодирует полученный ID token и сразу отклоняет вход,
если собственный claim Google `email_verified` не равен `true`. Неподтверждённый адрес Google никогда
не попадает в базу данных. При успехе:

```json
{
  "access_token": "<jwt>",
  "refresh_token": "<jwt>",
  "user": {"id": "<uuid>", "email": "user@example.com"}
}
```

Токен выпускается без claim организации (`OrgAwareRefreshToken.for_user_and_org(user, None)`,
`:190`): оба потока Google всегда возвращают токен без организации (потоки magic link ведут себя
иначе, см. [Magic links](#magic-links) ниже), поэтому следующим вызовом клиента обычно становится
[переключение организации](#switching-organization).

Ответы с ошибкой: `400`, если не передан `code`/`code_verifier`/`redirect_uri`, ID token
недействителен, отсутствует email или email не подтверждён; `502`, если эндпоинт токенов Google
вообще недоступен (`requests.RequestException`, `:110-114`); `403`, если итоговая учётная запись
деактивирована.

## Google ID token (мобильное приложение) {#google-id-token-mobile}

`POST /api/auth/google/` (`GoogleIdTokenView`, `backend/common/views/auth_views.py:201-319`) это
мобильный аналог: клиент сам уже получил Google ID token и передаёт его напрямую, а не код, который
обменивает сервер.

Тело запроса:

```json
{"idToken": "<google id token>"}
```

Сервер проверяет токен у Google (`google.oauth2.id_token.verify_oauth2_token`, сверка с
`GOOGLE_CLIENT_ID`) и применяет ту же проверку `email_verified`, что и веб-поток. При успехе:

```json
{
  "JWTtoken": "<jwt access token>",
  "refresh_token": "<jwt>",
  "user": {"id": "<uuid>", "email": "user@example.com", "name": "user", "profileImage": ""},
  "organizations": [{"id": "<uuid>", "name": "Acme", "role": "ADMIN"}]
}
```

Обратите внимание: поле access-токена здесь называется `JWTtoken`, а не `access_token`. У двух потоков
Google разная форма ответа, поэтому клиент, поддерживающий оба, не может читать access-токен из них
одинаково. Кроме того, этот ответ сразу содержит `organizations` (существующие членства вызывающего),
чего нет в ответе веб-callback выше; мобильный клиент может предложить выбор организации без
лишнего запроса `GET /api/auth/me/`. Ответы с ошибкой повторяют веб-поток: `400`, если `idToken`
не передан или недействителен, отсутствует email или email не подтверждён; `403` для
деактивированной учётной записи.

## Magic links {#magic-links}

Вход без пароля: два способа доставки, три эндпоинта.

`POST /api/auth/magic-link/request/` (`MagicLinkRequestView`,
`backend/common/views/auth_views.py:586-655`):

```json
{"email": "user@example.com", "delivery": "link"}
```

`delivery` необязателен и по умолчанию равен `"link"`; единственное другое значение `"code"`. Этот
эндпоинт **всегда возвращает `200`** с одним и тем же телом, независимо от того, есть ли у адреса
учётная запись, не прошёл ли он валидацию (некорректный email или одноразовый домен) и не сработало ли
ограничение частоты (пять токенов на адрес в час): все эти случаи сводятся к одному общему ответу:

```json
{"message": "If this email is valid, you will receive a sign-in link."}
```

Так сделано намеренно, см. [Первый вход](../getting-started/first-sign-in.md#magic-links). Это
значит, что по ответу клиент не может отличить «отправлено» от «отклонено»; обрабатывать `400` здесь
вообще не нужно. Сгенерированный токен истекает через 10 минут.

Единственный другой ответ это `429` от лимитов на клиента и на весь сайт в
`backend/common/throttles.py` (`MAGIC_LINK_THROTTLE_IP`, по умолчанию `30/hour`, и
`MAGIC_LINK_THROTTLE_GLOBAL`, по умолчанию `300/hour`). Они срабатывают до чтения email, поэтому `429`
тоже ничего не сообщает об адресе.

`POST /api/auth/magic-link/verify/` (`MagicLinkVerifyView`,
`backend/common/views/auth_views.py:658-768`) обменивает токен из письма со ссылкой:

```json
{"token": "<64-character hex token from the emailed link>"}
```

`POST /api/auth/magic-link/verify-code/` (`MagicLinkVerifyCodeView`,
`backend/common/views/auth_views.py:771-899`) вместо этого обменивает одноразовый код:

```json
{"email": "user@example.com", "code": "123456"}
```

Код проверяется под `select_for_update`, чтобы две одновременные попытки проверки не увидели одно и
то же число попыток, и сгорает (помечается использованным) после 5 неудачных попыток, даже если
позже прислать правильный код. Оба эндпоинта проверки возвращают одинаковый ответ при успехе:

```json
{
  "access_token": "<jwt>",
  "refresh_token": "<jwt>",
  "user": {
    "id": "<uuid>",
    "email": "user@example.com",
    "profile_pic": "",
    "is_active": true,
    "organizations": [{"id": "<uuid>", "name": "Acme", "role": "ADMIN", "is_organization_admin": true, "has_sales_access": true, "has_marketing_access": true}]
  }
}
```

с одним дополнением: если у пользователя есть **хотя бы одно** активное членство в организации,
токен выпускается привязанным к одной из них, а ответ дополнительно содержит:

```json
{"current_org": {"id": "<uuid>", "name": "Acme"}}
```

Условие не в том, что членство ровно одно: `Profile.objects.filter(user=user,
is_active=True).first()` (`backend/common/views/auth_views.py:740,745-746` для verify, `:874,878-879`
для verify-code) берёт активный профиль, который оказывается первым при сортировке, а сортировка
`Profile` по умолчанию `("-created_at",)` (`backend/common/models.py:238`). Поэтому для пользователя,
состоящего в нескольких организациях, токен привязывается к его **самому недавно созданному**
членству, а не обязательно к тому, с которым он собирается работать. Клиент для пользователя, который
может состоять в нескольких организациях, не может считать, что проверка magic link всегда оставляет
выбор организации на следующий шаг. Нужно проверить, есть ли `current_org`, и дать пользователю
переключиться, если организация не та, через [переключение организации](#switching-organization).
Если активных членств нет совсем, токен возвращается без организации, как и в потоках OAuth.
Ответы с ошибкой: `400` с `{"error": "Invalid request"}`, если не прошло валидацию само тело запроса
(нет токена, некорректный email, код не из ровно 6 цифр); `400` с
`{"error": "Invalid or expired link"}` / `{"error": "Invalid or expired code"}`, если токен или код не
совпадает с неиспользованной и неистёкшей записью; `403` для деактивированной учётной записи. Проверка
создаёт пользователя, если с этим email ещё ни разу не входили, точно так же, как потоки OAuth.

## Использование access-токена {#using-an-access-token}

Передавайте access-токен в заголовке `Authorization: Bearer <access_token>`. Он действует один час.
Почему так и что происходит после истечения, описано в разделе
[Модель токенов](../architecture/authentication.md#token-model).

`GET /api/auth/me/` (`MeView`, `backend/common/views/auth_views.py:322-336`) возвращает вошедшего
пользователя и все организации, в которых у него есть активный профиль:

```json
{
  "id": "<uuid>",
  "email": "user@example.com",
  "profile_pic": "",
  "is_active": true,
  "organizations": [
    {"id": "<uuid>", "name": "Acme", "role": "ADMIN", "is_organization_admin": true, "has_sales_access": true, "has_marketing_access": true}
  ]
}
```

Про этот эндпоинт стоит знать две вещи. Он явно задаёт `authentication_classes =
[JWTAuthentication]` (`:327`), поэтому, в отличие от большинства эндпоинтов, не принимает
персональный токен доступа или API-ключ организации: здесь работает только JWT. А его точный путь
входит в короткий список, для которого `GetProfileAndOrg` полностью пропускает определение контекста
организации (`backend/common/middleware/get_company.py:29-38`). Middleware сразу возвращает управление,
не пытаясь заполнить `request.profile`/`request.org`, поэтому этому эндпоинту никогда не нужен claim
`org_id`. Благодаря этому он работает с токеном без организации, который выдают описанные выше способы
входа, и именно поэтому он удобен, чтобы только что аутентифицированный клиент получил список
организаций для выбора.

## Обновление токенов {#refreshing}

`POST /api/auth/refresh-token/` (`OrgAwareTokenRefreshView`,
`backend/common/views/auth_views.py:339-448`) обменивает refresh-токен на новую пару access/refresh:

```json
{"refresh": "<refresh token>"}
```

```json
{"access": "<new access token>", "refresh": "<new refresh token>"}
```

Обратите внимание, что имена полей здесь, `access` и `refresh`, не совпадают с
`access_token`/`refresh_token` из эндпоинтов входа выше; это единственный ответ на странице с
короткими именами. Ответы с ошибкой: `400`, если не передан `refresh`; `401`, если токен истёк,
некорректен или уже в чёрном списке (`TokenError`); `403`, если учётную запись деактивировали после
выдачи токена; `403`, если токен содержит `org_id`, в которой у пользователя больше нет активного
профиля. Что происходит со старым токеном при успешном вызове и почему, описано в разделе
[Обновление и ротация](../architecture/authentication.md#refresh-and-rotation).

## Переключение организации {#switching-organization}

`POST /api/auth/switch-org/` (`OrgSwitchView`, `backend/common/views/auth_views.py:451-583`) переводит
аутентифицированного вызывающего в другую организацию и заново выпускает оба токена с привязкой к
ней. В отличие от большинства эндпоинтов, он требует только `IsAuthenticated`, без контекста
организации, потому что должен работать и с токеном, у которого организации ещё нет:

```json
{
  "org_id": "<uuid of an org the caller has an active profile in>",
  "refresh": "<optional: the refresh token being replaced>"
}
```

```json
{
  "access_token": "<jwt bound to org_id>",
  "refresh_token": "<jwt bound to org_id>",
  "current_org": {"id": "<uuid>", "name": "Acme"},
  "profile": {"id": "<uuid>", "role": "ADMIN", "is_organization_admin": true}
}
```

`refresh` необязателен; если он передан и принадлежит вызывающему, при переключении он попадает в
чёрный список, так что токен без организации (или от предыдущей организации) сразу перестаёт работать,
а не остаётся действительным до конца своего 14-дневного срока. Почему важна проверка владельца этого
поля, описано в разделе [Переключение организации](../architecture/authentication.md#organization-switching).
Ответы с ошибкой: `400`, если `org_id` не передан или не является корректным UUID; `403`, если у
вызывающего нет активного профиля в запрошенной организации.

## Локальная разработка {#local-development}

При локальной разработке с запущенным бэкендом и `DEBUG=True` пару токенов быстрее всего получить
management-командой `devlogin`, а не через эндпоинты выше. Ей не нужен ни OAuth-провайдер, ни
исходящая почта. Она вообще отказывается запускаться, если `DEBUG` не равен `True`. Точный вызов,
флаги и правила выбора организации описаны в разделе
[Первый вход: локальная разработка](../getting-started/first-sign-in.md); `devlogin` это короткий путь
в обход эндпоинтов этой страницы, и выданные им токены одинаково работают со всеми описанными выше
эндпоинтами.
