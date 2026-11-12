import tabApiNames from '@salesforce/apex/NamespaceUtil.tabApiNames';
import { loadTabNames, tabApiName, tabPageReference } from 'c/barnTabs';

jest.mock(
  '@salesforce/apex/NamespaceUtil.tabApiNames',
  () => ({
    default: jest.fn((params) =>
      Promise.resolve(Object.fromEntries(params.tabs.map((t) => [t, `barn__${t}`])))
    )
  }),
  { virtual: true }
);

describe('c/barnTabs', () => {
  it('opens a tab by the name Apex qualified, asking once per tab', async () => {
    expect(tabApiName('Find')).toBe('Find');
    const reference = await tabPageReference('Find', { c__x: '1' });
    expect(reference).toEqual({
      type: 'standard__navItemPage',
      attributes: { apiName: 'barn__Find' },
      state: { c__x: '1' }
    });
    await loadTabNames(['Find', 'Import']);
    expect(tabApiNames).toHaveBeenCalledTimes(2);
    expect(tabApiNames).toHaveBeenLastCalledWith({ tabs: ['Import'] });
    expect(tabApiName('Import')).toBe('barn__Import');
  });

  it('keeps the name as written when Apex fails', async () => {
    tabApiNames.mockImplementationOnce(() => Promise.reject(new Error('offline')));
    const reference = await tabPageReference('Receipts');
    expect(reference).toEqual({
      type: 'standard__navItemPage',
      attributes: { apiName: 'Receipts' }
    });
  });
});
