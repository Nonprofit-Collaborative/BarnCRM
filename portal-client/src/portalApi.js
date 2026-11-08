/**
 * Calls the BarnCRM portal API through the website's own proxy (the WordPress plugin, or any
 * server that does the same job). The browser never holds the OAuth secret or the session token:
 * the proxy adds the integration user's access token, keeps the session token in an HttpOnly
 * cookie and strips it from answers (ADR-0185 portal builder, decision 8).
 *
 * Framework-free: works in any browser and in Node with a fetch implementation.
 */

/** An answer the API refused, with its code (for example `code_invalid` or `not_allowed`). */
export class PortalError extends Error {
  constructor(code, status) {
    super(code);
    this.name = 'PortalError';
    this.code = code;
    this.status = status;
  }
}

/**
 * @param {object} options
 * @param {string} options.baseUrl the proxy's address, for example `/wp-json/barncrm-portal/v1`
 * @param {string} options.portal the portal key, sent with every call so the proxy picks the
 *   right session cookie
 * @param {string} [options.nonce] a value the proxy checks on every call (the plugin's nonce)
 * @param {Function} [options.fetch] a fetch implementation; the browser's by default
 */
export function createPortalApi({ baseUrl, portal, nonce, fetch: fetchImpl }) {
  const doFetch = fetchImpl || globalThis.fetch.bind(globalThis);
  const root = String(baseUrl).replace(/\/+$/, '');

  async function call(method, path, body) {
    const headers = { Accept: 'application/json', 'X-BarnCRM-Portal': portal };
    if (nonce) {
      headers['X-BarnCRM-Nonce'] = nonce;
    }
    const init = { method, headers, credentials: 'same-origin' };
    if (body !== undefined) {
      headers['Content-Type'] = 'application/json';
      init.body = JSON.stringify(body);
    }
    let response;
    try {
      response = await doFetch(root + '/' + path, init);
    } catch (offline) {
      throw new PortalError('network_error', 0);
    }
    let answer = null;
    try {
      answer = await response.json();
    } catch (notJson) {
      answer = null;
    }
    if (!response.ok || !answer || answer.ok === false) {
      throw new PortalError((answer && answer.error) || 'server_error', response.status);
    }
    return answer;
  }

  return {
    /** Asks for a sign-in code. The answer is the same whether or not the email is on file. */
    start: (email) => call('POST', 'login/start', { portal, email }),
    /** Checks the emailed code: `signedIn`, `secondFactor` or `enroll`. */
    verify: (challenge, code) => call('POST', 'login/verify', { challenge, code }),
    /** Checks an authenticator code after the emailed one. */
    secondFactor: (challenge, code) => call('POST', 'login/second-factor', { challenge, code }),
    /** The template title, the person's first name and their pages. */
    me: () => call('GET', 'me'),
    /** One page: its fields and the person's records on it. */
    page: (key) => call('GET', 'page?key=' + encodeURIComponent(key)),
    /** Saves the editable fields of one record (no recordId adds one, where the page allows). */
    save: (page, recordId, values) => call('POST', 'page/save', { page, recordId, values }),
    /** Runs a module's action on one record. */
    action: (page, recordId, action) => call('POST', 'page/action', { page, recordId, action }),
    /** Starts adding an authenticator while signed in. */
    enroll: () => call('POST', 'second-factor/enroll', {}),
    /** Confirms the authenticator with its first code. */
    confirmEnroll: (code) => call('POST', 'second-factor/confirm', { code }),
    /** Ends this session. */
    logout: () => call('POST', 'logout', {})
  };
}
