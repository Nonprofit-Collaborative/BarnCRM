import { concentration, fill, revenueMix, shareOf, showShare, sources } from 'c/fundersBoardModel';

const WORDS = { notSet: 'Not set', gifts: 'Gifts to funds' };

const BOARD = {
  grantsBySource: [
    { key: 'Federal', name: 'Federal', amount: 40000 },
    { key: null, name: null, amount: 10000 }
  ],
  grantsByFunder: [
    { key: 'a1', name: 'Lakeside Foundation', amount: 30000 },
    { key: 'a2', name: 'State Agency', amount: 20000 }
  ],
  givingAvailable: true,
  giftsThisYear: 50000,
  givingByAccount: [
    { key: 'a1', name: 'Lakeside Foundation', amount: 5000 },
    { key: 'a3', name: 'Corner Bakery', amount: 1000 }
  ]
};

describe('fundersBoardModel', () => {
  it('builds the revenue mix with gifts and a blank source', () => {
    const mix = revenueMix(BOARD, WORDS);
    expect(mix.total).toBe(100000);
    expect(mix.rows.map((row) => [row.name, row.share])).toEqual([
      ['Gifts to funds', 0.5],
      ['Federal', 0.4],
      ['Not set', 0.1]
    ]);
    expect(revenueMix({ ...BOARD, givingAvailable: false }, WORDS).total).toBe(50000);
    expect(revenueMix(null, WORDS)).toEqual({ rows: [], total: 0 });
  });

  it('joins grants and giving by organization', () => {
    expect(sources(BOARD).map((source) => [source.name, source.amount])).toEqual([
      ['Lakeside Foundation', 35000],
      ['State Agency', 20000],
      ['Corner Bakery', 1000]
    ]);
    expect(sources({ ...BOARD, givingAvailable: false })).toHaveLength(2);
  });

  it('flags one large source and a concentrated top five', () => {
    const spread = concentration(BOARD, 100000);
    expect(spread.largest.name).toBe('Lakeside Foundation');
    expect(spread.largest.share).toBeCloseTo(0.35);
    expect(spread.singleRisk).toBe(true);
    expect(spread.topFiveShare).toBeCloseTo(0.56);
    expect(spread.topFiveRisk).toBe(true);

    const spreadOut = concentration(
      { grantsByFunder: [{ key: 'x', name: 'X', amount: 10 }], givingAvailable: false },
      100
    );
    expect(spreadOut.singleRisk).toBe(false);
    expect(spreadOut.topFiveRisk).toBe(false);
    expect(concentration({}, 0)).toEqual({
      top: [],
      largest: null,
      topFiveShare: 0,
      singleRisk: false,
      topFiveRisk: false
    });
  });

  it('shows shares and fills text', () => {
    expect(shareOf(5, 0)).toBe(0);
    expect(shareOf('abc', 10)).toBe(0);
    expect(showShare(0.425, 'en-US')).toBe('43%');
    expect(fill('{0} gives {1} {2}', ['A', '30%'])).toBe('A gives 30% {2}');
  });
});
