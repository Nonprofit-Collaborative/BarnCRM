# UX Kit

A few small Core components that every admin screen is built from, so the screens look and behave alike. They live in `packages/core/main/default/lwc/` with the `barn` prefix, are not exposed to App Builder, and are placed inside other components. The plan behind them is decision D-140 in the product plan.

Rules for any screen:

- Show the task, hide the manual. No visible paragraph over 25 words on an admin screen; longer help goes in a popover, the About This Tool region, or the admin guide.
- Title Case for every title, heading, tab, tile and button; sentence case for body text and field labels.
- One card level. Never a card inside a card.
- No hard-coded colors or sizes. CSS uses SLDS 2 styling hooks (`--slds-g-*`) with a fallback, and `npm run lint:slds` must report no violations.
- Every UI string and message comes from a custom label; every help and guidance sentence comes from the package's help catalog (see Help Text below). Never add help prose as a label.

## Help Text

Help and guidance prose (an intro, a description, an explanation, an empty-state explanation, a setup note, a tooltip longer than a short phrase) lives in the package's JSON help catalog, not in custom labels (ADR-NEXT `NEXT-help-text-json.md`). Custom labels of an unmanaged or source install count toward the org's 5,000, and BarnCRM installs that way for a long time.

- **Where:** `packages/<dir>/main/default/staticresources/BarnHelp_<Package>.json` (`BarnHelp_Core`, `BarnHelp_Rollups`, `BarnHelp_Giving`, `BarnHelp_Volunteers`, `BarnHelp_Programs`, `BarnHelp_LogicModels`, `BarnHelp_Funders`, `BarnHelp_Mirror`), shaped `{ "languages": ["en"], "texts": { "<key>": "<text>" } }`. A package's first help text adds its catalog and a `.resource-meta.xml` copied from Core's. English only for now.
- **Keys:** named like labels, `<Package>_<Area>_<What>` (`Core_OrgOptimizer_Intro`). Keep the keys sorted.
- **What stays a label:** titles, buttons, tabs, column headers, field labels, short status words, every error, toast, confirmation, validation, notice, log line and run result, sentences with `{0}` about the current state, text written into records, emails and files, and anything named from FlexiPage, Flow or custom metadata.
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
| `c-barn-empty-state` | Any "nothing here yet" | `illustration` (`no-data`, `setup`, `all-clear`), `heading`, `message`, `size`, `heading-level`; default slot for the action |
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
| `c-barn-stat-tile` | One count as a big number over a label (import preview and results, Org Optimizer counts) | `label`, `value` (a number is formatted; text is shown as given), `badge-label`, `badge-variant` |
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

Each component has Jest tests written as stories (one case per variant a screen uses). Add a story when you add a variant.
