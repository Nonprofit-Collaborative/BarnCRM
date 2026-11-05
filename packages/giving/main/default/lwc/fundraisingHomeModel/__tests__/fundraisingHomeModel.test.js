import { badgeStatusFor, pageReferenceFor, toTiles, valueFor } from 'c/fundraisingHomeModel';

describe('fundraisingHomeModel', () => {
  it('keeps the status color only while there is something to act on', () => {
    expect(badgeStatusFor({ badgeLabel: 'Overdue', badgeStatus: 'overdue', count: 3 })).toBe(
      'overdue'
    );
    expect(badgeStatusFor({ badgeLabel: 'Overdue', badgeStatus: 'overdue', count: 0 })).toBe(
      'neutral'
    );
    expect(badgeStatusFor({ count: 4 })).toBeUndefined();
  });

  it('shows the count, or the cap with a plus past it', () => {
    expect(valueFor({ count: 7 })).toBe(7);
    expect(valueFor({ count: 2000, capped: true }, 'en-US')).toBe('2,000+');
    expect(valueFor({})).toBe(0);
  });

  it('opens a tab page or a list view', () => {
    expect(pageReferenceFor({ tabName: 'Acknowledgments' })).toEqual({
      type: 'standard__navItemPage',
      attributes: { apiName: 'Acknowledgments' }
    });
    expect(pageReferenceFor({ objectApiName: 'Installment__c', filterName: 'Overdue' })).toEqual({
      type: 'standard__objectPage',
      attributes: { objectApiName: 'Installment__c', actionName: 'list' },
      state: { filterName: 'Overdue' }
    });
    expect(pageReferenceFor(undefined)).toBeNull();
  });

  it('maps each figure for the stat tile with its own tab icon', () => {
    const icon = jest.fn((name) => `custom:${name}`);
    const [tile] = toTiles(
      [
        {
          name: 'openBatches',
          label: 'Gift Batches',
          count: 2,
          badgeLabel: 'Open',
          badgeStatus: 'info',
          objectApiName: 'Gift_Batch__c'
        }
      ],
      icon
    );
    expect(tile).toEqual({
      name: 'openBatches',
      label: 'Gift Batches',
      value: 2,
      badgeLabel: 'Open',
      badgeVariant: 'info',
      iconName: 'custom:Gift_Batch__c'
    });
    expect(toTiles(null, icon)).toEqual([]);
  });
});
