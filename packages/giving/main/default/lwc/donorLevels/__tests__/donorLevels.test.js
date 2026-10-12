import { createElement } from 'lwc';
import DonorLevels from 'c/donorLevels';
import getLadder from '@salesforce/apex/DonorLevelController.getLadder';
import recalculate from '@salesforce/apex/DonorLevelController.recalculate';

jest.mock(
  '@salesforce/apex/DonorLevelController.getLadder',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock('@salesforce/apex/DonorLevelController.recalculate', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock('@salesforce/apex', () => ({ refreshApex: jest.fn(() => Promise.resolve()) }), {
  virtual: true
});

jest.mock('@salesforce/label/c.Giving_DonorLevels_TopOfLadder', () => ({ default: 'and above' }), {
  virtual: true
});

jest.mock('@salesforce/label/c.Giving_DonorLevels_Inactive', () => ({ default: 'Inactive' }), {
  virtual: true
});

jest.mock(
  '@salesforce/label/c.Giving_DonorLevels_Off',
  () => ({
    default:
      'Donor levels are off. Build your ladder here, then turn Donor levels on in BarnCRM Settings under Giving.'
  }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Giving_DonorLevels_Empty',
  () => ({
    default: 'You have not created any levels yet. Choose New level to add the first rung.'
  }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Giving_DonorLevels_NeverRecalculated',
  () => ({ default: 'Not yet' }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Giving_DonorLevels_RecalculateStarted',
  () => ({ default: 'Placing every donor on the ladder.' }),
  { virtual: true }
);

const LADDER = {
  enabled: true,
  canRecalculate: true,
  sourceFieldLabel: 'Total Giving',
  lastRecalculated: '2026-09-08T02:15:00.000Z',
  rungs: [
    {
      recordId: 'a05000000000001AAA',
      name: 'Friend',
      description: 'Named in the annual report.',
      minimumAmount: 100,
      maximumAmount: 1000,
      active: true,
      donorCount: 42
    },
    {
      recordId: 'a05000000000002AAA',
      name: 'Leadership Circle',
      description: 'Invited to the spring dinner.',
      minimumAmount: 5000,
      maximumAmount: null,
      active: false,
      donorCount: 3
    }
  ]
};

function createComponent() {
  const element = createElement('c-donor-levels', { is: DonorLevels });
  document.body.appendChild(element);
  return element;
}

function flush() {
  return Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());
}

describe('c-donor-levels', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists every rung with the donors on it', async () => {
    const element = createComponent();
    getLadder.emit(LADDER);
    await flush();

    const rows = element.shadowRoot.querySelectorAll('[data-id="rung"]');
    expect(rows.length).toBe(2);
    const counts = element.shadowRoot.querySelectorAll('[data-id="donor-count"]');
    expect(counts[0].textContent).toBe('42');
    expect(counts[1].textContent).toBe('3');
  });

  it('says what the ladder is measured on, in words rather than a field name', async () => {
    const element = createComponent();
    getLadder.emit(LADDER);
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="source-field"]').textContent).toBe(
      'Total Giving'
    );
  });

  it('shows the top rung as having no ceiling and a retired rung as inactive', async () => {
    const element = createComponent();
    getLadder.emit(LADDER);
    await flush();

    const rows = element.shadowRoot.querySelectorAll('[data-id="rung"]');
    expect(rows[1].textContent).toContain('and above');
    const activeCells = element.shadowRoot.querySelectorAll('[data-id="rung-active"]');
    expect(activeCells[0].textContent.trim()).toBe('');
    expect(activeCells[1].textContent.trim()).toBe('Inactive');
  });

  it('stacks the ladder on a small screen, each cell naming its column', async () => {
    const element = createComponent();
    getLadder.emit(LADDER);
    await flush();

    const table = element.shadowRoot.querySelector('table');
    expect(table.classList.contains('slds-max-medium-table_stacked')).toBe(true);
    const firstRow = element.shadowRoot.querySelector('[data-id="rung"]');
    const columns = [...firstRow.querySelectorAll('td')].map((cell) => cell.dataset.label);
    expect(columns).toEqual([
      'c.Giving_DonorLevels_ColumnLevel',
      'c.Giving_DonorLevels_ColumnFrom',
      'c.Giving_DonorLevels_ColumnUpTo',
      'c.Giving_DonorLevels_ColumnDonors',
      'c.Giving_DonorLevels_ColumnActive'
    ]);
  });

  it('says donors have never been placed when nothing has run yet', async () => {
    const element = createComponent();
    getLadder.emit({ ...LADDER, lastRecalculated: null });
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="last-recalculated"]').textContent).toBe(
      'Not yet'
    );
  });

  it('tells the administrator to build the ladder first when there are no rungs', async () => {
    const element = createComponent();
    getLadder.emit({ ...LADDER, rungs: [] });
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="empty-state"]')).not.toBeNull();
  });

  it('says levels are off and refuses to start a recalculation', async () => {
    const element = createComponent();
    getLadder.emit({ ...LADDER, enabled: false });
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="off-notice"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="recalculate"]').disabled).toBe(true);
  });

  it('disables the recalculation for a user who may not change settings', async () => {
    const element = createComponent();
    getLadder.emit({ ...LADDER, canRecalculate: false });
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="recalculate"]').disabled).toBe(true);
  });

  it('starts a recalculation and says it is running', async () => {
    recalculate.mockResolvedValue('707000000000001AAA');
    const element = createComponent();
    getLadder.emit(LADDER);
    await flush();

    element.shadowRoot.querySelector('[data-id="recalculate"]').click();
    await flush();

    expect(recalculate).toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('[data-id="notice-message"]').textContent).toContain(
      'Placing every donor on the ladder.'
    );
  });

  it('shows the message the server sends when a recalculation is refused', async () => {
    recalculate.mockRejectedValue({
      body: { message: 'Turn Donor levels on in BarnCRM Settings under Giving first.' }
    });
    const element = createComponent();
    getLadder.emit(LADDER);
    await flush();

    element.shadowRoot.querySelector('[data-id="recalculate"]').click();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error-message"]').textContent.trim()).toBe(
      'Turn Donor levels on in BarnCRM Settings under Giving first.'
    );
  });

  it('reports a failure to read the ladder', async () => {
    const element = createComponent();
    getLadder.error({ message: 'You do not have access to donor levels.' });
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error-message"]')).not.toBeNull();
  });
});
