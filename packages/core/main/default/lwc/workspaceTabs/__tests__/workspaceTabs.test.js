import { openInWorkspace, labelTab, refreshEnclosingTab } from 'c/workspaceTabs';
import {
  getTabInfo,
  openSubtab,
  refreshTab,
  setTabIcon,
  setTabLabel
} from 'lightning/platformWorkspaceApi';

describe('c/workspaceTabs', () => {
  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('outside a console app', () => {
    const host = { enclosingTabId: null };

    it('leaves record opening to the caller', async () => {
      await expect(openInWorkspace(host, { recordId: '001000000000001AAA' })).resolves.toBe(false);
      expect(openSubtab).not.toHaveBeenCalled();
    });

    it('does not touch any tab', async () => {
      await expect(labelTab(host, 'Find', 'utility:search')).resolves.toBe(false);
      await expect(refreshEnclosingTab(host)).resolves.toBe(false);
      expect(setTabLabel).not.toHaveBeenCalled();
      expect(setTabIcon).not.toHaveBeenCalled();
      expect(refreshTab).not.toHaveBeenCalled();
    });
  });

  describe('in a console app', () => {
    it('opens a record as a subtab of the workspace tab', async () => {
      getTabInfo.mockResolvedValueOnce({ tabId: 'tab0', isSubtab: false });

      const opened = await openInWorkspace(
        { enclosingTabId: 'tab0' },
        { recordId: '001000000000001AAA' }
      );

      expect(opened).toBe(true);
      expect(openSubtab).toHaveBeenCalledWith('tab0', {
        recordId: '001000000000001AAA',
        focus: true
      });
    });

    it('opens beside the caller when the caller is itself a subtab', async () => {
      getTabInfo.mockResolvedValueOnce({ tabId: 'tab0_1', isSubtab: true, parentTabId: 'tab0' });

      await openInWorkspace({ enclosingTabId: 'tab0_1' }, { url: '/lightning/r/X/a01/view' });

      expect(openSubtab).toHaveBeenCalledWith('tab0', {
        url: '/lightning/r/X/a01/view',
        focus: true
      });
    });

    it('hands back to the caller when the console refuses', async () => {
      openSubtab.mockRejectedValueOnce(new Error('no workspace'));

      await expect(openInWorkspace({ enclosingTabId: 'tab0' }, { recordId: '001' })).resolves.toBe(
        false
      );
    });

    it('names the tab once per label', async () => {
      const host = { enclosingTabId: 'tab0' };

      await labelTab(host, 'Find', 'utility:search');
      await labelTab(host, 'Find', 'utility:search');

      expect(setTabLabel).toHaveBeenCalledTimes(1);
      expect(setTabLabel).toHaveBeenCalledWith('tab0', 'Find');
      expect(setTabIcon).toHaveBeenCalledWith('tab0', 'utility:search', { iconAlt: 'Find' });

      await labelTab(host, 'Find: Contacts', 'utility:search');
      expect(setTabLabel).toHaveBeenLastCalledWith('tab0', 'Find: Contacts');
    });

    it('tries again after the console failed to name the tab', async () => {
      const host = { enclosingTabId: 'tab0' };
      setTabLabel.mockRejectedValueOnce(new Error('busy'));

      await expect(labelTab(host, 'Find', 'utility:search')).resolves.toBe(false);
      await expect(labelTab(host, 'Find', 'utility:search')).resolves.toBe(true);
      expect(setTabLabel).toHaveBeenCalledTimes(2);
    });

    it('refreshes the tab the component sits in', async () => {
      await expect(refreshEnclosingTab({ enclosingTabId: 'tab0' })).resolves.toBe(true);
      expect(refreshTab).toHaveBeenCalledWith('tab0', { includeAllSubtabs: false });
    });

    it('reports a refresh the console refused', async () => {
      refreshTab.mockRejectedValueOnce(new Error('gone'));
      await expect(refreshEnclosingTab({ enclosingTabId: 'tab0' })).resolves.toBe(false);
    });
  });
});
