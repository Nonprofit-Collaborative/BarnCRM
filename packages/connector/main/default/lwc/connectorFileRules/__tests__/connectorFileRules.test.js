import {
  fileProblem,
  placeholders,
  lockedUrl,
  partOfKey,
  exportName,
  headerLines,
  MAX_FILE
} from 'c/connectorFileRules';

const text = (value) => JSON.stringify(value);

describe('backup destination templates (R-CN11)', () => {
  const fs = require('fs');
  const path = require('path');
  const folder = path.join(__dirname, '../../../../../../../docs/connector-templates');

  it('passes each example template in docs/connector-templates', () => {
    const files = fs.readdirSync(folder).filter((name) => name.endsWith('.json'));
    expect(files.length).toBeGreaterThan(0);
    files.forEach((name) => {
      expect(fileProblem(fs.readFileSync(path.join(folder, name), 'utf8'))).toBeNull();
    });
  });

  it('refuses a backup part with a sign-in header', () => {
    const file = { key: 'x', backup: { headers: [{ name: 'X-Api-Key', value: 'abc' }] } };
    expect(fileProblem(text(file))).toEqual({ key: 'Connector_Import_ErrorSecret', detail: 'X-Api-Key' });
  });

  it('turns headers into Name: value lines', () => {
    expect(headerLines([{ name: 'Overwrite', value: 'T' }, { name: 'X-Folder', value: 'crm' }, null])).toBe(
      'Overwrite: T\nX-Folder: crm'
    );
    expect(headerLines(undefined)).toBe('');
  });
});

describe('c/connectorFileRules (CN-08, R-CR13 to R-CR15)', () => {
  it('accepts a plain template or recipe file', () => {
    expect(fileProblem(text({ key: 'mailchimp', label: 'Mailchimp', version: 1 }))).toBeNull();
    expect(
      fileProblem(
        text({
          barnRecipe: 1,
          recipe: { steps: [{ headers: [{ name: 'X-Api-Key', value: '' }] }] }
        })
      )
    ).toBeNull();
  });

  it('refuses an empty, oversized or unreadable file', () => {
    expect(fileProblem('')).toEqual({ key: 'Connector_Import_ErrorSize', detail: '' });
    expect(fileProblem(' '.repeat(MAX_FILE + 1))).toEqual({
      key: 'Connector_Import_ErrorSize',
      detail: ''
    });
    expect(fileProblem('not json').key).toBe('Connector_Import_ErrorUnreadable');
    expect(fileProblem('[1, 2]').key).toBe('Connector_Import_ErrorUnreadable');
  });

  it('refuses a merge field, also when written with JSON escapes (F1)', () => {
    expect(fileProblem(text({ note: '{!$Credential.X.Y}' })).key).toBe(
      'Connector_Import_ErrorMergeField'
    );
    expect(fileProblem('{"note":"\\u007b!$Credential.X.Y}"}').key).toBe(
      'Connector_Import_ErrorMergeField'
    );
  });

  it('refuses a secret key, a sign-in value or a typed sign-in header (R-CR15)', () => {
    expect(fileProblem(text({ webhook: { apiKey: 'abc' } }))).toEqual({
      key: 'Connector_Import_ErrorSecret',
      detail: 'apiKey'
    });
    expect(fileProblem(text({ client_secret: 'x' })).detail).toBe('client_secret');
    const bearer = fileProblem(text({ description: 'Bearer abcdef1234567890' }));
    expect(bearer).toEqual({ key: 'Connector_Import_ErrorSecret', detail: 'Bearer' });
    expect(JSON.stringify(bearer)).not.toContain('abcdef1234567890');
    expect(fileProblem(text({ description: 'Basic setup for beginners' }))).toBeNull();
    expect(
      fileProblem(text({ steps: [{ headers: [{ name: 'X-Auth-Token', value: 'typed' }] }] }))
    ).toEqual({ key: 'Connector_Import_ErrorSecret', detail: 'X-Auth-Token' });
    expect(
      fileProblem(text({ steps: [{ headers: [{ name: 'X-Auth-Token', path: 'trigger.token' }] }] }))
    ).toBeNull();
  });

  it('refuses an auth header template or a body formula option', () => {
    expect(fileProblem(text({ auth: { headerTemplate: 'x' } }))).toEqual({
      key: 'Connector_Import_ErrorFormula',
      detail: 'headerTemplate'
    });
    expect(fileProblem(text({ allowMergeFieldsInBody: true })).detail).toBe(
      'allowMergeFieldsInBody'
    );
  });

  it('fills a locked base URL only in its host placeholders (F4)', () => {
    const params = [{ name: 'dc', pattern: '[a-z]{2}[0-9]{1,3}' }];
    const url = 'https://{dc}.api.mailchimp.com/3.0';
    expect(placeholders(url)).toEqual(['dc']);
    expect(lockedUrl(url, params, { dc: 'us21' })).toBe('https://us21.api.mailchimp.com/3.0');
    expect(lockedUrl(url, params, { dc: '' })).toBeNull();
    expect(lockedUrl(url, params, { dc: 'evil.com/x' })).toBeNull();
    expect(lockedUrl(url, params, { dc: 'usa' })).toBeNull();
    expect(lockedUrl(url, [{ name: 'dc' }], { dc: 'us21' })).toBeNull();
  });

  it('reads a URL part from what follows a key, and names an export file', () => {
    expect(partOfKey('0123456789abcdef-us21', '-')).toBe('us21');
    expect(partOfKey('nodash', '-')).toBe('');
    expect(partOfKey('a-b', '')).toBe('');
    expect(exportName('Send People: Weekly!')).toBe('send-people-weekly.json');
    expect(exportName('')).toBe('recipe.json');
  });
});
