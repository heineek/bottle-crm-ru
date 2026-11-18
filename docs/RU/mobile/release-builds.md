# Релизные сборки

Эта страница описывает, как получить устанавливаемый артефакт для Android/iOS, и какая
конфигурация подписи уже есть в репозитории, а какую нужно создать самостоятельно. Предполагается,
что вы уже направили приложение на свой сервер: см.
[Подключение к своему серверу](connect-to-self-hosted.md), поскольку релизная сборка, как и
отладочная, встраивает то, что указано в `lib/config/api_config.dart` на момент сборки.

Обе платформы берут идентификатор и версию приложения из нескольких общих источников:
`applicationId` `io.bottlecrm` (Android, `android/app/build.gradle.kts`) и bundle identifier
`io.bottlecrm` (iOS, `ios/Runner.xcodeproj/project.pbxproj`) совпадают на обеих платформах;
`version: 1.2.0+11` из `pubspec.yaml` задаёт и имя сборки (`1.2.0`), и номер сборки (`11`) через
`flutter.versionName`/`flutter.versionCode` на Android и `$(FLUTTER_BUILD_NAME)`/
`$(FLUTTER_BUILD_NUMBER)` на iOS. `io.bottlecrm` является собственным идентификатором BottleCRM.
Это также ID пакета собственной страницы BottleCRM в Play Store, на которую ссылается
`mobile/README.md`. Если вы распространяете свою сборку через собственную страницу в Play Console
или App Store Connect, здесь нужен ваш собственный идентификатор, а это влечёт последствия для
регистрации клиентов входа через Google, описанной в разделе
[Подключение к своему серверу](connect-to-self-hosted.md#google-sign-in-configuration)
(OAuth-клиент Android и `package_name` в `google-services.json` оба привязаны к тому
`applicationId`, с которым вы выпускаете приложение). Для APK, который вы собираете и
устанавливаете вручную, менять его не обязательно.

## Android {#android}

```bash
flutter build apk --release        # single APK, build/app/outputs/flutter-apk/app-release.apk
flutter build appbundle --release  # Play Store .aab, build/app/outputs/bundle/release/
```

Реальные минимальный, целевой и компиляционный уровни SDK из `android/app/build.gradle.kts`:

- `minSdk = 28` (Android 9). Задано прямо в этом файле с комментарием `// Android 9 (API 28)`.
  «Android: API level 31+ (Android 12+)» в `mobile/README.md` и
  `flutter_launcher_icons.min_sdk_android: 31` в `pubspec.yaml` (который управляет только тем,
  генерирует ли этот инструмент адаптивные иконки, а не минимальной версией самого приложения)
  говорят не то, что реальная конфигурация Gradle. Сборка требует именно 28.
- `compileSdk = flutter.compileSdkVersion`, `targetSdk = flutter.targetSdkVersion`. Оба значения
  берутся из умолчаний установленного у вас Flutter SDK, а не из числа, зафиксированного в проекте.

Сборке также нужны `ndkVersion = "28.2.13676358"` (зафиксировано в том же файле, «Bumped to
satisfy jni plugin requirement») и инструментарий, совместимый с JDK 17 (`compileOptions` и блок
`kotlin { compilerOptions { jvmTarget } }` оба нацелены на Java/Kotlin 17). Остальные требования к
локальному окружению см. в разделе [Сборка и настройка](build-and-configure.md#prerequisites).

`android/app/build.gradle.kts` безусловно применяет Gradle-плагины
`com.google.gms.google-services` и `com.google.firebase.crashlytics` (версии classpath
зафиксированы в `android/build.gradle.kts`: `com.google.gms:google-services:4.5.0`,
`com.google.firebase:firebase-crashlytics-gradle:3.0.7`). Задокументированное поведение плагина
google-services: сразу ронять сборку, если `android/app/google-services.json` отсутствует. Этот
репозиторий содержит только `android/app/google-services.json.template`. Настоящий файл в
gitignore (`**/google-services.json` в `mobile/.gitignore`) и в свежем клоне отсутствует. Чтобы
`flutter build apk` или `flutter build appbundle` прошли этот плагин, нужен собственный
`google-services.json` из проекта Firebase/Google Cloud. Для чего этот файл нужен помимо
прохождения сборки, см. в разделе
[Подключение к своему серверу](connect-to-self-hosted.md#google-sign-in-configuration).

## iOS {#ios}

Только macOS и Xcode.

```bash
flutter build ios --release              # produces build/ios/iphoneos/Runner.app; needs code signing
flutter build ios --release --no-codesign  # same, skipping signing (e.g. building without a team configured yet)
```

Чтобы получить архив, готовый к загрузке в App Store Connect, используйте
`flutter build ipa --release`: это управляемый Flutter аналог `appbundle` для iOS (он запускает
`xcodebuild -archive` и шаг экспорта, и для успеха ему нужна корректная подпись, см. ниже).

Реальная целевая версия развёртывания: `IPHONEOS_DEPLOYMENT_TARGET = 12.0`, заданная одинаково во
всех трёх конфигурациях сборки в `ios/Runner.xcodeproj/project.pbxproj` (Debug, Release, Profile);
«iOS: iOS 11.0+» в `mobile/README.md` не совпадает с файлом проекта.

Firebase/Crashlytics в этом коде намеренно не подключён для iOS (`main.dart` пропускает
`Firebase.initializeApp` вне `TargetPlatform.android` с комментарием о том, что
`GoogleService-Info.plist` для iOS пока нет), поэтому аналога барьера плагина google-services из
Android, блокирующего сборку iOS, нет: обычный `flutter build ios --release --no-codesign` пройдёт
без какой-либо конфигурации Firebase. Подпись кода является отдельным вопросом, о нём дальше.

## Подпись {#signing}

**Android.** `android/app/build.gradle.kts` загружает файл `key.properties` из корня Android-проекта,
если он существует:

```kotlin
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
```

Он читает из этого файла четыре свойства (`keyAlias`, `keyPassword`, `storeFile`,
`storePassword`), чтобы построить конфигурацию подписи `release`, и применяет её к типу сборки
`release`. **`key.properties` в этом репозитории нет**. Он указан в `android/.gitignore`, и в
отличие от `google-services.json` закоммиченной заготовки для него нет. Важно посмотреть, что
происходит с типом сборки `release`, когда файла нет:

```kotlin
buildTypes {
    release {
        signingConfig = if (keystorePropertiesFile.exists())
            signingConfigs.getByName("release")
        else
            signingConfigs.getByName("debug")
    }
    ...
}
```

**На свежем клоне без созданного `key.properties` команды `flutter build apk --release` и
`flutter build appbundle --release` откатываются на встроенную конфигурацию подписи `debug` из
Android Gradle Plugin**, а не на ключ, который предоставляет Flutter, и не на ключ, общий для всех
установок. Эта конфигурация опирается на `debug.keystore`, который инструменты Android SDK сами
генерируют на каждой машине при первой необходимости (обычно в `~/.android/debug.keystore`, с
фиксированной парой псевдоним/пароль `androiddebugkey`/`android`): Flutter никак в этом не
участвует, кроме вызова Gradle, и две разные машины сгенерируют два разных отладочных хранилища
ключей. У этого есть конкретное последствие помимо «это не настоящий релизный ключ»: сборка,
подписанная отладочным ключом на вашем ноутбуке, и сборка с вашей CI-машины имеют разные подписи,
а Android считает по-разному подписанные сборки несвязанными приложениями с точки зрения
обновлений. Одна не сможет незаметно обновить установку, пришедшую из другой или из сборки,
подписанной позже настоящим ключом загрузки. Это нормально для сборки, которую вы один раз
устанавливаете вручную и не собираетесь обновлять; но такую сборку не стоит распространять
публично, поскольку кто угодно может так же воспроизвести «подписанное» обновление с отладочным
хранилищем ключей своей машины. Прежде чем релизная сборка уйдёт дальше вашего собственного
устройства, сгенерируйте собственное хранилище ключей. Стандартный вызов `keytool`:

```bash
keytool -genkey -v -keystore <path-to-keystore>.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias <your-key-alias>
```

Затем создайте `android/key.properties` (никогда не коммитьте его) со значениями `storeFile`,
`storePassword`, `keyAlias`, `keyPassword`, указывающими на это хранилище.

Ещё одно следствие того же условия, о котором стоит знать, касается типа сборки *debug*:

```kotlin
debug {
    if (keystorePropertiesFile.exists()) {
        signingConfig = signingConfigs.getByName("release")
    }
}
```

Если `key.properties` существует, **отладочные сборки тоже подписываются вашим релизным ключом**, а
не локальным отладочным хранилищем ключей Android Gradle Plugin, описанным выше. Комментарий в
коде объясняет почему: чтобы отладочная сборка, установленная для локального тестирования, имела
тот же отпечаток SHA-1, что вы зарегистрировали для входа через Google (см.
[Подключение к своему серверу → Настройка входа через Google](connect-to-self-hosted.md#google-sign-in-configuration)),
и не нужен был второй, отдельный OAuth-клиент Android только для отладочных установок.

**iOS.** `ios/Runner.xcodeproj/project.pbxproj` задаёт
`CODE_SIGN_IDENTITY[sdk=iphoneos*] = "iPhone Developer"` для сборок под устройство на уровне
проекта, и это наследуют обе цели. `CODE_SIGN_STYLE = Automatic` тоже встречается в файле, но
только в трёх конфигурациях сборки цели **`RunnerTests`**. Цель приложения `Runner` и уровень
проекта вообще не задают `CODE_SIGN_STYLE`, и блок `TargetAttributes` проекта тоже не задаёт
`ProvisioningStyle` ни для одной из целей. Что неизменно во всём файле: ключа `DEVELOPMENT_TEAM`
в нём нет нигде (проверено напрямую; его просто нет), поэтому, какой бы стиль подписи ни показал
Xcode при первом открытии проекта, вам нужно открыть `ios/Runner.xcworkspace` в Xcode, выбрать
вкладку Signing & Capabilities цели Runner и выбрать свою команду Apple Developer, прежде чем
`flutter build ios` (без `--no-codesign`) или `flutter build ipa` завершатся успешно. Создавать
вручную файл, аналогичный хранилищу ключей, здесь не нужно: после выбора команды Xcode сам
управляет профилями подготовки (provisioning profiles).
