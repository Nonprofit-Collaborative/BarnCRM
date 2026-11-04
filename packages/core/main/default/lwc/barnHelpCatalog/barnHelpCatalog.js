/**
 * Help text catalogs (ADR-NEXT help-text-json), framework-free: no lightning/* or @salesforce/*
 * import, so a WordPress block or Node can reuse it (plan 9.9).
 *
 * Each package ships its help and guidance prose as one JSON static resource, BarnHelp_<Package>,
 * shaped { "languages": ["en"], "texts": { "<key>": "<text>" } }. Keys are the API names the
 * text had as custom labels. English is the base; a translation is a second resource,
 * BarnHelp_<Package>_<language> (for example BarnHelp_Giving_fr), listed in the English file's
 * "languages", holding only the keys it translates. A key missing from the translation falls
 * back to English; a key missing everywhere reads as empty text, never an error.
 *
 * createHelpStore(fetchJson, urlFor) makes one store per page: each package's catalog is
 * fetched once, the same promise is shared by every caller, and text() answers synchronously
 * once the catalog is in.
 */

export const BASE_LANGUAGE = 'en';

/**
 * The translations to try for a user language, most specific first: fr-CA gives fr_CA, fr.
 * English in any region gives none: English is the base. Matches BarnHelp.languageCandidates.
 */
export function languageCandidates(language) {
  const normalized = String(language || '').replace('-', '_');
  const base = normalized.split('_')[0];
  if (!normalized || base === BASE_LANGUAGE) {
    return [];
  }
  return base === normalized ? [normalized] : [normalized, base];
}

/** Replaces {0}, {1} and so on with the arguments, as a custom label's format would. */
export function formatHelp(text, args) {
  if (!text || !args || !args.length) {
    return text || '';
  }
  return text.replace(/\{(\d+)\}/g, (match, index) => {
    const value = args[index];
    return value === undefined || value === null ? match : String(value);
  });
}

function textsOf(catalog) {
  return catalog && typeof catalog.texts === 'object' && catalog.texts ? catalog.texts : {};
}

/**
 * fetchJson(url) resolves to the parsed JSON, or null when the resource is missing.
 * urlFor(resourceName) gives the URL of a static resource by its unprefixed name.
 */
export function createHelpStore(fetchJson, urlFor, onMissing) {
  const loaded = {};
  const pending = {};
  const warned = new Set();

  function fetchCatalog(name) {
    return Promise.resolve()
      .then(() => fetchJson(urlFor(name)))
      .catch(() => null);
  }

  function loadOne(pkg, language) {
    if (loaded[pkg]) {
      return Promise.resolve(loaded[pkg]);
    }
    if (!pending[pkg]) {
      const base = 'BarnHelp_' + pkg;
      pending[pkg] = fetchCatalog(base).then((english) => {
        const available = (english && english.languages) || [];
        const wanted = languageCandidates(language).filter((lang) => available.includes(lang));
        const translations = wanted.map((lang) => fetchCatalog(base + '_' + lang));
        return Promise.all(translations).then((found) => {
          // Most specific last, so it wins.
          const texts = Object.assign({}, textsOf(english), ...found.reverse().map(textsOf));
          loaded[pkg] = texts;
          return texts;
        });
      });
    }
    return pending[pkg];
  }

  return {
    /** Loads one package's catalog, or several (an array), once per page. */
    load(packages, language) {
      const list = Array.isArray(packages) ? packages : [packages];
      return Promise.all(list.map((pkg) => loadOne(pkg, language))).then(() => undefined);
    },

    /** True when every package named is already loaded, so a component can render at once. */
    isLoaded(packages) {
      const list = Array.isArray(packages) ? packages : [packages];
      return list.every((pkg) => Boolean(loaded[pkg]));
    },

    /** The text for a key, formatted with any arguments; empty until loaded or when missing. */
    text(pkg, key, args) {
      const texts = loaded[pkg];
      if (!texts) {
        return '';
      }
      const value = texts[key];
      if (value === undefined) {
        if (onMissing && !warned.has(pkg + '.' + key)) {
          warned.add(pkg + '.' + key);
          onMissing(pkg, key);
        }
        return '';
      }
      return formatHelp(value, args);
    }
  };
}
