// Opening a Lightning page and reading what went wrong on it.

const { expect } = require('@playwright/test');
const { barnComponents } = require('./metadata');

// Console messages Salesforce itself logs on every page, which say nothing about BarnCRM. Each is
// dropped before the remaining messages are attributed.
const PLATFORM_NOISE = [
  // Lightning's own markup uses inline event handlers that its Content Security Policy blocks.
  /violates the following Content Security Policy directive/,
  // Aura's profiler and In-App Guidance announce that they are off (logged as warnings in most
  // orgs, as errors in some).
  /ComponentProfiler: Component-level profiling/,
  /\[ORCHESTRATION\] In-App Guidance is disabled/
];

// What a broken page shows. Matched only when visible, so text that exists in a closed panel
// or in help text not on screen does not count.
const ERROR_TEXT = [
  'Sorry to interrupt',
  'Something went wrong',
  'This page has an error',
  "Looks like there's a problem"
];
const ERROR_SELECTORS = [
  // Error toasts (Aura and LWC flavors).
  '.forceToastMessage.slds-theme--error',
  '.slds-notify_toast.slds-theme_error',
  // An error alert inside the page, such as c/barnNotice with variant "error".
  '[role="alert"].slds-theme_error',
  '.slds-notify_alert.slds-theme_error'
];

const BARN_COMPONENTS = barnComponents();
const kebab = (name) => name.replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`);

/** True when a console message names a BarnCRM component (c/name, c:name or c-kebab-name). */
function fromBarn(text) {
  const refs = text.match(/\bc[/:][A-Za-z0-9_]+|\bc-[a-z0-9-]+/g) || [];
  return refs.some((ref) => {
    const name = ref.startsWith('c-')
      ? [...BARN_COMPONENTS].find((bundle) => `c-${kebab(bundle)}` === ref)
      : ref.slice(2);
    return name && BARN_COMPONENTS.has(name);
  });
}

class Lightning {
  constructor(page, org) {
    this.page = page;
    this.org = org;
    this.messages = [];
    this.onConsole = (message) => {
      if (message.type() === 'error') {
        this.messages.push(message.text());
      }
    };
    this.onPageError = (error) => {
      this.messages.push(`Uncaught ${error.name}: ${error.message}\n${error.stack || ''}`);
    };
  }

  listen() {
    this.page.on('console', this.onConsole);
    this.page.on('pageerror', this.onPageError);
  }

  stopListening() {
    this.page.off('console', this.onConsole);
    this.page.off('pageerror', this.onPageError);
  }

  /** Opens a page inside an app: `/lightning/app/c__<App><path>`, for example `/n/Find`. */
  async open(app, pagePath) {
    // A Lightning page tab (/n/) holds only BarnCRM components, so every console error on it is
    // BarnCRM's, even one a base component logs without naming its parent (ERR_RP009, for
    // example). An object's list view is a Salesforce page: there only errors naming a BarnCRM
    // component count.
    this.barnPage = pagePath.startsWith('/n/');
    await this.page.goto(`${this.org.origin}/lightning/app/c__${app}${pagePath}`);
    await this.waitLoaded();
  }

  /** The visible main region: the page in a standard app, the focused workspace tab in a console. */
  main() {
    return this.page.locator('[role="main"]:visible').first();
  }

  /**
   * Loaded: the main region is visible, holds text, shows no spinner, and its text has stopped
   * changing between two reads a second apart.
   */
  async waitLoaded() {
    const main = this.main();
    await expect(main).toBeVisible();
    let last = -1;
    await expect
      .poll(
        async () => {
          const spinners = await main
            .locator('lightning-spinner:visible, .slds-spinner:visible')
            .count();
          const length = (await main.innerText()).trim().length;
          const settled = spinners === 0 && length > 0 && length === last;
          last = length;
          return settled;
        },
        {
          message: 'page never settled: a spinner stayed or the content kept changing',
          intervals: [1000]
        }
      )
      .toBe(true);
  }

  /** The error panels, toasts and alerts visible on the page, with their text. */
  async visibleErrors() {
    const found = [];
    for (const text of ERROR_TEXT) {
      const match = this.page.getByText(text, { exact: false });
      for (const element of await match.all()) {
        if (await element.isVisible()) {
          found.push((await element.innerText()).trim().slice(0, 300));
        }
      }
    }
    for (const selector of ERROR_SELECTORS) {
      for (const element of await this.page.locator(selector).all()) {
        if (await element.isVisible()) {
          found.push((await element.innerText()).trim().slice(0, 300));
        }
      }
    }
    return [...new Set(found)];
  }

  /** Console errors after the platform noise is dropped, split by whether they are BarnCRM's. */
  consoleErrors() {
    const kept = this.messages.filter((text) => !PLATFORM_NOISE.some((noise) => noise.test(text)));
    const isBarn = (text) => this.barnPage || fromBarn(text);
    return {
      barn: kept.filter(isBarn),
      other: kept.filter((text) => !isBarn(text))
    };
  }

  /** The smoke assertions every page gets. Other console errors are attached, not failed. */
  async expectHealthy(testInfo) {
    expect(await this.visibleErrors(), 'error panel, toast or alert on the page').toEqual([]);
    const { barn, other } = this.consoleErrors();
    if (other.length) {
      testInfo.annotations.push({
        type: 'console',
        description: other.map((text) => text.split('\n')[0].slice(0, 200)).join(' || ')
      });
    }
    expect(barn, 'console errors from BarnCRM components').toEqual([]);
  }
}

module.exports = { Lightning, fromBarn };
