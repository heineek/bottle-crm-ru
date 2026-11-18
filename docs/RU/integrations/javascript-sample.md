# Пример на JavaScript

## Что делает пример {#what-this-does}

Тот же сценарий, что и в [примере на Python](python-sample.md), но на JavaScript: получить токен
доступа, вывести список лидов организации и создать лид, используя только встроенный `fetch`, без
зависимостей из npm. Пример написан для Node (проверен на совместимость с Node 24), но сами вызовы
`fetch` без изменений выполнятся в консоли любого современного браузера, если бэкенд разрешает CORS.

Как и в примере на Python, «получить токен» означает прочитать персональный токен доступа
(`bcrm_pat_…`) из окружения, а не проходить интерактивный вход. Что именно аутентифицирует PAT,
описано в разделе [Токены и API-ключи](../api/tokens-and-api-keys.md#personal-access-tokens), а как
создать его локально, показано в [примере на Python](python-sample.md#what-this-does).

## Скрипт {#the-script}

```javascript
#!/usr/bin/env node
// List an org's leads and create one, using a BottleCRM personal access token.
//
// Usage:
//   BCRM_BASE_URL=http://localhost:8000 BCRM_TOKEN=bcrm_pat_... node leads-sample.mjs
//
// Requires Node 18+ for the built-in `fetch`. The flag history, precisely:
// --experimental-fetch was a Node 17.5 flag; Node 18 made fetch available
// with no flag at all (still labeled experimental, with a startup warning);
// Node 21 dropped that warning and made fetch stable. Tested for Node 24.
// No npm dependencies.
//
// See docs/api/tokens-and-api-keys.md for how to mint BCRM_TOKEN, and
// docs/api/leads.md for the shape of the /api/leads/ responses this reads.

const BASE_URL = (process.env.BCRM_BASE_URL || "http://localhost:8000").replace(/\/$/, "");
const TOKEN = process.env.BCRM_TOKEN;

if (!TOKEN) {
  console.error(
    "Set BCRM_TOKEN to a bcrm_pat_... personal access token " +
      "(see docs/api/tokens-and-api-keys.md)."
  );
  process.exit(1);
}

const headers = {
  Authorization: `Bearer ${TOKEN}`,
  Accept: "application/json",
  "Content-Type": "application/json",
};

// GET /api/leads/, the response splits leads into open/closed sections
// rather than one flat list; see docs/api/leads.md#list-leads.
async function listLeads() {
  const res = await fetch(`${BASE_URL}/api/leads/`, { headers });
  const data = await res.json();
  if (!res.ok) {
    throw new Error(`List failed (${res.status}): ${JSON.stringify(data)}`);
  }
  const openSection = data.open_leads;
  const leads = openSection.open_leads;
  console.log(
    `${leads.length} open lead(s) on this page (of ${openSection.leads_count} total open):`
  );
  for (const lead of leads) {
    const name = `${lead.first_name ?? ""} ${lead.last_name ?? ""}`.trim();
    console.log(
      `  - ${name || "(no name)"} <${lead.email ?? "no email"}> [${lead.status}]`
    );
  }
  return data;
}

// POST /api/leads/. A 200 with {"error": false, ...} is success; the
// response does not echo the created record, so we look it up afterward.
async function createLead() {
  const email = `sample.lead+${Date.now()}@example.com`;
  const res = await fetch(`${BASE_URL}/api/leads/`, {
    method: "POST",
    headers,
    body: JSON.stringify({
      first_name: "Sample",
      last_name: "Lead",
      email,
      status: "assigned",
      source: "other",
    }),
  });
  const body = await res.json();
  if (!res.ok || body.error) {
    throw new Error(`Create failed (${res.status}): ${JSON.stringify(body)}`);
  }
  console.log(`Create response: ${JSON.stringify(body)}`);
  return email;
}

// GET /api/leads/?email=...; `email` is a case-insensitive contains filter
// (docs/api/conventions.md#filtering-and-search), fine here since the address
// we just created is unique in this org.
async function findByEmail(email) {
  const url = new URL(`${BASE_URL}/api/leads/`);
  url.searchParams.set("email", email);
  const res = await fetch(url, { headers });
  const data = await res.json();
  if (!res.ok) {
    throw new Error(`Lookup failed (${res.status}): ${JSON.stringify(data)}`);
  }
  const matches = data.open_leads.open_leads;
  if (matches.length) {
    console.log(`Found the new lead: id=${matches[0].id}`);
  } else {
    console.log("New lead not on this page (increase limit/offset to find it).");
  }
}

async function main() {
  console.log("Listing existing leads...");
  await listLeads();
  console.log("\nCreating a lead...");
  const email = await createLead();
  console.log("\nConfirming it was created...");
  await findByEmail(email);
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
```

## Запуск {#running-it}

Сохраните скрипт как `leads-sample.mjs`. В нём нет `import`/`export` и нет `await` верхнего уровня
(все вызовы `await` находятся внутри `async function main()`, которая вызывается с `.catch()`, а не
ожидается на верхнем уровне), поэтому он работает одинаково, считает ли Node файл модулем CommonJS
или ES. Расширение `.mjs` просто снимает любую неоднозначность, которую мог бы внести `package.json`
в том же каталоге. Вам нужен доступный бэкенд BottleCRM и персональный токен доступа, созданный так,
как описано в [примере на Python](python-sample.md#what-this-does):

```bash
BCRM_BASE_URL=http://localhost:8000 \
BCRM_TOKEN=bcrm_pat_... \
  node leads-sample.mjs
```

**О проверке:** как и пример на Python, этот скрипт проверен статически: каждый URL и каждое поле
сверены с разделами [Лиды](../api/leads.md) и [Соглашения](../api/conventions.md), а весь файл
проверен командой `node --check`. На живой базе данных он не запускался, чтобы не записывать строку
в общий экземпляр, который эта документация не создавала. Пример вывода иллюстративный, а не снятый с
реального запуска, и по форме совпадает с выводом [примера на Python](python-sample.md#running-it),
поскольку оба вызывают одни и те же эндпоинты:

```text
Listing existing leads...
3 open lead(s) on this page (of 3 total open):
  - Jordan Blake <jordan.blake@example.com> [assigned]
  - Priya Shah <priya.shah@example.com> [in process]
  - (no name) <no email> [assigned]

Creating a lead...
Create response: {"error":false,"message":"Lead Created Successfully"}

Confirming it was created...
Found the new lead: id=3f2a1c9e-....
```

Ошибка валидации возвращается как `400`, и скрипт выбрасывает исключение с телом ошибки, которое
вернул BottleCRM, согласно разделу [Ошибки](../api/errors.md#validation-errors):

```text
Create failed (400): {"error":true,"errors":{"email":["Another lead in this organisation already uses that email address."]}}
```
