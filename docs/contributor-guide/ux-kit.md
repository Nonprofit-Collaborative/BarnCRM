# UX Kit

A few small Core components that every BarnCRM screen, Core and modules alike, is built from, so the screens look and behave alike. They live in `packages/core/main/default/lwc/` with the `barn` prefix and are placed inside other components. Each is `isExposed` with no targets: that keeps them out of App Builder but lets any package that depends on Core nest or import them once the packages are split (`scripts/ci/check-namespace-readiness.py`), and the kit's labels are unprotected for the same reason. Never copy a kit part into a module; use it. The plan behind them is decision D-140 in the product plan, extended to every screen for v1.0 (owner approval 2026-11-04); the [Visual Standard](#visual-standard) below is the rule set.

Rules for any screen:

- Show the task, hide the manual. No visible paragraph over 25 words on an admin screen; longer help goes in a popover, the About This Tool region, or the admin guide.
- Title Case for every title, heading, tab, tile and button; sentence case for body text and field labels.
- One card level. Never a card inside a card.
- No hard-coded colors or sizes. CSS uses SLDS 2 styling hooks (`--slds-g-*`) with a fallback, and `npm run lint:slds` must report no violations.
- Every UI string and message comes from a custom label; every help and guidance sentence comes from the package's help catalog (see Help Text below). Never add help prose as a label.

## Help Text

Help and guidance prose (an intro, a description, an explanation, an empty-state explanation, a setup note, a tooltip longer than a short phrase) lives in the package's JSON help catalog, not in custom labels (ADR-0164 `0164-help-text-json.md`). Custom labels of an unmanaged or source install count toward the org's 5,000, and BarnCRM installs that way for a long time.

