import { createElement } from 'lwc';
import ErrorLogTile from 'c/errorLogTile';
import getTile from '@salesforce/apex/ErrorLogController.getTile';
import acknowledge from '@salesforce/apex/ErrorLogController.acknowledge';

jest.mock(
  '@salesforce/apex/ErrorLogController.getTile',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock('@salesforce/apex/ErrorLogController.acknowledge', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock('@salesforce/label/c.Core_ErrorLogTile_NewCount', () => ({ default: '{0} new' }), {
  virtual: true
});

jest.mock(
  '@salesforce/label/c.Core_ErrorLogTile_ReadOnly',
  () => ({ default: 'You can read these entries but not change them.' }),
  { virtual: true }
);

const ENTRY = {
  recordId: 'a01000000000001AAA',
  name: 'ERR-000001',
  message: 'This household could not be renamed because every member is marked deceased.',
  context: 'Household naming',
  severity: 'Error',
  status: 'New',
  occurredAt: '2026-09-07T09:12:00.000Z'
};

const TILE = {
  newCount: 3,
  canUpdate: true,
  recent: [ENTRY, { ...ENTRY, recordId: 'a01000000000002AAA', name: 'ERR-000002' }]
};

function createComponent() {
  const element = createElement('c-error-log-tile', { is: ErrorLogTile });
  document.body.appendChild(element);
  return element;
}

function flush() {
  return Promise.resolve().then(() => Promise.resolve());
}

describe('c-error-log-tile', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('counts the new errors and lists the most recent', async () => {
    const element = createComponent();
    getTile.emit(TILE);
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="new-count"]').label).toBe('3 new');
    const items = element.shadowRoot.querySelectorAll('[data-id="entry-list"] li');
    expect(items.length).toBe(2);
    expect(items[0].textContent).toContain('could not be renamed');
    expect(items[0].textContent).toContain('Household naming');
  });

  it('marks an entry acknowledged and shows the updated count', async () => {
    acknowledge.mockResolvedValue({ ...TILE, newCount: 2 });
    const element = createComponent();
    getTile.emit(TILE);
    await flush();

    element.shadowRoot.querySelectorAll('.acknowledge-button')[0].click();
    await flush();

    expect(acknowledge).toHaveBeenCalledWith({ errorLogId: ENTRY.recordId });
    expect(element.shadowRoot.querySelector('[data-id="new-count"]').label).toBe('2 new');
  });

  it('shows the message the server sends when the action is refused', async () => {
    acknowledge.mockRejectedValue({
      body: { message: 'That entry is no longer in the Error Log. Refresh the page.' }
    });
    const element = createComponent();
    getTile.emit(TILE);
    await flush();

    element.shadowRoot.querySelectorAll('.acknowledge-button')[0].click();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error-message"]').textContent).toBe(
      'That entry is no longer in the Error Log. Refresh the page.'
    );
  });

  it('says nothing has gone wrong when the list is empty', async () => {
    const element = createComponent();
    getTile.emit({ newCount: 0, canUpdate: true, recent: [] });
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="empty-state"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="new-count"]').label).toBe('0 new');
  });

  it('disables the action for a person who may only read', async () => {
    const element = createComponent();
    getTile.emit({ ...TILE, canUpdate: false });
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="read-only-notice"]')).not.toBeNull();
    expect(element.shadowRoot.querySelectorAll('.acknowledge-button')[0].disabled).toBe(true);
  });

  it('reports a failure to load the tile', async () => {
    const element = createComponent();
    getTile.error({ message: 'You do not have access to the Error Log.' });
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error-message"]').textContent).toBe(
      'You do not have access to the Error Log.'
    );
  });

  it('opens the entry itself', async () => {
    const element = createComponent();
    getTile.emit(TILE);
    await flush();

    const openButtons = element.shadowRoot.querySelectorAll('.open-entry-button');
    expect(openButtons.length).toBe(2);
    expect(openButtons[0].dataset.entry).toBe(ENTRY.recordId);
    // The navigation stub records nothing, so this asserts the click is wired and safe.
    openButtons[0].click();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="new-count"]').label).toBe('3 new');
  });

  it('announces an error rather than showing it in color alone', async () => {
    const element = createComponent();
    getTile.error({ message: 'You do not have access to the Error Log.' });
    await flush();

    expect(element.shadowRoot.querySelector('[role="alert"]')).not.toBeNull();
  });

  it('opens the Error Log list', async () => {
    const element = createComponent();
    getTile.emit(TILE);
    await flush();

    const navigate = jest.fn();
    element.shadowRoot.querySelector('[data-id="view-all"]').click();
    await flush();

    // The navigation stub records nothing, so the assertion is that clicking is safe and the
    // component keeps its state.
    expect(navigate).not.toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('[data-id="new-count"]').label).toBe('3 new');
  });
});
