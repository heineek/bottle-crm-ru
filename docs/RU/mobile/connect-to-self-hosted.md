# Подключение к своему серверу

Прочитайте эту страницу, прежде чем запускать или собирать мобильное приложение для работы с чем-либо,
кроме `api.bottlecrm.io`. Если коротко: URL бэкенда фиксируется при компиляции приложения, и вы
выбираете его флагом сборки, а не правкой исходников.

## Базовый URL времени компиляции {#the-compile-time-base-url}

`mobile/lib/config/api_config.dart` определяет один хост для всех запросов:

| Сборка | Без `API_BASE_URL` | С `--dart-define=API_BASE_URL=<url>` |
| --- | --- | --- |
| Отладочная (`flutter run`) | `http://localhost:8000` | `<url>`, `http://` допустим |
| Релизная (`flutter build`) | `https://api.bottlecrm.io` | `<url>`, который должен начинаться с `https://` |

Выбор на этапе компиляции сделан намеренно. Настройка во время выполнения позволила бы всему, что
может писать в хранилище приложения, перенаправить каждый запрос, а вместе с ним и каждый JWT, на
сервер по своему выбору. Поэтому приложение всё время жизни установки работает с тем URL, который
был задан при сборке, а сборка из магазина приложений может обращаться только к
`https://api.bottlecrm.io`.

## Как направить приложение на ваш бэкенд {#pointing-at-your-backend}

```bash
# Debug build against a backend on your machine (Android emulator)
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000

# Release build against your own server
flutter build appbundle --release --dart-define=API_BASE_URL=https://crm.example.com
```

Завершающий слеш отбрасывается. Релизная сборка с обычным URL `http://` отказывается запускаться,
чтобы не отправлять токены в незашифрованном виде. Горячая перезагрузка не подхватывает
изменённый define: остановите и запустите заново или пересоберите (см.
[Релизные сборки](release-builds.md)). Для входа через Google нужен собственный client id для
вашего бэкенда, который тоже передаётся через define; см. ниже.

Несколько моментов, касающихся самого URL:

- **Схема и доступность зависят от того, где запущено приложение, а не только от того, что отдаёт
  ваш бэкенд.**
  - **Эмулятор Android** не видит хост-машину как `localhost`: изнутри эмулятора
    `localhost`/`127.0.0.1` означает сам эмулятор. Задокументированный адрес петлевого интерфейса
    хоста: `10.0.2.2`. Если ваш бэкенд запущен через `docker compose up` на машине разработчика
    (см. [Docker](../self-hosting/docker.md), где привязка идёт к `0.0.0.0:8000`), направьте сборку
    для эмулятора на `http://10.0.2.2:8000`, а не на `http://localhost:8000`.
  - **Симулятор iOS** работает нативно на Mac (это не отдельное пространство имён виртуальной сети,
    как у эмулятора Android), поэтому `http://localhost:8000` изнутри симулятора действительно
    достигает бэкенда, запущенного на хост-машине Mac.
  - **Физическое устройство** (Android или iOS) вообще не может достучаться до «машины
    разработчика» через `localhost` или `10.0.2.2`: ему нужен IP-адрес вашей машины в локальной
    сети, оба устройства должны быть в одной сети, и брандмауэр не должен блокировать порт.
