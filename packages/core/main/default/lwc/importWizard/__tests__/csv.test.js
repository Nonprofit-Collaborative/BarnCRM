import { parseCsv, toRecords, withoutFormulaGuard } from '../csv';
import { toCsv } from 'c/findCsv';

describe('the CSV reader', () => {
  it('reads a plain file', () => {
    expect(parseCsv('a,b\n1,2')).toEqual([
      ['a', 'b'],
      ['1', '2']
    ]);
  });

  it('keeps commas and line breaks that are inside quotes', () => {
    const rows = parseCsv('Name,Address\n"Ramirez, Ana","12 Oak St\nPortland"');
    expect(rows[1][0]).toBe('Ramirez, Ana');
    expect(rows[1][1]).toBe('12 Oak St\nPortland');
  });

  it('reads a doubled quote as one quote', () => {
    expect(parseCsv('Name\n"She said ""hello"""')[1][0]).toBe('She said "hello"');
  });

  it('reads both line ending conventions', () => {
    expect(parseCsv('a,b\r\n1,2\r\n3,4')).toHaveLength(3);
  });

  it('drops the byte order mark Excel writes', () => {
    expect(parseCsv('﻿Email\nana@example.org')[0][0]).toBe('Email');
  });

  it('drops trailing blank lines', () => {
    expect(parseCsv('a\n1\n\n\n')).toEqual([['a'], ['1']]);
  });

  it('reads nothing from nothing', () => {
    expect(parseCsv('')).toEqual([]);
    expect(parseCsv(null)).toEqual([]);
  });

  describe('turning rows into records', () => {
    it('keys each row by the heading above it', () => {
      const { headers, records } = toRecords(parseCsv('First Name,Email\nAna,ana@example.org'));
      expect(headers).toEqual(['First Name', 'Email']);
      expect(records).toEqual([{ 'First Name': 'Ana', Email: 'ana@example.org' }]);
    });

    it('names a column with no heading by its position, so it is visible in the picker', () => {
      const { headers } = toRecords(parseCsv('Email,,Phone\na,b,c'));
      expect(headers[1]).toBe('Column 2');
    });

    it('fills in a short row rather than losing the columns after it', () => {
      const { records } = toRecords(parseCsv('A,B,C\n1,2'));
      expect(records[0]).toEqual({ A: '1', B: '2', C: '' });
    });

    it('trims the values', () => {
      const { records } = toRecords(parseCsv('Email\n  ana@example.org  '));
      expect(records[0].Email).toBe('ana@example.org');
    });

    it('skips a blank row in the middle of the file', () => {
      const { records } = toRecords(parseCsv('Email\nana@example.org\n\nben@example.org'));
      expect(records).toHaveLength(2);
    });

    it('reads a header row with no data under it as no records', () => {
      const { headers, records } = toRecords(parseCsv('Email'));
      expect(headers).toEqual(['Email']);
      expect(records).toEqual([]);
    });

    it('takes off the one quote a Find export puts before = + - or @, and nothing else', () => {
      const values = ['+44 20 7946 0000', '-', '@handle', '=SUM(A1)', "'quoted", "it's", 'plain'];
      const exported = toCsv(
        [{ label: 'Value', path: 'Value' }],
        values.map((value) => ({ Value: value }))
      );
      expect(exported).toContain("'+44 20 7946 0000");
      const { records } = toRecords(parseCsv(exported));
      expect(records.map((record) => record.Value)).toEqual(values);
      expect(withoutFormulaGuard("''+1")).toBe("''+1");
    });
  });

  describe('reading back the exceptions file', () => {
    it('survives a round trip through the shared CSV writer, byte-order mark and all', () => {
      const columns = [
        { label: 'Name', path: 'Name' },
        { label: 'Note', path: 'Note' },
        { label: 'Amount', path: 'Amount' }
      ];
      const records = [{ Name: 'Muñoz, Ana', Note: 'She said "hi"', Amount: '-25.00' }];
      const parsed = toRecords(parseCsv(toCsv(columns, records)));
      expect(parsed.headers).toEqual(['Name', 'Note', 'Amount']);
      expect(parsed.records).toEqual(records);
    });
  });
});
