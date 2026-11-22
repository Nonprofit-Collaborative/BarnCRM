/**
 * BarnCRM Connector's file rules for the browser (CN-08; canonical model R-CR13 to R-CR15;
 * security review F1, F4). Framework free, so it runs in Jest and ports to BarnCRM for WordPress
 * (plan 9.9). It returns help keys, never text. Apex (ConnectorRecipeFiles) checks every rule
 * again; these spare a round trip and keep a file holding a secret from leaving the browser.
 */

export const MAX_FILE = 400000;
const SECRET_KEYS = [
  'password',
  'secret',
  'clientsecret',
  'token',
  'accesstoken',
  'refreshtoken',
  'apikey',
  'apisecret',
  'authorization',
  'credential',
  'privatekey',
  'secreturl'
];
const FORMULA_KEYS = [
  'header',
  'headervalue',
  'headertemplate',
  'formula',
  'allowmergefieldsinbody',
  'allowmergefieldsinheader'
];
const SIGN_IN_HEADER = /(key|token|secret|auth|password|signature|session)/i;
const SIGN_IN_VALUE = /^\s*(bearer|basic)\s+(?=[A-Za-z._~+/=-]*[0-9])[A-Za-z0-9._~+/=-]{12,}\s*$/i;
const PLACEHOLDER = /\{([A-Za-z0-9_]{1,40})\}/g;

/** The first refusal a value holds (R-CR15, F1), as `{ key, detail }`, or null. */
function scan(value) {
  if (Array.isArray(value)) {
    for (const item of value) {
      const found = scan(item);
      if (found) {
        return found;
      }
    }
    return null;
  }
  if (value && typeof value === 'object') {
    for (const key of Object.keys(value)) {
      const plain = key.toLowerCase().replace(/[-_]/g, '');
      if (SECRET_KEYS.includes(plain)) {
        return { key: 'Connector_Import_ErrorSecret', detail: key };
      }
      if (FORMULA_KEYS.includes(plain)) {
        return { key: 'Connector_Import_ErrorFormula', detail: key };
      }
      const found = scan(value[key]);
      if (found) {
        return found;
      }
    }
    const headers = Array.isArray(value.headers) ? value.headers : [];
    const signIn = headers.find(
      (header) => header && SIGN_IN_HEADER.test(header.name || '') && !header.path && header.value
    );
    return signIn ? { key: 'Connector_Import_ErrorSecret', detail: signIn.name } : null;
  }
  if (typeof value === 'string' && SIGN_IN_VALUE.test(value)) {
    return { key: 'Connector_Import_ErrorSecret', detail: value.trim().split(/\s/)[0] };
  }
  return null;
}

/**
 * What is wrong with a file's text before it is sent, as `{ key, detail }`, or null: its size,
 * whether it is a JSON object, a merge field anywhere (F1), a secret or a formula option.
 */
export function fileProblem(text) {
  const source = typeof text === 'string' ? text : '';
  if (!source.trim() || source.length > MAX_FILE) {
    return { key: 'Connector_Import_ErrorSize', detail: '' };
  }
  let parsed;
  try {
    parsed = JSON.parse(source);
  } catch {
    parsed = undefined;
  }
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    return { key: 'Connector_Import_ErrorUnreadable', detail: '' };
  }
  if (JSON.stringify(parsed).includes('{!')) {
    return { key: 'Connector_Import_ErrorMergeField', detail: '' };
  }
  return scan(parsed);
}

/** The placeholders of a template base URL, in order, once each. */
export function placeholders(baseUrl) {
  const names = [];
  String(baseUrl || '').replace(PLACEHOLDER, (whole, name) => {
    if (!names.includes(name)) {
      names.push(name);
    }
    return whole;
  });
  return names;
}

/**
 * A template's base URL with its placeholders filled (R-CR14), or null while any value is blank
 * or does not match its pattern; the host can change only in the placeholders (F4).
 */
export function lockedUrl(baseUrl, params, values) {
  let ready = true;
  const url = String(baseUrl || '').replace(PLACEHOLDER, (whole, name) => {
    const param = (params || []).find((entry) => entry.name === name);
    const value = String((values || {})[name] || '').trim();
    let pattern;
    try {
      pattern = param && param.pattern ? new RegExp(`^(?:${param.pattern})$`) : null;
    } catch {
      pattern = null;
    }
    if (!pattern || !value || !pattern.test(value) || /[^A-Za-z0-9-]/.test(value)) {
      ready = false;
    }
    return value;
  });
  return ready ? url : null;
}

/**
 * The non-secret part of a key a URL part is read from (Mailchimp's data center: what follows
 * the last `-`), or blank. Read once, at saving, never kept (F10).
 */
export function partOfKey(key, after) {
  const text = String(key || '');
  const at = after ? text.lastIndexOf(after) : -1;
  return at < 0 ? '' : text.slice(at + 1);
}

/** A file name for an exported recipe: its name in letters, digits and hyphens. */
export function exportName(name) {
  const base = String(name || 'recipe')
    .replace(/[^A-Za-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .toLowerCase();
  return `${base || 'recipe'}.json`;
}

/** Backup Settings headers as the page edits and sends them (R-CN11): `Name: value`, one a line. */
export function headerLines(headers) {
  return (Array.isArray(headers) ? headers : [])
    .filter((header) => header && header.name)
    .map((header) => `${header.name}: ${header.value || ''}`)
    .join('\n');
}
