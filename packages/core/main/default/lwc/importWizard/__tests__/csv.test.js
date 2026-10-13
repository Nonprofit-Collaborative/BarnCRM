import { parseCsv, toRecords, toCsv, detectDelimiter } from '../csv';

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
  });

  describe('the separator', () => {
    it('splits on the separator it is given, keeping one inside quotes', () => {
      expect(parseCsv('a;b\n"x;y";2', ';')).toEqual([
        ['a', 'b'],
        ['x;y', '2']
      ]);
      expect(parseCsv('a\tb\n1\t2', '\t')[1]).toEqual(['1', '2']);
      expect(parseCsv('a|b\n1|2', '|')[1]).toEqual(['1', '2']);
    });

    it('reads as commas when given a separator it does not offer', () => {
      expect(parseCsv('a,b', ':')).toEqual([['a', 'b']]);
    });

    it('detects semicolons, tabs and pipes, and commas by default', () => {
      expect(detectDelimiter('Name;Amount\nRamirez;12,50\nOkafor;3,00')).toBe(';');
      expect(detectDelimiter('Name\tEmail\nAna\tana@example.org')).toBe('\t');
      expect(detectDelimiter('Name|Email\nAna|ana@example.org')).toBe('|');
      expect(detectDelimiter('Name,Email\nAna,ana@example.org')).toBe(',');
      expect(detectDelimiter('Email\nana@example.org')).toBe(',');
      expect(detectDelimiter('')).toBe(',');
    });

    it('ignores a separator inside quotes when detecting', () => {
      expect(detectDelimiter('Name,Note\n"Ramirez; Ana","a; b; c"\nOkafor,x')).toBe(',');
    });

    it('prefers the separator that gives every row the header width', () => {
      // Three columns by semicolon in the header only; two by comma on every row.
      expect(detectDelimiter('a,b;c;d\n1,2\n3,4\n5,6')).toBe(',');
    });

    it('stops after the rows it was asked for', () => {
      expect(parseCsv('a\n1\n2\n3', ',', 2)).toEqual([['a'], ['1']]);
    });
  });

  describe('writing the exceptions file', () => {
    it('quotes only what has to be quoted', () => {
      const text = toCsv(['Row', 'Reason'], [{ Row: 2, Reason: 'Missing, last name' }]);
      expect(text).toBe('Row,Reason\r\n2,"Missing, last name"');
    });

    it('survives a round trip', () => {
      const headers = ['Name', 'Note'];
      const records = [{ Name: 'Ramirez, Ana', Note: 'She said "hi"' }];
      const again = toRecords(parseCsv(toCsv(headers, records))).records;
      expect(again).toEqual(records);
    });
  });
});
