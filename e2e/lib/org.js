// Calls to the sf CLI for the org under test. The front-door URL carries a session id: it is
// returned to the caller only, and no error raised here ever includes it or the CLI's output.

const { execFileSync } = require('child_process');

const API_VERSION = 'v62.0';

function sfJson(args, what) {
  let out;
  try {
    out = execFileSync('sf', [...args, '--json'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
      maxBuffer: 64 * 1024 * 1024
    });
  } catch (error) {
    // execFileSync's error carries stdout, which for `org open` is the session URL.
    throw new Error(`sf CLI failed: ${what} (exit ${error.status}). Is the alias authorized?`);
  }
  try {
    return JSON.parse(out);
  } catch {
    throw new Error(`sf CLI returned output that is not JSON: ${what}.`);
  }
}

/** A one-time sign-in URL for the org's default user. Never log or store it. */
function frontDoorUrl(alias) {
  const result = sfJson(['org', 'open', '-o', alias, '--url-only'], `org open -o ${alias}`).result;
  if (!result || !result.url) {
    throw new Error(`sf org open gave no URL for ${alias}.`);
  }
  return result.url;
}

function queryNames(alias, soql, tooling) {
  const args = ['data', 'query', '-o', alias, '-q', soql];
  if (tooling) {
    args.push('--use-tooling-api');
  }
  const json = sfJson(args, `data query on ${alias}`);
  return (json.result.records || []).map((record) => record.Name || record.DeveloperName);
}

/**
 * What the org holds, read once per run: the tabs that exist (TabDefinition), the tabs the
 * running user can see (the REST tabs describe), and the unpackaged apps (AppDefinition).
 */
function orgShape(alias) {
  const allTabs = queryNames(alias, 'SELECT Name FROM TabDefinition WHERE IsCustom = true', true);
  // `sf api request rest` prints the response body itself, not a --json envelope.
  let visible;
  try {
    visible = JSON.parse(
      execFileSync(
        'sf',
        ['api', 'request', 'rest', `/services/data/${API_VERSION}/tabs`, '-o', alias],
        {
          encoding: 'utf8',
          stdio: ['ignore', 'pipe', 'ignore'],
          maxBuffer: 64 * 1024 * 1024
        }
      )
    ).map((tab) => tab.name);
  } catch {
    throw new Error(`Could not read the tabs the user of ${alias} can see.`);
  }
  const apps = queryNames(
    alias,
    'SELECT DeveloperName FROM AppDefinition WHERE NamespacePrefix = null',
    false
  );
  return { allTabs, visibleTabs: visible, apps };
}

module.exports = { frontDoorUrl, orgShape };
