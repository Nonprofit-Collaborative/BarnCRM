import { setTabIcon, setTabLabel } from 'lightning/platformWorkspaceApi';
import { labelTab } from 'c/rollupTabLabel';

jest.mock(
  'lightning/platformWorkspaceApi',
  () => ({ setTabIcon: jest.fn(), setTabLabel: jest.fn(), EnclosingTabId: jest.fn() }),
  { virtual: true }
);

describe('c/rollupTabLabel', () => {
  afterEach(() => {
    setTabLabel.mockReset();
    setTabIcon.mockReset();
  });

  it('does nothing outside a console or without a label', async () => {
    expect(await labelTab({ enclosingTabId: null }, 'Rollups')).toBe(false);
    expect(await labelTab({ enclosingTabId: 'tab1' }, '')).toBe(false);
    expect(await labelTab(undefined, 'Rollups')).toBe(false);
    expect(setTabLabel).not.toHaveBeenCalled();
  });

  it('names the tab and sets its icon once, then skips an unchanged call', async () => {
    setTabLabel.mockResolvedValue(undefined);
    setTabIcon.mockResolvedValue(undefined);
    const host = { enclosingTabId: 'tab1' };
    expect(await labelTab(host, 'Rollups', 'custom:custom9')).toBe(true);
    expect(await labelTab(host, 'Rollups', 'custom:custom9')).toBe(true);
    expect(setTabLabel).toHaveBeenCalledTimes(1);
    expect(setTabLabel).toHaveBeenCalledWith('tab1', 'Rollups');
    expect(setTabIcon).toHaveBeenCalledWith('tab1', 'custom:custom9', { iconAlt: 'Rollups' });
  });

  it('asks again after a failure, and sets no icon when none is given', async () => {
    setTabLabel.mockRejectedValueOnce(new Error('no console'));
    const host = { enclosingTabId: 'tab2' };
    expect(await labelTab(host, 'Rollups')).toBe(false);
    setTabLabel.mockResolvedValue(undefined);
    expect(await labelTab(host, 'Rollups')).toBe(true);
    expect(setTabLabel).toHaveBeenCalledTimes(2);
    expect(setTabIcon).not.toHaveBeenCalled();
  });
});
