import CORE_HELP_URL from '@salesforce/resourceUrl/BarnHelp_Core';
import LANGUAGE from '@salesforce/i18n/lang';
import { createHelpStore } from 'c/barnHelpCatalog';

/**
 * Help and guidance text from the packaged JSON catalogs (ADR-0164 help-text-json). The
 * Salesforce half of c/barnHelpCatalog: it knows the static resource URLs, the user's language
 * and fetch, and keeps one store for the page.
 *
 * In a component:
 *   import { helpText, loadHelp, isHelpLoaded } from 'c/barnHelpText';
 *   helpReady = isHelpLoaded('Core');
 *   connectedCallback() { if (!this.helpReady) loadHelp('Core').then(() => { this.helpReady = true; }); }
 *   get intro() { return helpText('Core', 'Core_Example_Intro'); }
 * and wrap the template in <template lwc:if={helpReady}> so the first render has the text.
 * For a popover next to a field, use <c-barn-help help-package="Core" help-key="...">.
 */

// The URL of another package's catalog: Core's own, with the name swapped. The prefix before
// the name (a namespace, once there is one) is kept, so nothing is hard-coded. The timestamp
// segment is dropped: it is Core's, and a module's catalog changes when the module does.
function urlFor(name) {
  const url = String(CORE_HELP_URL || '');
  const at = url.lastIndexOf('BarnHelp_Core');
  if (at < 0) {
    return '/resource/' + name;
  }
  const lastSlash = url.lastIndexOf('/', at);
  const prefix = url.substring(lastSlash + 1, at);
  return '/resource/' + prefix + name;
}

function fetchJson(url) {
  return fetch(url, { credentials: 'same-origin' }).then((response) => {
    return response.ok ? response.json() : null;
  });
}

function onMissing(pkg, key) {
  console.warn(`BarnCRM help text ${pkg}.${key} is missing from BarnHelp_${pkg}.`);
}

const store = createHelpStore(fetchJson, urlFor, onMissing);

/** Loads one package's help ('Core', 'Giving', ...) or several (an array); resolves when in. */
export function loadHelp(packages) {
  return store.load(packages, LANGUAGE);
}

/** True when the packages' help is already loaded on this page. */
export function isHelpLoaded(packages) {
  return store.isLoaded(packages);
}

/** The text for a key, formatted with any further arguments ({0}, {1}); empty until loaded. */
export function helpText(pkg, key, ...args) {
  return store.text(pkg, key, args);
}
