# BottleCRM: CRM для ИИ и людей

Бесплатная мультитенантная CRM с открытым исходным кодом, которую вы разворачиваете у себя. Построена на Django REST Framework, SvelteKit и Flutter.

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Python](https://img.shields.io/badge/python-3.12+-green.svg)
![Django](https://img.shields.io/badge/django-6.x-green.svg)
![SvelteKit](https://img.shields.io/badge/sveltekit-3.x-orange.svg)
![Svelte](https://img.shields.io/badge/svelte-5-orange.svg)
![Flutter](https://img.shields.io/badge/flutter-3.44+-blue.svg)
![Coverage](./coverage-badge.svg)

**BottleCRM: CRM с открытым кодом, которая работает на вашей инфраструктуре.** Она охватывает весь
цикл работы с клиентом (лиды, компании, контакты, сделки, обращения в поддержку, задачи и
счета) через веб-приложение на SvelteKit, нативное мобильное приложение на Flutter и
документированный REST API, которые работают с одним backend на Django. Row-Level Security в
PostgreSQL изолирует данные каждой организации на уровне базы данных, поэтому одно развёртывание
может обслуживать как один стартап, так и сотни тенантов.

Никакой оплаты за место, никаких лимитов на пользователей, никаких платных функций. Лицензия MIT:
форкайте, разворачивайте у себя, владейте своими данными.

**[Попробовать бесплатно →](https://bottlecrm.io/)** · [Возможности](https://bottlecrm.io/features) · [Документация продукта](https://bottlecrm.io/docs) · [Цены](https://bottlecrm.io/pricing) · [Переезд с Salesforce или HubSpot](https://bottlecrm.io/migration)

(Это документация продукта на маркетинговом сайте, на английском. Техническая документация (развёртывание, архитектура, API, участие в разработке) описана ниже в разделе [Документация](#документация).)

## Почему BottleCRM

- **Бесплатно навсегда, лицензия MIT**: неограниченное число пользователей и записей, без
  подписки. Настоящая альтернатива Salesforce, HubSpot и Pipedrive, которую вы размещаете сами.
- **Мультитенантность заложена в архитектуру**: Row-Level Security в PostgreSQL обеспечивает
  изоляцию тенантов в базе данных, а не только в коде приложения. Используйте для одной
  компании или как SaaS для многих.
- **REST API, готовый для агентов**: подключите Claude, Cursor, Codex, Gemini или любого другого
  агента к API с персональным токеном доступа, и он будет искать, создавать и изменять записи
  *от вашего имени*, с вашей ролью, организацией и правами. В комплекте есть схема OpenAPI, так
  что агент сам найдёт нужные эндпоинты.
- **Веб, нативное мобильное приложение и API**: один REST backend на Django, веб-приложение на
  Svelte 5 и приложение на Flutter для iOS и Android.
- **Стек, который действительно можно дорабатывать**: Django 6 / DRF и Svelte 5, а не
  самописный фреймворк. Если ваша команда пишет на Python, она сможет расширять систему с первого
  дня.
- **Полноценные инструменты поддержки**: настоящий helpdesk с таймерами SLA, согласованиями,
  эскалациями, макросами и базой знаний, а не прикрученный сбоку список обращений.

## Сравнение

| | BottleCRM | SaaS CRM (Salesforce, HubSpot) | Типичная CRM с открытым кодом |
|---|---|---|---|
| **Стоимость** | Бесплатно, без лимита пользователей | За место в месяц | Бесплатное ядро, часто платные тарифы |
| **Размещение** | У себя (есть управляемый хостинг) | Только облако поставщика | У себя |
| **Владение данными** | Полное. Это ваша база данных | Под контролем поставщика | Полное |
| **Мультитенантность** | RLS на уровне базы данных | Неприменимо | Редко |
| **Нативное мобильное приложение** | Да, Flutter, iOS и Android | Да | Редко |
| **Доступ для ИИ-агентов** | Полный REST API, токены у каждого пользователя | Закрытые дополнения | Редко |
| **Стек** | Django REST и SvelteKit | Закрытый код | По-разному |
| **Лицензия** | MIT | Проприетарная | По-разному, часто GPL/AGPL |

## Быстрый старт

```bash
git clone https://github.com/django-crm/Django-CRM.git
cd Django-CRM
docker compose up --build
```

Frontend откроется на http://localhost:5181, API и Swagger UI на http://localhost:8000/swagger-ui/.
Учётные данные администратора по умолчанию, загрузка демо-данных и назначение каждого сервиса
описаны в [руководстве по быстрому старту с Docker](docs/RU/getting-started/docker-quick-start.md).

## Развёртывание в один клик

[![Deploy on RepoCloud](https://d16t0pc4846x52.cloudfront.net/deploylobe.svg)](https://repocloud.io/details/BottleCRM/)

## Документация

Полная документация (настройка, развёртывание, архитектура, REST API и участие в разработке)
лежит в папке [`docs/RU/`](docs/RU/) этого репозитория. Это перевод английского оригинала из
[`docs/EN/`](docs/EN/), который собирается MkDocs Material и публикуется на Read the Docs по адресу
<https://django-crm.readthedocs.io/en/latest/>. С чего начать:

- **[Начало работы](docs/RU/getting-started/docker-quick-start.md)**: установка через Docker и вручную, первый вход, демо-данные.
- **[Развёртывание на своём сервере](docs/RU/self-hosting/requirements.md)**: требования, развёртывание в продакшене, PostgreSQL и Row-Level Security, резервные копии, усиление безопасности.
- **[Справочник API](docs/RU/api/conventions.md)**: аутентификация, соглашения и все документированные эндпоинты.
- **[Участие в разработке](docs/RU/contributing/development-setup.md)**: локальное окружение, тестирование, стиль кода и как открыть pull request.

## Участие в разработке

Мы рады вашему вкладу! Настройка окружения, проверки и правила оформления pull request описаны в [CONTRIBUTING_RU.md](CONTRIBUTING_RU.md).

## Сообщество

- **Задачи**: [GitHub Issues](https://github.com/django-crm/Django-CRM/issues)
- **Коммерческая поддержка**: [Связаться с нами](https://bottlecrm.io/contact)
- **LinkedIn**: [BottleCRM в LinkedIn](https://www.linkedin.com/company/bottle-crm)

## Лицензия

Проект распространяется по лицензии MIT, подробности в файле [LICENSE](LICENSE).

## Спонсоры

BottleCRM разрабатывает и поддерживает [RunCode Inc.](https://runcode.io)

Мы будем рады новым спонсорам. Если вы хотите поддержать BottleCRM и помочь проекту расти, пожалуйста, [напишите нам](https://bottlecrm.io/contact).

## Участники

Проект существует благодаря всем, кто в него внёс вклад.

[Все участники BottleCRM](https://github.com/django-crm/Django-CRM/graphs/contributors).
