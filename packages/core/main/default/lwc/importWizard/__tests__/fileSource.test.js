import { readFileSheets } from '../fileSource';
import { readSheetNames, readXlsx } from '../xlsx';

jest.mock('../xlsx', () => {
  const actual = jest.requireActual('../xlsx');
  return { ...actual, readSheetNames: jest.fn(), readXlsx: jest.fn() };
});

describe('fileSource', () => {
  it('reads a text file as one unnamed sheet, detecting its separator', async () => {
    const file = new File(['﻿Name;Email\nAna;ana@example.org'], 'people.csv');
    const { sheets, delimiter } = await readFileSheets(file);
    expect(delimiter).toBe(';');
    expect(sheets).toHaveLength(1);
    expect(sheets[0].name).toBe('');
    expect(sheets[0].rows[1]).toEqual(['Ana', 'ana@example.org']);
  });

  it('keeps a separator the user chose', async () => {
    const file = new File(['Name;Email\nAna;ana@example.org'], 'people.csv');
    const { sheets, delimiter } = await readFileSheets(file, { delimiter: ',' });
    expect(delimiter).toBe(',');
    expect(sheets[0].rows[0]).toEqual(['Name;Email']);
  });

  it('reads every sheet of a workbook, in tab order', async () => {
    readSheetNames.mockResolvedValueOnce(['People', 'Shifts']);
    readXlsx.mockResolvedValueOnce([['Name'], ['Ana']]).mockResolvedValueOnce([['Shift']]);
    const { sheets } = await readFileSheets(new File(['zip'], 'Book.XLSX'));
    expect(sheets).toEqual([
      { name: 'People', rows: [['Name'], ['Ana']] },
      { name: 'Shifts', rows: [['Shift']] }
    ]);
    expect(readXlsx).toHaveBeenLastCalledWith(expect.anything(), { sheet: 'Shifts' });
  });
});
