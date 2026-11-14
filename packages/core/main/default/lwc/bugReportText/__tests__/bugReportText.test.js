import { bugReportText, isStatusCode, safeParts, utcMinute } from 'c/bugReportText';

const WORDS = {
  heading: 'BarnCRM bug report.',
  where: 'Where',
  object: 'Object',
  severity: 'Severity',
  when: 'When',
  times: 'Times it happened',
  codes: 'Error codes',
  stack: 'Where in the code',
  none: 'none',
  noDetail: 'Technical detail: not included.'
};

const DETAIL = [
  "System.DmlException: Insert failed. First exception on row 0; first error: FIELD_CUSTOM_VALIDATION_EXCEPTION, 'Ana Ortiz' (ana@example.org, 555-0100) needs an amount: [Amount__c]",
  'Class.barn.GiftService.save: line 120, column 1',
  'Trigger.GiftTrigger: line 3, column 1',
  'Class.barn.GiftService.save: line 120, column 1'
].join('\n');

describe('c/bugReportText', () => {
  it('keeps only error codes, exception types and stack lines', () => {
    const parts = safeParts(DETAIL);
    expect(parts.codes).toEqual(['FIELD_CUSTOM_VALIDATION_EXCEPTION']);
    expect(parts.exceptions).toEqual(['System.DmlException']);
    expect(parts.stack).toEqual([
      'Class.barn.GiftService.save: line 120, column 1',
      'Trigger.GiftTrigger: line 3, column 1'
    ]);
    expect(safeParts(undefined)).toEqual({ codes: [], exceptions: [], stack: [] });
  });

  it('writes a report with no name, email, phone or field value in it', () => {
    const text = bugReportText(
      {
        context: 'GiftService.save',
        severity: 'Error',
        occurredAt: '2026-09-07T09:12:30.000Z',
        occurrences: 4,
        objectName: 'Gift__c',
        technicalDetail: DETAIL
      },
      WORDS
    );
    expect(text).toContain('Where: GiftService.save');
    expect(text).toContain('When: 2026-09-07 09:12 UTC');
    expect(text).toContain('Times it happened: 4');
    expect(text).toContain('Error codes: System.DmlException, FIELD_CUSTOM_VALIDATION_EXCEPTION');
    expect(text).toContain('  Trigger.GiftTrigger: line 3, column 1');
    for (const secret of ['Ana', 'Ortiz', 'ana@example.org', '555-0100', 'Amount__c', 'row 0']) {
      expect(text).not.toContain(secret);
    }
  });

  it('says what is missing when there is no detail to read', () => {
    const text = bugReportText({ context: 'Find' }, WORDS);
    expect(text).toContain('Object: none');
    expect(text).toContain('Times it happened: 1');
    expect(text).toContain('Error codes: none');
    expect(text).toContain('Technical detail: not included.');
    expect(bugReportText(undefined, WORDS)).toContain('Where: none');
  });

  it('keeps only Salesforce status codes, never a value written in capitals', () => {
    const parts = safeParts(
      'first error: INVALID_EMAIL_ADDRESS, STRING_TOO_LONG, UNABLE_TO_LOCK_ROW, ' +
        'REQUIRED_FIELD_MISSING, INSUFFICIENT_ACCESS_OR_READONLY, LIMIT_EXCEEDED, ' +
        'APEX_ERROR for ANA_ORTIZ at ACME_CORP_HQ with PO_12345'
    );
    expect(parts.codes).toEqual([
      'INVALID_EMAIL_ADDRESS',
      'STRING_TOO_LONG',
      'UNABLE_TO_LOCK_ROW',
      'REQUIRED_FIELD_MISSING',
      'INSUFFICIENT_ACCESS_OR_READONLY',
      'LIMIT_EXCEEDED',
      'APEX_ERROR'
    ]);
    for (const value of ['ANA_ORTIZ', 'ACME_CORP_HQ', 'PO_12345']) {
      expect(isStatusCode(value)).toBe(false);
    }
  });

  it('gives no time for a missing or unreadable one', () => {
    expect(utcMinute(undefined)).toBe('');
    expect(utcMinute('not a date')).toBe('');
  });
});