- **Where:** `packages/<dir>/main/default/staticresources/BarnHelp_<Package>.json` (`BarnHelp_Core`, `BarnHelp_Rollups`, `BarnHelp_Giving`, `BarnHelp_Volunteers`, `BarnHelp_Programs`, `BarnHelp_LogicModels`, `BarnHelp_Funders`, `BarnHelp_Mirror`), shaped `{ "languages": ["en"], "texts": { "<key>": "<text>" } }`. A package's first help text adds its catalog and a `.resource-meta.xml` copied from Core's. English only for now.
- **Keys:** named like labels, `<Package>_<Area>_<What>` (`Core_OrgOptimizer_Intro`). Keep the keys sorted.
- **Messages too (D-172):** every error, toast, confirmation, validation message, notice, log line and run result, and any sentence with `{0}` about the current state, goes into the catalog the same way. Read it in a getter or handler with `helpText`, or in Apex with `BarnHelp.text` (an exception thrown from a trigger reads it like any other).
- **What stays a label:** titles, buttons, tabs, column headers, field labels, short status words, text written into emails, notifications and files, and anything named from FlexiPage, Flow or custom metadata (a Flow's error message, for one).
- **In a component:**

  ```js
  import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

  export default class Example extends LightningElement {
    helpReady = isHelpLoaded('Core');

    connectedCallback() {
      if (!this.helpReady) {
        loadHelp('Core').then(() => {
          this.helpReady = true;
        });
      }
    }

    get intro() {
      return helpText('Core', 'Core_Example_Intro');
    }
  }
  ```

  Wrap the template in `<template lwc:if={helpReady}>` so the first render has the text, and read help only in getters and handlers, never in a class field or module constant (those are read before the catalog arrives). Pass an array to `loadHelp` and `isHelpLoaded` when a component shows another package's help (its own package's and Core's only). `helpText(pkg, key, a, b)` fills `{0}` and `{1}`.
- **A popover:** `<c-barn-help help-package="Core" help-key="Core_Example_Help"></c-barn-help>`.
- **In Apex** (only where Apex returns help to the UI): `BarnHelp.text('Core', 'Core_Example_Help')`, or `BarnHelp.text('Core', 'Core_Example_Count', new List<Object>{ n })`.
- **Keys are literals.** Write the package and key as quoted strings so `scripts/ci/check-help-text.py`, and a reader, can find them; it fails on a missing, unused or non-literal key, an em or en dash, and a key that is also a label.
- **Jest:** `c/barnHelpText` is mapped to a stand-in that is always loaded and reads a key as `c.<key>`, like the label stub. For real wording, `import { setHelpTextForTest } from 'c/barnHelpText'` and set `{ key: 'text' }`.
- **Accessibility:** help keeps its element: a paragraph stays a paragraph, and an `aria-describedby` still points at it. Only where the words come from changes.

## Part 1 Components

| Component | Use it for | Main properties |
|---|---|---|
| `c-barn-page-shell` | The page of an admin tool: one header, About This Tool help, body, footer | `icon-name`, `title`, `purpose`, `title-hidden`, `help-label`, `help-storage-key`, `status-message`; slots `actions`, `help`, `footer` and the default body |
| `c-barn-tool-grid` | A hub of tools in groups (Data Manager, the Org Optimizer overview, Home) | `groups` (each with `name`, `label`, `tiles`), `heading-level`; fires `select` with `detail.name` |
| `c-barn-tool-tile` | One tool on a hub; the whole tile is one link or button | `name`, `label`, `description`, `icon-name`, `href`, `new-tab`, `badge-label`, `badge-variant`, `disabled`, `disabled-reason`; fires `select` |
| `c-barn-empty-state` | Any "nothing here yet" | `illustration` (`no-data`, `setup`, `all-clear`), `heading`, `message`, `size` (`small`, `large`, `compact`), `heading-level`; default slot for the action |
| `c-barn-help` | Help next to a field or section | `help-key` and `help-package` (popover text from the help catalog) or `content` (popover text given), `learn-more-url`, `learn-more-label`, `alternative-text` |

Notes:

- On a Lightning App Page the platform already prints the page name above the component. Pass `title-hidden` to the shell so the name is not printed twice; the `h1` stays for screen readers.
- The About This Tool region opens on a person's first visit and stays closed after that. With `help-storage-key` the person's own choice is remembered in their browser only; it is a convenience, not a setting.
- A disabled tile stays focusable so a screen reader reads why it is disabled.
- Every link that opens a new tab goes through `c-barn-help` or copies its pattern: `rel="noopener noreferrer"`, the new-window icon, and "(opens in a new tab)" for screen readers. A link tile does this with `new-tab` (a grid tile with `newTab: true`), as Data Manager's Salesforce's Own Tools do.
- A hub page that must open without running anything (Org Optimizer) badges a tile only from what is cheap or already known, and lets a section report its own result with a `summary` event once it has been opened.
- A component placed inside the shell drops its own `lightning-card` and opens with an `h2` and its actions, unless it is also exposed for Home or record pages, where it keeps its card.

## Part 2 Components

| Component | Use it for | Main properties |
|---|---|---|
| `c-barn-step-flow` | A wizard: the SLDS path, the step body, and one footer with Back left and the step's actions right (Import, Super Transformer, Bulk Delete) | `steps` (each `value`, `label`), `current-step`, `can-go-back`; slot `actions` and the default body; fires `back` |
| `c-barn-visual-picker` | One choice from a few as icon cards (Import's What Are You Importing?, the first-run edition) | `label` (the legend), `options` (each `value`, `label`, `description`, `iconName`, `warning`), `value`; fires `change` with `detail.value` |
| `c-barn-stat-tile` | One figure as a big value over a label (import preview and results, Org Optimizer counts, pipeline totals, dashboards) | `label`, `value` (a number is formatted; text is shown as given), `format-style` (`decimal`, `currency`, `percent`; percent takes a fraction, 0.25 is 25%), `currency-code`, `icon-name`, `badge-label`, `badge-variant` (a status word, drawn by `c-barn-status-badge`), `align` (`center` default, `start`), `bordered`, `href` (the tile is one link), `clickable` with `name` (the tile is one button; fires `select` with `detail.name`) |
| `c-barn-save-bar` | The save footer of a settings form, docked to the bottom while anything is unsaved | `dirty-count`, `saving`; fires `save` and `discard` |
| `c-barn-confirm-modal` | A yes or no question in a platform modal; open it with `BarnConfirmModal.open({...})` | `label`, `message`, `details`, `confirmLabel`, `cancelLabel`, `confirmVariant` (`destructive` for a red button), `typeToConfirm` and `typeToConfirmLabel` for a large or lasting change; `items` (a bulleted list of names), `choices` with `choicesLabel` and `choice` (a radio group), `checks` with `checksLabel` (tick boxes, none ticked) |

Notes:

- The step flow's path names each step, so the screen drops its own step heading; the flow keeps an `h2` ("Step 2 of 6: Upload File") for screen readers. Step labels are Title Case and short.
- The visual picker is a native radio group, so the arrow keys change the choice. Keep the picker on screen after a choice and show what follows from it below; never move to another screen on `change`.
- The save bar asks before the browser tab closes or reloads while anything is unsaved. It cannot stop a move to another Lightning tab.
- The confirm modal resolves `true` when confirmed. With `choices` or `checks` it resolves `{ choice, checked }` instead (the chosen value and the ticked values), so a caller that passes neither keeps its plain `true`. Each `choices` and `checks` entry is `{ label, value }`.
- Use `typeToConfirm` (for example the record count) only for deletes and other changes that are hard to undo; the confirm button stays disabled until the text matches.

## Part 3 Screens that follow the kit

| Screen | How it follows the kit |
|---|---|
| Data Jobs (`dataJobHistory`) | Each job row shows its status as a `lightning-badge` (green when done, amber while it runs, red when it failed) and keeps the job's actions, Undo for now, in a small row menu (`lightning-button-menu`) instead of a button on every row. The undo confirmations still open in place above the list. |
| Org Optimizer storage (`optimizerStorage`) | Each limit is a `c-barn-meter` (name, bar, "N of N (N%)"), with a warning `c-barn-status-badge` for Near Limit. |
| Home Quick Links (`hubQuickLinks`) | Each tile's icon comes from `c/barnIcons`, so it matches its tab. |
| Find export files (`findExportFiles`) | A refused export shows an error `c-barn-notice`. |

Each component has Jest tests written as stories (one case per variant a screen uses). Add a story when you add a variant.

## Part 4 Components (v1.0)

| Component | Use it for | Main properties |
|---|---|---|
| `c-barn-status-badge` | Any status in a list, tile or record panel | `status` (a word from the vocabulary below), `label` (the text), `icon-name` (replaces the tone's icon, for example `utility:favorite` for Primary), `hide-icon` |
| `c-barn-notice` | Any message inside a panel: a result, a refusal, a caution, a neutral note | `variant` (`info` default, `success`, `warning`, `error`), `title`, `message`, `action-label` with `action-href` (a link) or without it (a button that fires `action`), `alternative-text`; default slot for richer content |
| `c-barn-meter` | A share or progress: steps done, attendance rate, received against awarded, a funding mix row | `label`, `value`, `max` (100 by default), `value-text` (for example "3 of 5"; the percent when empty), `size` |
| `c/barnStatus` (module) | The status vocabulary, for code that needs the tone without the badge | `statusFor(word)` returns `{ tone, themeClass, iconName }`; `TONES`, `ALIASES` |
| `c/barnIcons` (module) | The icon for a tab or object | `iconFor(apiName, fallback)`; `ICONS` |

The two modules are framework free (no `lightning/*` or `@salesforce/*` imports), so they port to BarnCRM for WordPress (plan 9.9). `c-barn-empty-state` also takes `size="compact"` (below).

## Text and Date Helpers

| Module | Use it for | Main exports |
|---|---|---|
| `c/barnFormat` | Filling a label's `{0}`, `{1}` placeholders, and a local date as `YYYY-MM-DD` (the form a date input and Apex take) | `format(template, ...values)` (a placeholder with no value given stays; a null value reads as empty), `isoDate(date = new Date())` |

Framework free (plan 9.9, UTIL-01). A module that offered its own copy re-exports this one (`import { format } from 'c/barnFormat'; export { format };`) so its callers and tests are unchanged; write no new copy.

## Drag and Drop

| Module | Use it for | Main exports |
|---|---|---|
| `c/barnDrag` | Moving an item between board columns, reordering a list, or dropping one part onto another (Grant Pipeline, Logic Model builder, Cohort Members, Eligibility Rules, import and Super Transformer steps) | `createDragController(options)` returning `pointerDown(event)`, `keyDown(event)`, `cancel()`, `state`, `destroy()`; list helpers `moveItem(list, from, to)` (a copy with one item moved; use it in `onDrop` with `toIndex`) and `targetIndex(index, delta, length)` (where Move Up or Move Down goes, -1 at an end) |
| `c/barnDragText` | The words the controller announces, from the Core help catalog | `dragMessages()`, `dragInstructions()` |

`c/barnDrag` is framework free (plan 9.9). Rules:

- Drag and drop is always an addition. The screen keeps its Move Up and Move Down buttons, card menu or form; on a phone, where columns stack, the menu stays the main way.
- Markup: a drop zone is any element with `data-drop-zone` (its id) and `data-drop-label` (its name); an item inside it has `data-drag-id`, `data-drag-label`, `tabindex="0"`, `aria-describedby` pointing at a hidden element holding `dragInstructions()`, and `onpointerdown` and `onkeydown` handlers that call the controller. A zone can itself sit inside another zone (a part inside a column): the innermost zone under the pointer wins.
- Options: `root` (the component's `this.template`), `layout` (`columns` when zones sit side by side, Left and Right change column; `list` for one list), `messages` (`dragMessages()`, after `loadHelp([<your package>, 'Core'])`), `announce(text)` (write it to the component's own `aria-live="polite"` region), `onChange(state)` (render the source and target highlight from `state.itemId`, `overZone` and `overIndex`), `onDrop({ itemId, fromZone, fromIndex, toZone, toIndex })` (apply the move; return `false` or reject to snap back, and show the reason the same way the existing control does), and optional `canDrop(itemId, fromZone, toZone)`.
- Pointer: a mouse or pen drag starts after a few pixels of movement; touch starts after a 250 ms press and hold, so a swipe still scrolls. The click that ends a drag does not open the card under it. Uses pointer events, never HTML5 `draggable` (it does not fire on iOS Safari).
- Keyboard: Space on the item picks it up, the arrow keys move it, Space or Enter drops, Escape or Tab cancels. Space on a button or link inside the item keeps its own job. Focus returns to the moved item after the drop.
- Call `destroy()` in `disconnectedCallback`.
- A list whose rows hold inputs (import and Super Transformer steps, `importColumnTransforms`) puts `data-drag-id` and the handlers on a small handle `span` (`role="button"`, `tabindex="0"`, `aria-label` the item's name) rather than on the row, so typing and clicking in the row are untouched. Its Move Up and Move Down buttons announce through the same region with `Core_Drag_Position`.
- Never for a destructive or single-choice action (a delete, a merge, a setting).

## Visual Standard

One part per job. A reviewer checks a screen against this list, not against taste.

### Status: one vocabulary, color and icon

| Tone | Words | Look |
|---|---|---|
| success | success, on, active, done, complete, current, passed, met, achieved, approved | green badge, `utility:success` |
| warning | warning, attention, needs attention, due, due soon, expiring, review, pending | amber badge, `utility:warning` |
| error | error, failed, overdue, expired, not met, rejected, blocked | red badge, `utility:error` |
| running | running, in progress, queued | amber badge, `utility:clock` |
| info | info, new | default badge, `utility:info` |
| neutral | neutral, off, inactive, skipped, former, not run, closed, draft, anything unknown | default badge, no icon |

- Do: `<c-barn-status-badge status="overdue" label={labels.overdue}>`. Pass the record's own status word when it is in the list; otherwise map it to a tone in the component.
- Do: a problem state is never the quietest badge. Expired or not met is error; due soon is warning.
- Don't: `lightning-badge` with a hand-picked `slds-theme_*`, a raw `span.slds-badge`, `slds-badge_lightest`, `slds-badge_inverse` (black), or `slds-theme_shade` on a badge.

### Messages: `c-barn-notice`

- Do: info for neutral notes (read only, "other tools"), success for a finished action, warning for something to check, error for a refusal. Errors are announced (`role="alert"`), the rest politely (`role="status"`).
- Do: put a link to the result in `action-label` and `action-href` ("Open Gift"); it takes the notice's text color and an underline, so it passes contrast on every variant.
- Don't: a solid `slds-box slds-theme_error|warning|success` block, a bare `slds-text-color_error` paragraph for a refusal, or `slds-notify_alert` inside a panel. `slds-notify_alert` stays only for an org-wide state at the top of a page (automation paused).

### Figures: `c-barn-stat-tile`

- A row of tiles: `<div class="slds-grid slds-wrap slds-gutters_x-small">`, each tile in `slds-col slds-size_1-of-2 slds-medium-size_1-of-4 slds-var-m-bottom_x-small`, with `bordered` and `align="start"`. Two per row on a phone.
- A single hero figure: the default (centered, no border).
- Money uses `format-style="currency"`; a rate uses `percent` with a fraction. Never print a raw `{value}` number.
- A tile that opens the list behind it uses `href` (or `clickable` and `select`), never a separate Open button.

### Shares and progress: `c-barn-meter`

- Any "N of M" or percent that people compare uses a meter, so the share has a shape and the number is always in text beside it. A long-running job keeps `lightning-progress-bar` inside its own job panel.

### Icons: `c/barnIcons`

- Rule: a link to a tab, and a card about a tab's object, uses that tab's icon: `icon-name={icons.gift}` with `icons = { gift: iconFor('Gift__c') }`. A tab icon is never borrowed by another object's card.
- Card headers use `custom:` or `standard:` icons only, never `utility:` (a grey glyph beside colored tiles). Every card with a `custom:` icon is a row in the Card Icons table of [Tab Icons](tab-icons.md#card-icons).
- A new tab gets its registry entry in the same PR. `scripts/ci/tests/test_core_navigation.py` checks the registry against every tab, and checks each card against the Card Icons table (the icon as a literal or as `iconFor('<tab>')`).

### Empty states: `c-barn-empty-state`

- A panel or page with nothing yet: `size="small"` (default) or `large`, with `illustration` `no-data`, `setup` (something to set up first) or `all-clear` (a good empty: nothing to approve, no errors), and the panel's first action in the slot.
- A card in a record page sidebar, or a section inside a panel: `size="compact"` (no art, a small heading, one weak line).
- Plain text stays only for an empty column inside a board or diagram.

### Tables

The recipe for a hand-built table:

```html
<table class="slds-table slds-table_bordered slds-table_cell-buffer slds-max-medium-table_stacked">
```

- Add `slds-table_fixed-layout` with `slds-truncate` and a `title` on text cells when columns are long.
- Every `th` and `td` carries `data-label` (the column name) so the stacked phone view labels each value.
- A deliberately wide table (an import preview with every column) sits in `slds-scrollable_x` and carries the `data-wide-table` attribute instead of stacking.
- Prefer `lightning-datatable` for record lists that sort or select; it handles narrow screens itself.

### Type scale

| Step | Use | Class |
|---|---|---|
| 1 Page | The page title | the platform header, or the shell's `h1` |
| 2 Card or section | A card or a top section | `lightning-card` title, or `h2.slds-text-heading_medium` |
| 3 Subsection | A group inside a card | `h3.slds-text-heading_small` |
| 4 Label | A label over a value, a row's name | `slds-text-title_bold` |
| Body | Running text | default, or `slds-text-body_regular` |
| Help and meta | Dates, roles, a one-line hint | `slds-text-body_small slds-text-color_weak` |

- Don't: `slds-text-title_caps` (ALL CAPS breaks Title Case), `slds-text-heading_x-small` or `slds-text-title` for the label step.

### Spacing

- Use the density-aware `slds-var-*` classes (`slds-var-m-bottom_small`, `slds-var-p-horizontal_medium`), which follow the person's Comfy or Compact setting; never the plain `slds-m-*` or `slds-p-*`.
- Card body padding is `slds-var-p-horizontal_medium` (or `slds-card__body_inner`). Between blocks in a card, `slds-var-m-bottom_small`; between sections, `slds-var-m-bottom_medium`.
- Custom CSS spacing uses `--slds-g-spacing-*` hooks with a fallback.

### Check

`scripts/ci/check-visual-standard.py` (run by `run-offline-checks.sh` and CI) fails a component that adds `slds-text-title_caps`, a solid `slds-box slds-theme_*` message, a non-stacking `slds-table` without `data-wide-table`, or `slds-badge_inverse`. Screens built earlier are counted in `scripts/ci/visual-standard-baseline.txt`; when a screen adopts the kit, lower or delete its lines (`--write-baseline` rewrites the file from the code). A count never goes up.
