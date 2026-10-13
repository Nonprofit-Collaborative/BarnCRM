import { createElement } from 'lwc';
import DuplicateReview from 'c/duplicateReview';
import getView from '@salesforce/apex/DuplicateController.getView';
import startScan from '@salesforce/apex/DuplicateController.startScan';
import dismissSuggestion from '@salesforce/apex/DuplicateController.dismiss';
import previewMerge from '@salesforce/apex/DuplicateController.previewMerge';
import mergeHouseholds from '@salesforce/apex/DuplicateController.mergeHouseholds';
import { EnclosingTabId, getTabInfo, openSubtab } from 'lightning/platformWorkspaceApi';

jest.mock('@salesforce/apex/DuplicateController.getView', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/DuplicateController.startScan', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/DuplicateController.dismiss', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/DuplicateController.previewMerge', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/DuplicateController.mergeHouseholds', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/customPermission/Manage_BarnCRM_Settings', () => ({ default: true }), {
  virtual: true
});
jest.mock(
  '@salesforce/schema/Duplicate_Dismissal__c',
  () => ({ default: { objectApiName: 'Duplicate_Dismissal__c' } }),
  { virtual: true }
);

const HOUSEHOLD_A = '001000000000001AAA';
const HOUSEHOLD_B = '001000000000002AAA';

function viewWith(overrides) {
  return {
    canManage: true,
    anyRuleActive: true,
    rules: [{ objectName: 'Contact', ruleLabel: 'Standard Contact Duplicate Rule', active: true }],
    suggestions: [],
    dismissedCount: 0,
    scanRunning: false,
    lastScanFinished: null,
    canReviewSuggestions: true,
    totalSuggestions: 0,
    moreNotCounted: false,
    lastScanSummary: null,
    lastScanHadFailures: false,
    ...overrides
  };
}

const HOUSEHOLD_PAIR = {
  setId: '0GK000000000001AAA',
  canMerge: true,
  records: [
    { recordId: HOUSEHOLD_A, name: 'The Smith Family', detail: 'Springfield', isHousehold: true },
    { recordId: HOUSEHOLD_B, name: 'The Smith Family', detail: 'Springfield', isHousehold: true }
  ]
};

const PEOPLE_PAIR = {
  setId: '0GK000000000002AAA',
  canMerge: false,
  records: [
    {
      recordId: '003000000000001AAA',
      name: 'Ann Lee',
      detail: 'ann@example.org',
      isHousehold: false
    },
    {
      recordId: '003000000000002AAA',
      name: 'Ann Lee',
      detail: 'ann@example.org',
      isHousehold: false
    }
  ]
};

async function flush() {
  for (let i = 0; i < 5; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
}

async function mount(view) {
  getView.mockResolvedValue(view);
  const element = createElement('c-duplicate-review', { is: DuplicateReview });
  document.body.appendChild(element);
  await flush();
  return element;
}

const q = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);
const qa = (element, id) => element.shadowRoot.querySelectorAll(`[data-id="${id}"]`);

