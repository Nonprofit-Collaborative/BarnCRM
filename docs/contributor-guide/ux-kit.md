# UX Kit

A few small Core components that every admin screen is built from, so the screens look and behave alike. They live in `packages/core/main/default/lwc/` with the `barn` prefix, are not exposed to App Builder, and are placed inside other components. The plan behind them is decision D-140 in the product plan.

Rules for any screen:

- Show the task, hide the manual. No visible paragraph over 25 words on an admin screen; longer help goes in a popover, the About This Tool region, or the admin guide.
- Title Case for every title, heading, tab, tile and button; sentence case for body text and field labels.
- One card level. Never a card inside a card.
- No hard-coded colors or sizes. CSS uses SLDS 2 styling hooks (`--slds-g-*`) with a fallback, and `npm run lint:slds` must report no violations.
- Every string comes from a custom label.

## Part 1 Components

| Component | Use it for | Main properties |
|---|---|---|
| `c-barn-page-shell` | The page of an admin tool: one header, About This Tool help, body, footer | `icon-name`, `title`, `purpose`, `title-hidden`, `help-label`, `help-storage-key`, `status-message`; slots `actions`, `help`, `footer` and the default body |
| `c-barn-tool-grid` | A hub of tools in groups (Data Manager, the Org Optimizer overview, Home) | `groups` (each with `name`, `label`, `tiles`), `heading-level`; fires `select` with `detail.name` |
| `c-barn-tool-tile` | One tool on a hub; the whole tile is one link or button | `name`, `label`, `description`, `icon-name`, `href`, `badge-label`, `badge-variant`, `disabled`, `disabled-reason`; fires `select` |
| `c-barn-empty-state` | Any "nothing here yet" | `illustration` (`no-data`, `setup`, `all-clear`), `heading`, `message`, `size`, `heading-level`; default slot for the action |
| `c-barn-help` | Help next to a field or section | `content` (popover), `learn-more-url`, `learn-more-label`, `alternative-text` |

Notes:

- On a Lightning App Page the platform already prints the page name above the component. Pass `title-hidden` to the shell so the name is not printed twice; the `h1` stays for screen readers.
- The About This Tool region opens on a person's first visit and stays closed after that. With `help-storage-key` the person's own choice is remembered in their browser only; it is a convenience, not a setting.
- A disabled tile stays focusable so a screen reader reads why it is disabled.
- Every link that opens a new tab goes through `c-barn-help` or copies its pattern: `rel="noopener noreferrer"`, the new-window icon, and "(opens in a new tab)" for screen readers.

Each component has Jest tests written as stories (one case per variant a screen uses). Add a story when you add a variant. Part 2 (step flow, visual picker, stat tile) and the save bar follow in later pull requests.
