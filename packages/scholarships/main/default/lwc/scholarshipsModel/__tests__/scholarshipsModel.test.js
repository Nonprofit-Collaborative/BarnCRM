import { csvCell, toCsv, weightedTotal } from 'c/scholarshipsModel';

describe('c-scholarships-model', () => {
  const criteria = [
    { key: 'need', max: 10, weight: 2 },
    { key: 'essay', max: 10, weight: 1 }
  ];

  it('weighs and caps scores like Apex', () => {
    expect(weightedTotal(criteria, { need: 8, essay: '6' })).toBe(22);
    expect(weightedTotal(criteria, { need: 15, essay: -3 })).toBe(20);
    expect(weightedTotal(criteria, {})).toBe(0);
    expect(weightedTotal(null, null)).toBe(0);
  });

  it('quotes cells and neutralizes formulas', () => {
    expect(csvCell('a,b')).toBe('"a,b"');
    expect(csvCell('say "hi"')).toBe('"say ""hi"""');
    expect(csvCell('=SUM(A1)')).toBe("'=SUM(A1)");
    expect(csvCell('-5')).toBe('-5');
    expect(csvCell(null)).toBe('');
  });

  it('writes a heading and one line per row', () => {
    const csv = toCsv(
      [{ name: 'DSB-1', amount: 500 }],
      [
        ['name', 'Disbursement'],
        ['amount', 'Amount']
      ]
    );
    expect(csv).toBe('Disbursement,Amount\r\nDSB-1,500\r\n');
  });
});
