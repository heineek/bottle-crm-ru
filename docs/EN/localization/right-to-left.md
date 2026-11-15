# Right-to-left languages

Persian, Arabic, Hebrew and Urdu are written right to left. Translating their strings is not
enough: the whole layout mirrors, so the sidebar, back arrows, table columns and padding swap
sides. This page lists what is already in place and what a right-to-left language still needs.

## What is in place {#what-is-in-place}

- **Web.** `hooks.server.js` sets `dir` on `<html>` from `textDirection(locale)` in
  `src/lib/i18n/locale.js`, which knows the right-to-left languages (`ar`, `fa`, `he`, `ur` and a
  few more). The browser then mirrors text alignment, inline flow, flex rows, grid columns and
  scrollbars by itself.
- **Mobile.** `flutter_localizations` sets `Directionality` from the app locale, so `Row`,
  `ListTile`, `AppBar` back buttons and the platform's directional icons mirror by themselves.
- **Formatting.** `Intl` and `intl` give the language's own digits and calendar (`fa`: Persian
  digits and the Solar Hijri calendar) from the locale alone.

## What still needs work {#what-still-needs-work}

Anything written with a physical side (left, right) stays on that side when the page mirrors.
Today the code has no right-to-left language, so these are still physical:

| Where | Roughly | What to change |
|---|---|---|
| `frontend/src/lib/v2/styles/v2.css`, `src/app.css` | 35 declarations | `margin-left` to `margin-inline-start`, `padding-right` to `padding-inline-end`, `left:` to `inset-inline-start:`, `text-align: left` to `start`, `border-left` to `border-inline-start` |
| `<style>` blocks in `frontend/src/**/*.svelte` | 170 declarations | The same CSS logical properties |
| Tailwind classes in `frontend/src` | a handful | `ml-*` / `mr-*` to `ms-*` / `me-*`, `pl-*` / `pr-*` to `ps-*` / `pe-*`, `left-*` / `right-*` to `start-*` / `end-*`, `text-left` to `text-start`, `rounded-l-*` to `rounded-s-*`, `border-l-*` to `border-s-*` |
| `mobile/lib` | about 380 uses | `EdgeInsets.only(left:)` and `fromLTRB` to `EdgeInsetsDirectional.only(start:)` / `fromSTEB`, `Alignment.centerLeft` to `AlignmentDirectional.centerStart`, `Positioned` to `PositionedDirectional`, `TextAlign.left` to `TextAlign.start` |

Do the conversion module by module, in the same pull request as that module's strings, so each
change is small enough to check on screen. A logical property renders exactly like the physical
one in a left-to-right language, so the conversion is safe to land before the translation.

## Things that must not mirror {#things-that-must-not-mirror}

- **Icons that mean a direction** (chevrons, back and forward arrows, "send", progress steps) must
  flip. On the web use Tailwind's `rtl:` variant (`rtl:-scale-x-100`); in Flutter, prefer the
  icons Material already mirrors, or wrap in `Directionality`-aware widgets. Icons that do not
  mean a direction (a phone, a clock, a check mark) must not flip.
- **Values that are left to right by nature**: email addresses, URLs, phone numbers, IBANs, API
  tokens, code and record ids. Give their inputs and cells `dir="ltr"` (Flutter:
  `textDirection: TextDirection.ltr`), and wrap one inside a right-to-left sentence in `<bdi>` so
  punctuation stays where it belongs.
- **Charts and timelines** whose axis is time keep time running in the reading direction of the
  language; check them by eye.
- **Tenant text** in another script (a Latin company name in a Persian page) is isolated with
  `<bdi>` or `dir="auto"` where it sits inside translated text.

## Checking it {#checking-it}

Switch your profile to the language and walk the module at 390px and at desktop width: the
sidebar on the right, back arrows pointing right, numbers in tables aligned to the
end of the cell, no text clipped against the wrong edge. Put a screenshot of each converted module
at 390px in its pull request.
