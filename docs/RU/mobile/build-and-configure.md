# Сборка и настройка

Эта страница описывает запуск исходников Flutter из клона репозитория: зависимости, локальный
запуск и команды тестов и линтера. Она не описывает, как направить приложение на ваш собственный
бэкенд или получить подписанную релизную сборку; для этого см.
[Подключение к своему серверу](connect-to-self-hosted.md) и
[Релизные сборки](release-builds.md).

## Предварительные требования {#prerequisites}

`mobile/pubspec.yaml` объявляет:

```yaml
environment:
  sdk: ^3.8.1
```

Это единственная запись в `environment:`. Ключа `flutter:` нет. В `pubspec.yaml` для Flutter
ограничение `sdk:` в `environment:` фиксирует SDK **Dart**, а не SDK Flutter; строка
`flutter: ">=x.y.z"` отдельно зафиксировала бы Flutter, но в этом проекте её нет. Поэтому сам
проект не объявляет явной минимальной версии Flutter: `^3.8.1` означает лишь «Dart SDK 3.8.1 или
новее, но ниже 4.0.0».

При этом сохранённый в репозитории `mobile/pubspec.lock` записывает в завершающем блоке `sdks:`
ограничения SDK, реально полученные при разрешении всего графа зависимостей:

```yaml
sdks:
  dart: ">=3.12.0 <4.0.0"
  flutter: ">=3.44.0"
```

Это уже, чем собственный нижний порог проекта `^3.8.1`, потому что у ряда зависимостей (например,
`flutter_riverpod: ^3.3.1`, `go_router: ^17.2.3`, `google_fonts: ^8.1.0`) свои, более высокие
требования к SDK, а `pub` берёт пересечение всех этих требований. На практике зависимости этого
проекта разрешаются с **Flutter 3.44.0 или новее** (в нём поставляется Dart 3.12+). Это число
взято из lock-файла, а не из догадки о том, какой релиз Flutter соответствует какой версии Dart.
Файла `.fvmrc` нет, и ни один из двух workflow GitHub Actions в этом репозитории
(`.github/workflows/tests.yml`, `codeql-analysis.yml`) вообще не упоминает Flutter, Dart или
`mobile/`, так что версию не проверяет и CI. Lock-файл является единственной существующей фиксацией.

(`mobile/README.md` указывает «Flutter SDK: 3.8.1 or later»: та же ошибка, когда ограничение Dart
скопировано как версия Flutter. Используйте вместо этого числа из lock-файла выше.)

Помимо самого SDK:

- **Сборкам для Android** нужен Android SDK (через Android Studio или отдельные инструменты
  командной строки). `mobile/android/app/build.gradle.kts` задаёт
  `compileSdk = flutter.compileSdkVersion` и `targetSdk = flutter.targetSdkVersion`: оба значения
  берутся из того, что ваш установленный Flutter SDK считает текущим, а не из числа, жёстко
  прописанного в проекте. Две вещи файл всё же фиксирует сам: `ndkVersion = "28.2.13676358"`
  (комментарий поясняет, что версию «bumped to satisfy jni plugin requirement») и совместимость
  Java/Kotlin на уровне **17** (`compileOptions.sourceCompatibility` /
  `targetCompatibility = JavaVersion.VERSION_17`, продублировано в блоке
  `kotlin { compilerOptions { jvmTarget } }`). Gradle должен иметь доступ к инструментарию,
  совместимому с JDK 17.
- **Сборкам для iOS** нужны Xcode и CocoaPods, и они работают только на macOS. `mobile/README.md`
  указывает «iOS: iOS 11.0+», но реальная целевая версия развёртывания в
  `mobile/ios/Runner.xcodeproj/project.pbxproj` равна `IPHONEOS_DEPLOYMENT_TARGET = 12.0` и задана
  одинаково во всех трёх конфигурациях сборки (Debug, Release, Profile). Настоящий минимум: 12.0.

## Получение зависимостей {#getting-dependencies}

```bash
cd mobile
flutter pub get
```

Команда разрешает и скачивает пакеты, объявленные в `pubspec.yaml`, в ваш локальный кэш pub и
записывает или обновляет `pubspec.lock` (он уже есть в репозитории; если upstream ничего не
изменилось, `flutter pub get` должен воспроизвести его в точности). Интеграция Firebase/Crashlytics
для Android (`firebase_core`, `firebase_crashlytics`) подключена только для Android. Что она
требует от вас, а что нет, см. в разделе
[Подключение к своему серверу](connect-to-self-hosted.md#google-sign-in-configuration).

## Запуск с локальным бэкендом {#running-against-a-local-backend}

`flutter run` запускает приложение в отладочном режиме на подключённом устройстве или эмуляторе
(их список выводит `flutter devices`). **Прежде чем это делать, прочитайте
[Подключение к своему серверу](connect-to-self-hosted.md)**: URL бэкенда, к которому
обращается отладочная сборка, является константой времени компиляции в `lib/config/api_config.dart`,
и в поставляемом виде он **не** указывает ни на `localhost`, ни на какой-либо бэкенд, который вы,
скорее всего, запускаете сами. Если запустить `flutter run`, не изменив сначала эту константу,
сборка пройдёт успешно, и приложение просто будет работать с чужим бэкендом.

Когда `lib/config/api_config.dart` указывает на ваш сервер:

```bash
flutter run
```

Нажмите `r` для горячей перезагрузки, `R` для горячего перезапуска, `q` для выхода. Если вы меняете
константу URL, когда приложение уже запущено, перезапустите его (`R` или остановка и повторный
запуск), а не полагайтесь на горячую перезагрузку. См. оговорку о константах времени компиляции на
странице по ссылке.

## Тесты и анализ {#tests-and-analysis}

```bash
flutter test                        # run the test suite
flutter analyze --no-fatal-infos    # static analysis (analysis_options.yaml + flutter_lints)
dart format .                       # format all Dart source
```

`mobile/README.md` описывает структуру `test/unit/`, `test/widget/`, `test/integration/`. На
момент написания в реальном дереве `test/` один файл,
`test/screens/deals/deals_list_screen_test.dart`, виджет-тест экрана списка сделок; описанного в
README разделения на три части пока нет. `flutter test` запускает всё, что есть, независимо от
структуры каталогов, так что сама команда верна, даже если описанная структура нет.

`flutter analyze --no-fatal-infos` работает по правилам из `analysis_options.yaml`, который
подключает `package:flutter_lints/flutter.yaml` без добавленных или отключённых правил проекта.
