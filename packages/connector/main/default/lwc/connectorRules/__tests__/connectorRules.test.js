import {
  KINDS,
  kindKey,
  isSafeUrl,
  isHeaderName,
  formProblems,
  statusOf,
  outcomeOf
} from 'c/connectorRules';

describe('c/connectorRules', () => {
  it('names the four built-in kinds and nothing else', () => {
    expect(KINDS.map((entry) => entry.value)).toEqual([
      'ApiKeyHeader',
      'BearerToken',
      'BasicAuth',
      'SecretUrl'
    ]);
    expect(kindKey('BearerToken')).toBe('Connector_Kind_BearerToken');
    expect(kindKey('OAuth')).toBe('');
  });

  it('accepts only https addresses with a host and no user, query, fragment or merge field', () => {
    expect(isSafeUrl('https://api.example.org/v2')).toBe(true);
    expect(isSafeUrl(' https://api.example.org ')).toBe(true);
    [
      'http://api.example.org',
      'https://user:pass@api.example.org',
      'https://api.example.org/?key=1',
      'https://api.example.org/#part',
      'https://api.example.org/{!$Credential.X}',
      'https://api.example.org/a b',
      'https://api.example.org\\x',
      'https://',
      'ftp://api.example.org',
      '',
      undefined,
      'https://' + 'a'.repeat(1000) + '.org'
    ].forEach((value) => expect(isSafeUrl(value)).toBe(false));
  });

  it('accepts a plain header name and refuses reserved or odd ones', () => {
    expect(isHeaderName('X-Api-Key')).toBe(true);
    ['Authorization', 'host', 'Cookie', 'X Api', 'X_Api', '', 'a'.repeat(65), null].forEach(
      (value) => expect(isHeaderName(value)).toBe(false)
    );
  });

  it('lists what stops a new connection, per kind', () => {
    expect(
      formProblems({
        label: 'Mailing list',
        authKind: 'BearerToken',
        baseUrl: 'https://api.example.org',
        hasSecret: true
      })
    ).toEqual([]);
    expect(formProblems({ label: '', authKind: '', hasSecret: false })).toEqual([
      'Connector_Error_Label',
      'Connector_Error_Kind',
      'Connector_Error_KeyRequired'
    ]);
    expect(
      formProblems({
        label: '{!x}',
        authKind: 'ApiKeyHeader',
        baseUrl: 'http://x',
        headerName: 'Authorization',
        hasSecret: true
      })
    ).toEqual(['Connector_Error_Label', 'Connector_Error_Url', 'Connector_Error_HeaderName']);
    expect(
      formProblems({
        label: 'Ledger',
        authKind: 'BasicAuth',
        baseUrl: 'https://api.example.org',
        userName: ' ',
        hasSecret: true
      })
    ).toEqual(['Connector_Error_UserRequired']);
    expect(formProblems({ label: 'Hook', authKind: 'SecretUrl', hasSecret: false })).toEqual([
      'Connector_Error_Url'
    ]);
  });

  it('checks only the key and user name when replacing a key', () => {
    expect(formProblems({ authKind: 'BearerToken', hasSecret: true }, true)).toEqual([]);
    expect(formProblems({ authKind: 'BasicAuth', hasSecret: false }, true)).toEqual([
      'Connector_Error_UserRequired',
      'Connector_Error_KeyRequired'
    ]);
  });

  it('puts the Setup step first in a status', () => {
    expect(statusOf({ calloutsEnabled: false, accessGranted: false }).key).toBe(
      'Connector_Status_CalloutsOff'
    );
    expect(statusOf({ calloutsEnabled: true, accessGranted: false }).key).toBe(
      'Connector_Status_AccessMissing'
    );
    expect(statusOf({ calloutsEnabled: true, accessGranted: true, keyStored: false }).key).toBe(
      'Connector_Status_Disconnected'
    );
    expect(statusOf({ calloutsEnabled: true, accessGranted: true, keyStored: true })).toEqual({
      key: 'Connector_Status_Ready',
      variant: 'success'
    });
  });

  it('turns an answer into an outcome', () => {
    expect(outcomeOf({ outcome: 'answered', status: 200 }).key).toBe('Connector_Outcome_Connected');
    expect(outcomeOf({ outcome: 'answered', status: 401 }).key).toBe(
      'Connector_Outcome_KeyRefused'
    );
    expect(outcomeOf({ outcome: 'answered', status: 403 }).variant).toBe('error');
    expect(outcomeOf({ outcome: 'answered', status: 404 }).key).toBe('Connector_Outcome_Answered');
    expect(outcomeOf({ outcome: 'created' }).key).toBe('Connector_Outcome_Created');
    expect(outcomeOf({ outcome: 'unreachable' }).variant).toBe('error');
    expect(outcomeOf({ outcome: 'other' }).key).toBe('Connector_Error_Unexpected');
    expect(outcomeOf(undefined).key).toBe('Connector_Error_Unexpected');
  });
});