- **Обе платформы по умолчанию блокируют обычный HTTP, и ничто в этом проекте не включает его
  обратно, но действует ли это умолчание на трафик этого приложения, по одному репозиторию
  установить нельзя.** Две политики и то, что (не) настроено для каждой:
  - **Android** по умолчанию запрещает незашифрованный трафик для приложений с
    `targetSdkVersion` 28 или выше. Это определяется `targetSdk`, а не `minSdk`.
    `android/app/build.gradle.kts` фиксирует `minSdk = 28` (строка 40), но
    `targetSdk = flutter.targetSdkVersion` на следующей строке в этом проекте *не* зафиксирован.
    Он следует за установленным у вас Flutter SDK (см. [Релизные сборки](release-builds.md)). В
    любом случае в `AndroidManifest.xml` нет ни атрибута `android:usesCleartextTraffic`, ни
    `android:networkSecurityConfig`, и нигде в `android/app/src/main/res/` нет ресурса
    `network_security_config.xml` (проверено напрямую): ничто здесь не разрешает незашифрованный
    трафик обратно.
  - **iOS** имеет аналогичное умолчание: App Transport Security блокирует обычный HTTP, если в
    `Info.plist` приложения нет исключения `NSAppTransportSecurity`, а в `ios/Runner/Info.plist`
    его нет.
  - Однако на обеих платформах это умолчание обычно применяет собственный HTTP-стек платформы:
    `NetworkSecurityPolicy` в Android, к которому обращаются `HttpURLConnection`/OkHttp/WebView;
    App Transport Security в iOS, которая действует внутри `NSURLSession`/CFNetwork. Запросы этого
    приложения явно не проходят ни через один из них: `api_service.dart` создаёт клиента из
    стандартного `Client()` пакета `package:http`
    (`final http.Client _client = http.Client();`), который на платформах, отличных от веба,
    превращается в `IOClient`, тонкую обёртку над собственным `HttpClient` из `dart:io`
    (исходники пакета `http`, `lib/src/client.dart` / `lib/src/io_client.dart`), а не в
    `cronet_http` или `cupertino_http`, ни один из которых здесь не является зависимостью.
    Учитывает ли сокетный уровень `dart:io` на какой-либо из платформ политику ОС по
    незашифрованному трафику или ATS, чтением исходников не установить; для этого нужна реальная
    сборка, проверенная на хосте с обычным HTTP, что выходит за рамки этой страницы.

  Считайте HTTPS обязательным, как бы ни разрешилась эта неясность на практике: это соединение
  передаёт JWT и данные клиентов (см. [выше](#the-compile-time-base-url)), и оно должно быть
  зашифровано само по себе, а не потому, что так получилось из-за умолчания платформы. Если вам
  всё же нужно проверить работу напрямую со стеком [Docker](../self-hosting/docker.md) на обычном
  HTTP, попробуйте; если соединение не устанавливается так, что это похоже на блокировку
  незашифрованного трафика или ATS, обходной путь на стороне Android: добавить собственный
  `android:usesCleartextTraffic="true"` (или ограниченный `network_security_config.xml`) в
  `AndroidManifest.xml`. Надёжное решение на обеих платформах: поставить перед бэкендом
  [обратный прокси](../self-hosting/production-deploy.md#reverse-proxy), который завершает TLS,
  потому что сам бэкенд TLS тоже не завершает.

## Настройка входа через Google {#google-sign-in-configuration}

[Вход по magic-ссылке из письма](../getting-started/first-sign-in.md#magic-links) не требует
настройки ни с одной стороны и работает с любым бэкендом. Вход через Google требует настройки
**и** бэкенда, **и** мобильного приложения, и эти настройки должны согласовываться друг с другом.
Это сложнее, чем [настройка Google OAuth для веб-приложения](../self-hosting/google-oauth.md),
потому что мобильный сценарий [основан на ID-токене, а не на
перенаправлении](../self-hosting/google-oauth.md#mobile-id-tokens).

**Сторона бэкенда** (предварительное условие, подробно описано на странице
[Google OAuth](../self-hosting/google-oauth.md)): `GOOGLE_CLIENT_ID` должен содержать настоящий
идентификатор Web-клиента Google OAuth, потому что `GoogleIdTokenView` сверяет аудиторию каждого
ID-токена ровно с этим значением
(`google.oauth2.id_token.verify_oauth2_token(..., settings.GOOGLE_CLIENT_ID)`). Оставьте его
пустым, и вход через Google останется выключенным. Тогда единственный способ входа: magic-ссылки.

**Сторона Android**: три вещи, в поставляемом виде все привязаны к собственному проекту Google
Cloud BottleCRM:

1. Приложение входит с client id OAuth типа **Web** в качестве `serverClientId`: это аудитория,
   с которой сверяет `GOOGLE_CLIENT_ID` вашего бэкенда. По умолчанию используется client id
   BottleCRM, который ваш бэкенд отклонит. Собирайте приложение с client id Web-клиента из
   **вашего собственного** проекта Google Cloud, тем же значением, что и `GOOGLE_CLIENT_ID`
   вашего бэкенда:
   ```bash
   --dart-define=GOOGLE_SERVER_CLIENT_ID=<your-web-client-id>.apps.googleusercontent.com
   ```
2. Для входа на Android дополнительно нужен OAuth-клиент типа **Android** (отдельный от
   Web-клиента выше), зарегистрированный в Google Cloud и привязанный к `applicationId` вашего
   приложения и отпечатку SHA-1 сертификата, которым подписана сборка. Получите отпечаток командой
   `cd android && ./gradlew signingReport`. Для этого уже должен существовать
   `android/local.properties` с записью `flutter.sdk` (`settings.gradle.kts` требует её через
   `require` и иначе падает с `"flutter.sdk not set in local.properties"`); этот файл в
   gitignore (`android/.gitignore:6`) и записывается собственными командами Flutter, которые
   вызывают Gradle (`flutter run`, `flutter build ...`), а не одним `flutter pub get`, так что
   убедитесь, что хотя бы раз запустили одну из них. По этой же причине тип сборки `debug` в
   `build.gradle.kts` подписывается релизным ключом, когда существует `key.properties` (см.
   [Релизные сборки → Подпись](release-builds.md#signing)), а не локальным отладочным хранилищем
   ключей Android Gradle Plugin, чтобы SHA-1 локально установленной отладочной сборки совпадал с
   зарегистрированным.
3. Конфигурация Firebase/Crashlytics (`android/app/google-services.json`) нужна, чтобы сборка
   Gradle вообще прошла, когда применён плагин `com.google.gms.google-services` (а он применяется
   безусловно, в `android/app/build.gradle.kts`); в репозитории лежит только заготовка
   `google-services.json.template`, настоящий файл вы берёте из собственного проекта
   Firebase/Google Cloud. Что делает этот плагин, если файла нет, см. в разделе
   [Релизные сборки](release-builds.md).

**Сторона iOS в поставляемом виде в этом репозитории не настроена вообще**, независимо от того,
что вы меняете на Android. Нативный SDK, который оборачивает плагин `google_sign_in_ios`
(зафиксирован на `6.3.0` в `pubspec.lock`), может получить свой client ID из трёх мест, которые
обработчик `configureWithParameters:` самого плагина проверяет в таком порядке
(`FLTGoogleSignInPlugin.m:180-191`):

1. аргумент `clientId:` во время выполнения, переданный в `GoogleSignIn.instance.initialize(...)`;
2. ключ `CLIENT_ID` во встроенном `GoogleService-Info.plist`;
3. собственный ключ `GIDClientID` в `Info.plist`, который `GIDSignIn` автоматически читает по
   умолчанию, когда не задано ни одно из двух предыдущих. Комментарий в исходниках самого плагина
   называет это «the recommended configuration method».

Здесь нет ни одного из трёх: вызов `initialize()` в `auth_service.dart` передаёт только
`serverClientId` и никогда `clientId`; `ios/Runner/GoogleService-Info.plist` не существует (он в
gitignore, и в отличие от Android закоммиченной заготовки нет); а поиск по всему дереву `ios/`
строк `GIDClientID`, `CFBundleURLTypes` и `REVERSED_CLIENT_ID` ничего не находит.

При этом ошибки при запуске не возникает. Когда все три источника отсутствуют, внутренний
`configurationWithClientIdentifier:...` плагина возвращает `nil`, и обработчик просто не
назначает новую конфигурацию (`if (configuration) { self.signIn.configuration = configuration; }`)
вместо того чтобы упасть; конфигурация `GIDSignIn` просто остаётся незаданной. Вызов
`initialize()` в `auth_service.dart` в любом случае обёрнут в `try`/`catch`, который при ошибке
только вызывает `debugPrint`, поэтому на iOS приложение в любом случае запускается как обычно.
Пробел становится заметен, только когда пользователь действительно нажимает «Sign in with Google»,
а конфигурации для входа нет.

**Наименее инвазивное исправление: источник №3 выше, путь через `Info.plist`, который рекомендует
сам `GIDSignIn`, потому что он не требует изменений в коде Dart:**

```xml
<!-- ios/Runner/Info.plist -->
<key>GIDClientID</key>
<string>YOUR-IOS-CLIENT-ID.apps.googleusercontent.com</string>
```

плюс обработчик обратного вызова по URL-схеме, который, согласно README самого пакета
`google_sign_in_ios`, нужен независимо от того, каким из трёх путей вы передаёте сам client ID:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>com.googleusercontent.apps.YOUR-REVERSED-CLIENT-ID</string>
    </array>
  </dict>
</array>
```

Оба значения берутся из OAuth-клиента типа iOS в вашем проекте Google Cloud: в
`GoogleService-Info.plist` для этого проекта они находятся под `CLIENT_ID` и `REVERSED_CLIENT_ID`
соответственно, либо их можно скопировать прямо из Cloud Console, вообще не скачивая этот файл.
Альтернатива: передать `clientId:` (и при необходимости `serverClientId:`) аргументами в
`_googleSignIn.initialize(...)` в `auth_service.dart` вместо задания `GIDClientID` (источник №1
вместо №3), но запись `CFBundleURLTypes` выше нужна в любом случае.

Это не связано с Firebase Crashlytics, который в этом коде намеренно работает только на Android:
`main.dart` явно защищает инициализацию Firebase условием
`defaultTargetPlatform == TargetPlatform.android` с комментарием, что у iOS «пока» (yet) нет
`GoogleService-Info.plist`. Не считайте пробел с Crashlytics доказательством того, что пробел со
входом через Google столь же намеренный: это две разные области конфигурации, у которых просто
отсутствует один и тот же файл.
