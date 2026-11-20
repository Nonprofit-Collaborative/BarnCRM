/**
 * BarnCRM Connector's connection rules for the browser (CN-01, canonical model 29CN1). Framework
 * free, so it runs in Jest and ports to BarnCRM for WordPress (plan 9.9). The server checks every
 * rule again (ConnectorConnections); these only spare a round trip and turn answers into help
 * keys. No function here takes or keeps a key (security review F10).
 */

/** The built-in auth kinds, each also its principal's name (R-CN2), and their help keys. */
export const KINDS = [
  { value: 'ApiKeyHeader', key: 'Connector_Kind_ApiKeyHeader' },
  { value: 'BearerToken', key: 'Connector_Kind_BearerToken' },
  { value: 'BasicAuth', key: 'Connector_Kind_BasicAuth' },
  { value: 'SecretUrl', key: 'Connector_Kind_SecretUrl' }
];

export const SECRET_URL = 'SecretUrl';
export const API_KEY = 'ApiKeyHeader';
export const BASIC = 'BasicAuth';

const RESERVED_HEADERS = ['authorization', 'host', 'cookie', 'content-length', 'transfer-encoding'];

/** The help key naming a kind, or blank for an unknown one. */
export function kindKey(kind) {
  const found = KINDS.find((entry) => entry.value === kind);
  return found ? found.key : '';
}

/**
 * Whether an address is one a connection may use (R-CN4, F4): `https`, a host, no user
 * information, query, fragment, spaces, backslash or `{!`.
 */
export function isSafeUrl(value) {
  const text = typeof value === 'string' ? value.trim() : '';
  if (!/^https:\/\//i.test(text) || /\s|\\|\{!/.test(text) || text.length > 1000) {
    return false;
  }
  let parsed;
  try {
    parsed = new URL(text);
  } catch {
    return false;
  }
  return (
    parsed.protocol === 'https:' &&
    Boolean(parsed.hostname) &&
    !parsed.username &&
    !parsed.password &&
    !parsed.search &&
    !parsed.hash
  );
}

/** Letters, digits and hyphens, at most 64, and not a header the kind or Salesforce sets. */
export function isHeaderName(value) {
  const text = typeof value === 'string' ? value.trim() : '';
  return /^[A-Za-z0-9-]{1,64}$/.test(text) && !RESERVED_HEADERS.includes(text.toLowerCase());
}

/**
 * What stops a form from being sent, as help keys. `form` holds the non-secret fields and
 * `hasSecret`, whether the key box is filled; `replacing` is true for Replace Key, which keeps
 * the name, kind, URL and header.
 */
export function formProblems(form, replacing) {
  const problems = [];
  const kind = form.authKind;
  if (!replacing) {
    const label = typeof form.label === 'string' ? form.label.trim() : '';
    if (!label || label.length > 80 || label.includes('{!')) {
      problems.push('Connector_Error_Label');
    }
    if (!kindKey(kind)) {
      problems.push('Connector_Error_Kind');
    }
    if (kind && kind !== SECRET_URL && !isSafeUrl(form.baseUrl)) {
      problems.push('Connector_Error_Url');
    }
    if (kind === API_KEY && !isHeaderName(form.headerName)) {
      problems.push('Connector_Error_HeaderName');
    }
  }
  if (kind === BASIC && !(typeof form.userName === 'string' && form.userName.trim())) {
    problems.push('Connector_Error_UserRequired');
  }
  if (!form.hasSecret) {
    problems.push(kind === SECRET_URL ? 'Connector_Error_Url' : 'Connector_Error_KeyRequired');
  }
  return problems;
}

/** A connection's status as a help key and a notice variant (Setup step first). */
export function statusOf(connection) {
  if (!connection.calloutsEnabled) {
    return { key: 'Connector_Status_CalloutsOff', variant: 'warning' };
  }
  if (!connection.accessGranted) {
    return { key: 'Connector_Status_AccessMissing', variant: 'warning' };
  }
  if (!connection.keyStored) {
    return { key: 'Connector_Status_Disconnected', variant: 'info' };
  }
  return { key: 'Connector_Status_Ready', variant: 'success' };
}

/** What a write or check did, as a help key, a notice variant and the app's status if any. */
export function outcomeOf(result) {
  const outcome = result && result.outcome;
  const status = result && result.status;
  if (outcome === 'answered') {
    if (status >= 200 && status < 300) {
      return { key: 'Connector_Outcome_Connected', variant: 'success', status };
    }
    if (status === 401 || status === 403) {
      return { key: 'Connector_Outcome_KeyRefused', variant: 'error', status };
    }
    return { key: 'Connector_Outcome_Answered', variant: 'warning', status };
  }
  const fixed = {
    created: ['Connector_Outcome_Created', 'success'],
    createdAccessMissing: ['Connector_Outcome_CreatedAccessMissing', 'warning'],
    replaced: ['Connector_Outcome_Replaced', 'success'],
    disconnected: ['Connector_Outcome_Disconnected', 'success'],
    deleted: ['Connector_Outcome_Deleted', 'success'],
    deleteInSetup: ['Connector_Outcome_DeleteInSetup', 'warning'],
    calloutsOff: ['Connector_Outcome_CalloutsOff', 'warning'],
    accessAdded: ['Connector_Outcome_AccessAdded', 'info'],
    accessMissing: ['Connector_Outcome_AccessMissing', 'warning'],
    unreachable: ['Connector_Outcome_Unreachable', 'error']
  }[outcome] || ['Connector_Error_Unexpected', 'error'];
  return { key: fixed[0], variant: fixed[1], status };
}