describe('c-duplicate-review', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('says so when no duplicate rule is on, rather than showing an empty list as clean', async () => {
    const element = await mount(viewWith({ anyRuleActive: false, rules: [] }));
    expect(q(element, 'no-rules')).not.toBeNull();
    expect(q(element, 'setup-link').getAttribute('href')).toBe(
      '/lightning/setup/DuplicateRules/home'
    );
  });

  it('lists each rule with whether it is on', async () => {
    const element = await mount(viewWith({}));
    const rules = qa(element, 'rule');
    expect(rules).toHaveLength(1);
    expect(rules[0].textContent).toContain('Standard Contact Duplicate Rule');
    expect(q(element, 'no-rules')).toBeNull();
  });

  it('says so when the license gives no access to suggestions, and offers no action', async () => {
    const element = await mount(viewWith({ canReviewSuggestions: false }));
    expect(q(element, 'no-access').textContent).toContain(
      'c.Core_Duplicates_NoSuggestionAccessNotice'
    );
    expect(q(element, 'empty')).toBeNull();
    expect(q(element, 'scan-button').disabled).toBe(true);
  });

  it('says how many are shown only when more are waiting than are listed', async () => {
    const all = await mount(viewWith({ suggestions: [HOUSEHOLD_PAIR], totalSuggestions: 1 }));
    expect(q(all, 'showing-count')).toBeNull();
    document.body.removeChild(all);

    const some = await mount(viewWith({ suggestions: [HOUSEHOLD_PAIR], totalSuggestions: 120 }));
    expect(q(some, 'showing-count').textContent).toContain('c.Core_Duplicates_ShowingCount');
  });

  it('shows the last scan line, marked when a chunk could not be checked', async () => {
    const element = await mount(
      viewWith({
        lastScanSummary: 'Scan finished: 1 chunk not checked.',
        lastScanHadFailures: true
      })
    );
    const line = q(element, 'last-scan-summary');
    expect(line.textContent).toBe('Scan finished: 1 chunk not checked.');
    expect(line.classList.contains('slds-text-color_error')).toBe(true);
  });

  it('shows the empty message when nothing is waiting', async () => {
    const element = await mount(viewWith({}));
    expect(q(element, 'empty')).not.toBeNull();
    expect(qa(element, 'suggestion')).toHaveLength(0);
  });

  it('offers a household merge for households and the platform merge note for people', async () => {
    const element = await mount(viewWith({ suggestions: [HOUSEHOLD_PAIR, PEOPLE_PAIR] }));
    expect(qa(element, 'suggestion')).toHaveLength(2);
    expect(qa(element, 'merge-button')).toHaveLength(1);
    expect(qa(element, 'people-notice')).toHaveLength(1);
    expect(qa(element, 'dismiss-button')).toHaveLength(2);
  });

  it('starts a scan and says it started', async () => {
    const element = await mount(viewWith({}));
    startScan.mockResolvedValue(viewWith({ scanRunning: true }));
    q(element, 'scan-button').click();
    await flush();
    expect(startScan).toHaveBeenCalled();
    expect(q(element, 'notice').textContent).toContain('c.Core_Duplicates_ScanStarted');
    expect(q(element, 'scan-running')).not.toBeNull();
  });

  it('shows the reason a scan was refused', async () => {
    const element = await mount(viewWith({}));
    startScan.mockRejectedValue({ body: { message: 'No duplicate rule is switched on.' } });
    q(element, 'scan-button').click();
    await flush();
    expect(q(element, 'error').textContent).toContain('No duplicate rule is switched on.');
  });

  it('dismisses a pair with the reason typed', async () => {
    const element = await mount(viewWith({ suggestions: [PEOPLE_PAIR] }));
    dismissSuggestion.mockResolvedValue(viewWith({ dismissedCount: 1 }));
    q(element, 'dismiss-button').click();
    await flush();
    const reason = q(element, 'dismiss-reason');
    reason.value = 'Twins';
    reason.dispatchEvent(new CustomEvent('change'));
    q(element, 'dismiss-confirm').click();
    await flush();
    expect(dismissSuggestion).toHaveBeenCalledWith({
      duplicateRecordSetId: PEOPLE_PAIR.setId,
      reason: 'Twins'
    });
    expect(q(element, 'view-dismissed')).not.toBeNull();
    expect(q(element, 'empty')).not.toBeNull();
  });

  it('previews and merges two households, keeping the first by default', async () => {
    const element = await mount(viewWith({ suggestions: [HOUSEHOLD_PAIR] }));
    previewMerge.mockResolvedValue({
      fields: [
        {
          fieldName: 'Phone',
          label: 'Phone',
          survivorValue: '1',
          victimValue: '2',
          inConflict: true
        },
        {
          fieldName: 'Name',
          label: 'Name',
          survivorValue: 'A',
          victimValue: 'A',
          inConflict: false
        }
      ]
    });
    mergeHouseholds.mockResolvedValue(viewWith({}));
    q(element, 'merge-button').click();
    await flush();
    expect(previewMerge).toHaveBeenCalledWith({ survivorId: HOUSEHOLD_A, victimId: HOUSEHOLD_B });
    expect(qa(element, 'conflict')).toHaveLength(1);
    q(element, 'merge-confirm').click();
    await flush();
    expect(mergeHouseholds).toHaveBeenCalledWith({
      duplicateRecordSetId: HOUSEHOLD_PAIR.setId,
      survivorId: HOUSEHOLD_A,
      victimId: HOUSEHOLD_B,
      fieldChoices: {}
    });
    expect(q(element, 'merge-dialog')).toBeNull();
    expect(q(element, 'notice').textContent).toContain('c.Core_Duplicates_MergeSuccess');
  });

  it('keeps the other household when the person changes the choice', async () => {
    const element = await mount(viewWith({ suggestions: [HOUSEHOLD_PAIR] }));
    previewMerge.mockResolvedValue({ fields: [] });
    q(element, 'merge-button').click();
    await flush();
    q(element, 'keep-choice').dispatchEvent(
      new CustomEvent('change', { detail: { value: HOUSEHOLD_B } })
    );
    await flush();
    expect(previewMerge).toHaveBeenLastCalledWith({
      survivorId: HOUSEHOLD_B,
      victimId: HOUSEHOLD_A
    });
  });

  it('opens the dismiss box as a labelled region and moves focus to its heading', async () => {
    const element = await mount(viewWith({ suggestions: [PEOPLE_PAIR] }));
    q(element, 'dismiss-button').click();
    await flush();
    const box = q(element, 'dismiss-dialog');
    expect(box.getAttribute('role')).toBe('region');
    expect(box.hasAttribute('aria-modal')).toBe(false);
    expect(element.shadowRoot.activeElement).toBe(q(element, 'dismiss-heading'));
  });

  it('closes a dialog on cancel', async () => {
    const element = await mount(viewWith({ suggestions: [PEOPLE_PAIR] }));
    q(element, 'dismiss-button').click();
    await flush();
    const cancel = q(element, 'dismiss-dialog').querySelectorAll('lightning-button')[1];
    cancel.click();
    await flush();
    expect(q(element, 'dismiss-dialog')).toBeNull();
  });

  it('shows a plain message when loading fails without one', async () => {
    getView.mockRejectedValue({});
    const element = createElement('c-duplicate-review', { is: DuplicateReview });
    document.body.appendChild(element);
    await flush();
    expect(q(element, 'error').textContent).toContain('c.Core_Duplicates_ErrorUnexpected');
  });

  it('lets the browser open a suggested record outside a console', async () => {
    const element = await mount(viewWith({ suggestions: [HOUSEHOLD_PAIR], totalSuggestions: 1 }));
    const event = new MouseEvent('click', { bubbles: true, cancelable: true });
    qa(element, 'record-link')[0].dispatchEvent(event);
    await flush();

    expect(event.defaultPrevented).toBe(false);
    expect(openSubtab).not.toHaveBeenCalled();
  });

  it('opens a suggested record as a subtab in a console', async () => {
    getTabInfo.mockResolvedValueOnce({ tabId: 'tab0', isSubtab: false });
    const element = await mount(viewWith({ suggestions: [HOUSEHOLD_PAIR], totalSuggestions: 1 }));
    EnclosingTabId.emit('tab0');
    await flush();

    const event = new MouseEvent('click', { bubbles: true, cancelable: true });
    qa(element, 'record-link')[1].dispatchEvent(event);
    await flush();

    expect(event.defaultPrevented).toBe(true);
    expect(openSubtab).toHaveBeenCalledWith('tab0', { recordId: HOUSEHOLD_B, focus: true });
  });
});
