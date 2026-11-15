# Google OAuth

BottleCRM поддерживает вход через Google и в веб-приложении (обмен authorization code с PKCE), и в
мобильном приложении (Google ID token, отправляемый напрямую на бэкенд). Оба способа необязательны:
развёртывание работает и без них, используя
[вход по ссылке из письма](../getting-started/first-sign-in.md), пока вы не настроите OAuth-клиент
Google.

## Регистрация OAuth-клиента {#registering-an-oauth-client}

Создайте в Google Cloud Console OAuth 2.0 Client ID типа «Web application». Redirect URI, который
нужно для него разрешить, строится страницей входа фронтенда
(`frontend/src/routes/(no-layout)/login/+page.server.js`) как `${GOOGLE_LOGIN_DOMAIN}/login`;
`GOOGLE_LOGIN_DOMAIN` является переменной окружения **фронтенда** (`frontend/.env.example` задаёт ей по
умолчанию `http://localhost:5181`), поэтому регистрировать в Google нужно `http://localhost:5181/login`
для локальной разработки или `https://<your-frontend-host>/login` в продакшене. Для мобильного
сценария отдельная регистрация redirect не нужна: он вообще не использует redirect (см.
[ID-токены в мобильном приложении](#mobile-id-tokens) ниже).

Фронтенду нужна собственная копия client ID; `frontend/.env.example` задаёт `GOOGLE_CLIENT_ID`
(только client ID; комментарий в этом файле прямо говорит «secret is on backend»), потому что URL
авторизации Google строится на стороне клиента (`client_id`, `redirect_uri`, PKCE `code_challenge` и
CSRF-параметр `state`). Client secret всегда хранится только на бэкенде.

## Настройка бэкенда {#backend-configuration}

`backend/crm/settings.py` читает две переменные, связанные с Google, обе по умолчанию пустые строки:

```python
GOOGLE_CLIENT_ID = os.environ.get("GOOGLE_CLIENT_ID", "")
GOOGLE_CLIENT_SECRET = os.environ.get("GOOGLE_CLIENT_SECRET", "")
```

Именно их бэкенд отправляет на token-эндпоинт Google при обмене authorization code (см. ниже) и
использует как ожидаемую аудиторию (audience) при проверке мобильного ID-токена. Если оставить любую
из них пустой, каждый такой обмен или проверка завершится ошибкой, так что вход через Google
фактически выключен, пока обе не заданы. `.env.docker` и `.env.example` поставляются с обеими
пустыми, под комментарием «optional. Leave blank to disable».

Настройки redirect URI намеренно нет. Redirect URI для обмена токенов берётся из тела запроса,
которое фронтенд отправляет при каждом вызове (см. [Сценарий callback с PKCE](#the-pkce-callback-flow)).
Настройка `GOOGLE_REDIRECT_URI` какое-то время существовала: она читалась в Django и нигде не
использовалась, из-за чего администраторы тратили время на настройку того, что ни на что не влияло;
её удалили, а не стали документировать.

## Сценарий callback с PKCE {#the-pkce-callback-flow}

Веб-сценарий представляет собой стандартный OAuth Authorization Code flow с PKCE, разделённый между
фронтендом и `GoogleOAuthCallbackView`:

1. `login/+page.server.js` генерирует пару PKCE `code_verifier`/`code_challenge` и случайный `state`,
   сохраняет verifier и state в короткоживущих httpOnly cookie и перенаправляет браузер на эндпоинт
   авторизации Google с `code_challenge`.
2. Google перенаправляет обратно на `/login?code=...&state=...`. Фронтенд сверяет полученный `state`
   с cookie (защита от CSRF) и считывает сохранённый `code_verifier`, затем делает вызов
   «сервер-сервер»: `POST /api/auth/google/callback/`
   (`GoogleOAuthCallbackView`, подключён в `backend/common/urls.py:67`) с `code`, `code_verifier`
   и `redirect_uri` в теле.
3. `GoogleOAuthCallbackView` обменивает code на токены напрямую у Google
   (`https://oauth2.googleapis.com/token`), отправляя `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, а
   также полученные `redirect_uri` и `code_verifier`. Именно этому шагу нужен client secret, поэтому
   он должен выполняться на бэкенде, а не в браузере.
4. View декодирует `id_token`, который возвращает Google (комментарий в его коде отмечает, что это
   безопасно без проверки подписи именно потому, что токен пришёл напрямую от Google по HTTPS на
   предыдущем шаге, а не от недоверенного клиента), и требует, чтобы `email_verified` было true, прежде
   чем вообще доверять адресу почты: неподтверждённый адрес никогда не создаёт учётную запись и не
   выполняет вход в неё.
5. Он получает или создаёт `User` по email, отвечает 403, если учётная запись деактивирована
   (`user.is_active`), и выдаёт собственную пару JWT BottleCRM через
   `OrgAwareRefreshToken.for_user_and_org(user, None)`. Организация `None` означает, что в токене нет
   claim `org_id`: пользователю всё равно нужно выбрать организацию
   ([Переключение организаций](../getting-started/first-sign-in.md#choosing-an-organization)), прежде
   чем заработает любой запрос в рамках организации.

## ID-токены в мобильном приложении {#mobile-id-tokens}

Мобильное приложение полностью обходится без redirect: Google Sign-In на устройстве возвращает
ID-токен, выданный Google, и приложение отправляет его прямо на `POST /api/auth/google/`
(`GoogleIdTokenView`, подключён в `backend/common/urls.py:69`) в виде `{"idToken": "..."}`. В отличие
от веб-callback выше, этот view проверяет токен криптографически, `google.oauth2.id_token.
verify_oauth2_token(id_token_str, google_requests.Request(), settings.GOOGLE_CLIENT_ID)`: подпись
сверяется с публичными ключами Google, а аудитория с собственным `GOOGLE_CLIENT_ID` бэкенда, поэтому
токен, выданный для другого клиента, отклоняется. Он применяет те же проверки `email_verified` и
неактивной учётной записи, что и веб-сценарий, затем возвращает `JWTtoken`, `refresh_token` и список
организаций, в которых у пользователя уже есть `Profile` (`{"id", "name", "role"}` для каждой), чтобы
мобильное приложение могло показать выбор организации без второго запроса.
