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

  it('says why each pair is proposed when the reason is known', async () => {
    const element = await mount(
      viewWith({
        suggestions: [
          { ...PEOPLE_PAIR, reason: 'Same email on Contact Point Email' },
          HOUSEHOLD_PAIR
        ]
      })
    );
    const reasons = qa(element, 'reason');
    expect(reasons).toHaveLength(1);
    expect(reasons[0].textContent.trim()).toBe('Same email on Contact Point Email');
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

  it('shows the preview of the latest choice when an earlier one answers last', async () => {
    const element = await mount(viewWith({ suggestions: [HOUSEHOLD_PAIR] }));
    previewMerge.mockResolvedValueOnce({ fields: [] });
    q(element, 'merge-button').click();
    await flush();
    let answerSlow;
    previewMerge.mockReturnValueOnce(
      new Promise((resolve) => {
        answerSlow = resolve;
      })
    );
    previewMerge.mockResolvedValueOnce({
      fields: [{ fieldName: 'Phone', label: 'Phone', survivorValue: 'B', inConflict: true }]
    });
    const choice = q(element, 'keep-choice');
    choice.dispatchEvent(new CustomEvent('change', { detail: { value: HOUSEHOLD_B } }));
    choice.dispatchEvent(new CustomEvent('change', { detail: { value: HOUSEHOLD_A } }));
    await flush();
    answerSlow({ fields: [] });
    await flush();
    expect(qa(element, 'conflict')).toHaveLength(1);
  });

  it('offers no second scan while one is running', async () => {
    const element = await mount(viewWith({ scanRunning: true }));
    expect(q(element, 'scan-button').disabled).toBe(true);
    expect(q(element, 'scan-running')).not.toBeNull();
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

  describe('a long list', () => {
    const pairs = (count, canMerge) =>
      Array.from({ length: count }, (unused, index) => ({
        setId: `0GK0000000${String(index).padStart(5, '0')}AAA`,
        canMerge,
        records: [
          { recordId: `003${index}A`, name: `Person ${index}`, detail: 'x', isHousehold: false },
          { recordId: `003${index}B`, name: `Person ${index}`, detail: 'x', isHousehold: false }
        ]
      }));

    it('shows ten pairs, the count badge and Show More, then the next ten', async () => {
      const element = await mount(
        viewWith({ suggestions: pairs(25, false), totalSuggestions: 25 })
      );
      expect(qa(element, 'suggestion')).toHaveLength(10);
      expect(q(element, 'count-badge').label).toBe('25');
      expect(q(element, 'showing-count').textContent).toContain('c.Core_Duplicates_ShowingCount');
      expect(q(element, 'show-more')).not.toBeNull();

      q(element, 'show-more').click();
      await flush();
      expect(qa(element, 'suggestion')).toHaveLength(20);
      expect(element.shadowRoot.activeElement).toBe(qa(element, 'record-link')[20]);

      q(element, 'show-more').click();
      await flush();
      expect(qa(element, 'suggestion')).toHaveLength(25);
      expect(q(element, 'show-more')).toBeNull();
      expect(q(element, 'showing-count')).toBeNull();
    });

    it('marks the badge when more are waiting than the server counted', async () => {
      const element = await mount(
        viewWith({ suggestions: pairs(50, true), totalSuggestions: 50, moreNotCounted: true })
      );
      expect(q(element, 'count-badge').label).toBe('50+');
      expect(q(element, 'showing-count').textContent).toContain(
        'c.Core_Duplicates_ShowingCountMore'
      );
    });

    it('gives the people merge note once, not on every pair', async () => {
      const element = await mount(
        viewWith({ suggestions: pairs(12, false), totalSuggestions: 12 })
      );
      expect(qa(element, 'people-notice')).toHaveLength(1);
    });

    it('leaves out the people merge note when every shown pair is households', async () => {
      const element = await mount(viewWith({ suggestions: pairs(3, true), totalSuggestions: 3 }));
      expect(q(element, 'people-notice')).toBeNull();
    });

    it('opens the dismiss box inside the pair it is about', async () => {
      const element = await mount(viewWith({ suggestions: pairs(3, false), totalSuggestions: 3 }));
      qa(element, 'dismiss-button')[1].click();
      await flush();
      const cards = qa(element, 'suggestion');
      expect(cards[1].querySelector('[data-id="dismiss-dialog"]')).not.toBeNull();
      expect(cards[0].querySelector('[data-id="dismiss-dialog"]')).toBeNull();
    });
  });

  it('shows no count badge when nothing is waiting', async () => {
    const element = await mount(viewWith({}));
    expect(q(element, 'count-badge')).toBeNull();
    expect(q(element, 'empty').heading).toBe('c.Core_Duplicates_EmptyHeading');
  });

  it('tells the tab how many pairs are waiting, and again after an action', async () => {
    getView.mockResolvedValue(
      viewWith({ suggestions: [HOUSEHOLD_PAIR], totalSuggestions: 50, moreNotCounted: true })
    );
    dismissSuggestion.mockResolvedValue(viewWith({}));
    const counts = [];
    const element = createElement('c-duplicate-review', { is: DuplicateReview });
    element.addEventListener('countchange', (event) => counts.push(event.detail.count));
    document.body.appendChild(element);
    await flush();
    expect(counts).toEqual(['50+']);

    q(element, 'dismiss-button').click();
    await flush();
    q(element, 'dismiss-confirm').click();
    await flush();
    expect(counts).toEqual(['50+', '']);
  });

  it('shows the two records side by side and marks where the second differs from the first', async () => {
    const field = (fieldName, label, value) => ({ fieldName, label, value });
    const pair = {
      ...PEOPLE_PAIR,
      records: [
        {
          ...PEOPLE_PAIR.records[0],
          fields: [
            field('Email', 'Email', 'ann@example.org'),
            field('Phone', 'Phone', null),
            field('MailingCity', 'Mailing City', 'Springfield')
          ]
        },
        {
          ...PEOPLE_PAIR.records[1],
          fields: [
            field('Email', 'Email', 'ANN@example.org '),
            field('Phone', 'Phone', '555 0100'),
            field('MailingCity', 'Mailing City', 'Shelbyville')
          ]
        }
      ]
    };
    const element = await mount(viewWith({ suggestions: [pair], totalSuggestions: 1 }));

    const sides = qa(element, 'side');
    expect(sides).toHaveLength(2);
    expect(sides[0].className).toContain('slds-medium-size_1-of-2');
    expect(sides[0].className).toContain('slds-size_1-of-1');
    const rows = (side) =>
      Array.from(side.querySelectorAll('[data-id="field"]')).map((row) => ({
        label: row.querySelector('dt').textContent,
        value: row.querySelector('[data-id="value"]').firstChild.textContent.trim(),
        differs: row.querySelector('[data-id="differs"]') !== null
      }));
    // The first record is what the second is compared with, so it carries no marks.
    expect(rows(sides[0])).toEqual([
      { label: 'Email', value: 'ann@example.org', differs: false },
      { label: 'Phone', value: 'c.Core_Duplicates_Blank', differs: false },
      { label: 'Mailing City', value: 'Springfield', differs: false }
    ]);
    // Spaces and capitals aside the emails agree; a phone against a blank differs, as do cities.
    expect(rows(sides[1])).toEqual([
      { label: 'Email', value: 'ANN@example.org', differs: false },
      { label: 'Phone', value: '555 0100', differs: true },
      { label: 'Mailing City', value: 'Shelbyville', differs: true }
    ]);
    expect(sides[1].querySelector('[data-id="differs"]').label).toBe('c.Core_Duplicates_Different');
    expect(sides[1].querySelector('.slds-assistive-text').textContent).toBe(
      'c.Core_Duplicates_DifferentFrom'
    );
    expect(sides[0].querySelector('[data-id="detail"]')).toBeNull();
    expect(q(element, 'compared-with-first')).toBeNull();
  });

  it('compares every record of a larger suggestion with the first, in up to three columns', async () => {
    const field = (value) => [{ fieldName: 'BillingPostalCode', label: 'Zip', value }];
    const records = ['A', 'B', 'C', 'D'].map((letter, index) => ({
      ...HOUSEHOLD_PAIR.records[0],
      recordId: `001${letter}`,
      name: `The ${letter} Family`,
      fields: field(index === 2 ? '18150' : '18149')
    }));
    const element = await mount(
      viewWith({ suggestions: [{ ...HOUSEHOLD_PAIR, records }], totalSuggestions: 1 })
    );

    const sides = qa(element, 'side');
    expect(sides).toHaveLength(4);
    expect(sides[0].className).toContain('slds-large-size_1-of-3');
    // Two records holding the first one's zip are not marked; only the one that differs is.
    expect(
      Array.from(sides).map((side) => side.querySelector('[data-id="differs"]') !== null)
    ).toEqual([false, false, true, false]);
    expect(q(element, 'compared-with-first').textContent.trim()).toBe(
      'c.Core_Duplicates_ComparedWithFirst'
    );
  });

  it('falls back to the one-line detail when the server sends no compared fields', async () => {
    const element = await mount(viewWith({ suggestions: [HOUSEHOLD_PAIR], totalSuggestions: 1 }));
    const sides = qa(element, 'side');
    expect(sides[0].querySelector('[data-id="detail"]').textContent).toBe('Springfield');
    expect(sides[0].querySelector('[data-id="field"]')).toBeNull();
    expect(q(element, 'merge-button').variant).toBe('brand');
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
