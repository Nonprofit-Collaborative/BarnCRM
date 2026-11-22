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
// segment is dropped: it is Core's, and a module's catalog changes when the module does. The
// path before /resource/ is kept too, so a page on a Salesforce Site with a path prefix (a
// public form, C-42b) reads the catalog from its own Site.
//
// A static resource read without its timestamp is served with a 45-day public cache, and
// Salesforce still served a catalog's previous file a day after a deploy, so an upgrade's new
// keys read as missing (blank buttons and tile labels). The hour in the query string makes a
// new address each hour: an upgrade's text shows within the hour, and within the hour a page
// still reads each catalog from the cache.
const HOUR_MS = 3600000;

function urlFor(name) {
  const version = '?v=' + Math.floor(Date.now() / HOUR_MS);
  const url = String(CORE_HELP_URL || '');
  const at = url.lastIndexOf('BarnHelp_Core');
  if (at < 0) {
    return '/resource/' + name + version;
  }
  const lastSlash = url.lastIndexOf('/', at);
  const prefix = url.substring(lastSlash + 1, at);
  const resourceAt = url.indexOf('/resource/');
  const site = resourceAt > 0 ? url.substring(0, resourceAt) : '';
  return site + '/resource/' + prefix + name + version;
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
