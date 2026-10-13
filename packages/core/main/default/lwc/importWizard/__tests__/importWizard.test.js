import { createElement } from 'lwc';
import ImportWizard from 'c/importWizard';
import canImport from '@salesforce/apex/ImportController.canImport';
import getTemplates from '@salesforce/apex/ImportController.getTemplates';
import suggestMapping from '@salesforce/apex/ImportController.suggestMapping';
import saveFile from '@salesforce/apex/ImportController.saveFile';
import createBatch from '@salesforce/apex/ImportController.createBatch';
import stageRows from '@salesforce/apex/ImportController.stageRows';
import startDryRun from '@salesforce/apex/ImportController.startDryRun';
import startCommit from '@salesforce/apex/ImportController.startCommit';
import getBatch from '@salesforce/apex/ImportController.getBatch';
import getRows from '@salesforce/apex/ImportController.getRows';
import saveRecurring from '@salesforce/apex/ImportController.saveRecurring';
import getEntityTargets from '@salesforce/apex/ImportController.getEntityTargets';
import getMatchFields from '@salesforce/apex/ImportController.getMatchFields';
import getLoadableObjects from '@salesforce/apex/ImportController.getLoadableObjects';
import createObjectTemplate from '@salesforce/apex/ImportController.createObjectTemplate';
import getObjectFields from '@salesforce/apex/ImportController.getObjectFields';
import getKeyFields from '@salesforce/apex/ImportController.getKeyFields';
import getChangedValues from '@salesforce/apex/ImportController.getChangedValues';
import previewChanges from '@salesforce/apex/ImportController.previewChanges';
import { EnclosingTabId, setTabIcon, setTabLabel } from 'lightning/platformWorkspaceApi';

jest.mock('@salesforce/label/c.Core_Console_TabLabel', () => ({ default: '{0}: {1}' }), {
  virtual: true
});

// Real label values, so a test can see a column target built from its two labels.
jest.mock(
  '@salesforce/label/c.Core_Import_TargetSecondPersonField',
  () => ({ default: 'Second person: {0}' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_Import_TargetOrganizationField',
  () => ({ default: 'Organization: {0}' }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Core_Import_FieldEmail', () => ({ default: 'email' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_Import_FieldName', () => ({ default: 'name' }), {
  virtual: true
});

jest.mock('@salesforce/apex/ImportController.canImport', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.getTemplates', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.suggestMapping', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.saveFile', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.createBatch', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.stageRows', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.startDryRun', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.startCommit', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.getBatch', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.saveRecurring', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.getRows', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.getEntityTargets', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.getMatchFields', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.getLoadableObjects', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/ImportController.createObjectTemplate',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/ImportController.getObjectFields', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.getKeyFields', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.getChangedValues', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.previewChanges', () => ({ default: jest.fn() }), {
  virtual: true
});

const TEMPLATE = {
  id: 'a01',
  name: 'Generic contact list',
  description: 'A list of people with their contact details.',
  matchingRule: 'Email exact',
  personMode: 'Contacts',
  mapping: '{"version":1,"columns":[]}',
  isPackageDefault: true
};

const DRY_RUN_BATCH = {
  id: 'a02',
  name: 'IB-000001',
  status: 'Dry run complete',
  isDryRun: true,
  isFinished: true,
  rowCount: 2,
  created: 2,
  updated: 0,
  matched: 0,
  rejected: 0,
  runLog: 'Dry run. Nothing was written.'
};

const FILE_TEXT = 'Last Name,Email,Notes\nRamirez,ana@example.org,vip\nOkafor,ben@example.org,';

/**
 * Lets every pending promise and rerender settle. Several turns, because reading a file goes
 * through FileReader, which resolves on its own task.
 */
async function flush(turns = 5) {
  for (let i = 0; i < turns; i++) {
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
}

function render() {
  const element = createElement('c-import-wizard', { is: ImportWizard });
  document.body.appendChild(element);
  return element;
}

/** Feeds the wizard a file the way the browser's file input does. */
async function chooseFile(element, text = FILE_TEXT, name = 'donors.csv') {
  const input = element.shadowRoot.querySelector('[data-id="file"]');
  const file = new File([text], name, { type: 'text/csv' });
  Object.defineProperty(input, 'files', { value: [file], configurable: true });
  input.dispatchEvent(new CustomEvent('change'));
  await flush();
}

function click(element, id) {
  element.shadowRoot.querySelector(`[data-id="${id}"]`).click();
}

describe('the import wizard', () => {
  beforeEach(() => {
    canImport.mockResolvedValue(true);
    getTemplates.mockResolvedValue([TEMPLATE]);
    suggestMapping.mockResolvedValue(
      JSON.stringify({
        version: 1,
        columns: [
          { source: 'Last Name', target: 'Contact1.LastName' },
          { source: 'Email', target: 'Contact1.Email' },
          { source: 'Notes', target: 'Ignore' }
        ]
      })
    );
    saveFile.mockResolvedValue('069000000000001');
    createBatch.mockResolvedValue(DRY_RUN_BATCH);
    stageRows.mockResolvedValue(2);
    startDryRun.mockResolvedValue(DRY_RUN_BATCH);
    startCommit.mockResolvedValue({ ...DRY_RUN_BATCH, status: 'Complete', isDryRun: false });
    getBatch.mockResolvedValue(DRY_RUN_BATCH);
    getRows.mockResolvedValue([]);
    getEntityTargets.mockResolvedValue([]);
    getMatchFields.mockResolvedValue({ contact: [], account: [] });
    getChangedValues.mockResolvedValue([]);
    previewChanges.mockResolvedValue({ problems: [], samples: [] });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('offers the templates it was given', async () => {
    const element = render();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="template"]').options).toEqual([
      { label: 'Generic contact list', value: 'a01' }
    ]);
  });

  it('asks for the templates, columns and match fields together, not one after another', async () => {
    getTemplates.mockReturnValue(new Promise(() => {}));
    render();
    await flush();
    expect(getTemplates).toHaveBeenCalledTimes(1);
    expect(getEntityTargets).toHaveBeenCalledTimes(1);
    expect(getMatchFields).toHaveBeenCalledTimes(1);
  });

  it('tells a user without the permission who to ask', async () => {
    canImport.mockResolvedValue(false);
    const element = render();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="read-only"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="template"]')).toBeNull();
  });

  it('saves the recurring mark and its source name before leaving the first step', async () => {
    saveRecurring.mockResolvedValue(undefined);
    const element = render();
    await flush();
    const box = element.shadowRoot.querySelector('[data-id="recurring"]');
    box.checked = true;
    box.dispatchEvent(new CustomEvent('change'));
    await flush();
    const name = element.shadowRoot.querySelector('[data-id="source-name"]');
    name.value = 'Monthly processor export';
    name.dispatchEvent(new CustomEvent('change'));
    click(element, 'next');
    await flush();

    expect(saveRecurring).toHaveBeenCalledWith({
      templateId: 'a01',
      isRecurring: true,
      sourceName: 'Monthly processor export'
    });
    expect(element.shadowRoot.querySelector('[data-id="file"]')).not.toBeNull();
  });

  it('stays on the first step and says why when the recurring mark is refused', async () => {
    saveRecurring.mockRejectedValue({ body: { message: 'Give this file a source name.' } });
    const element = render();
    await flush();
    const box = element.shadowRoot.querySelector('[data-id="recurring"]');
    box.checked = true;
    box.dispatchEvent(new CustomEvent('change'));
    await flush();
    click(element, 'next');
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="template"]')).not.toBeNull();
    expect(element.shadowRoot.textContent).toContain('Give this file a source name.');
  });

  it('does not save anything when the recurring mark is left alone', async () => {
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    expect(saveRecurring).not.toHaveBeenCalled();
  });

  it('shows the chosen template description so the choice can be checked', async () => {
    const element = render();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="template-help"]').textContent).toContain(
      'A list of people'
    );
  });

  it('shows a row of the column picker for every column in the file', async () => {
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    const rows = element.shadowRoot.querySelectorAll('[data-id="column-row"]');
    expect(rows).toHaveLength(3);
    expect(rows[0].textContent).toContain('Last Name');
    expect(
      element.shadowRoot.querySelector('[data-id="columns-table"]').getAttribute('aria-label')
    ).toBe('c.Core_Import_StepColumns');
    // Outside a console the tab is left as it is.
    expect(setTabLabel).not.toHaveBeenCalled();
  });

  it('names the console tab for the file being imported', async () => {
    const element = render();
    EnclosingTabId.emit('tab0');
    await flush();
    expect(setTabLabel).toHaveBeenLastCalledWith('tab0', 'c.Core_Import_TabLabel');
    expect(setTabIcon).toHaveBeenCalledWith('tab0', 'standard:file', {
      iconAlt: 'c.Core_Import_TabLabel'
    });

    click(element, 'next');
    await flush();
    await chooseFile(element);

    expect(setTabLabel).toHaveBeenLastCalledWith('tab0', 'c.Core_Import_TabLabel: donors.csv');
  });

  it('shows the first values of each column beside the choice', async () => {
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    const rows = element.shadowRoot.querySelectorAll('[data-id="column-row"]');
    expect(rows[0].textContent).toContain('Ramirez, Okafor');
  });

  it('names each column target from custom labels, so the picker can be translated', async () => {
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    const options = element.shadowRoot.querySelector(
      '[data-id="column-row"] lightning-combobox'
    ).options;
    expect(options).toContainEqual({ value: 'Contact2.Email', label: 'Second person: email' });
    expect(options).toContainEqual({
      value: 'Household.Name',
      label: 'c.Core_Import_TargetHouseholdField'
    });
  });

  it('refuses a file with no rows under its heading', async () => {
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element, 'Last Name,Email');
    // Labels are stubbed by their identifier under jest; the wording itself lives in
    // Import.labels-meta.xml and is quoted in the admin guide.
    expect(element.shadowRoot.querySelector('[data-id="message"]').textContent).toBe(
      'c.Core_Import_NoHeaderRow'
    );
    expect(element.shadowRoot.querySelectorAll('[data-id="column-row"]')).toHaveLength(0);
  });

  it('reads a file named .xlsx as a workbook, and says so when it is not one', async () => {
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element, 'not really a workbook', 'donors.xlsx');
    expect(element.shadowRoot.querySelector('[data-id="message"]').textContent).toBe(
      'c.Core_Import_XlsxUnreadable'
    );
    expect(element.shadowRoot.querySelectorAll('[data-id="column-row"]')).toHaveLength(0);
  });

  it('explains what the chosen matching rule risks', async () => {
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    click(element, 'next');
    await flush();
    const help = element.shadowRoot.querySelector('[data-id="rule-help"]');
    expect(help.textContent).toBe('c.Core_Import_MatchingEmailHelp');
  });

  it('writes nothing before the dry run', async () => {
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    click(element, 'next');
    await flush();
    expect(createBatch).not.toHaveBeenCalled();
    expect(startDryRun).not.toHaveBeenCalled();
  });

  it('stages the file in pages and then dry runs it', async () => {
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    click(element, 'next');
    await flush();
    click(element, 'dry-run');
    await flush();

    expect(createBatch).toHaveBeenCalledTimes(1);
    expect(stageRows).toHaveBeenCalledTimes(1);
    // The first data row of a file is row two, because row one is the heading.
    expect(stageRows.mock.calls[0][0].firstRowNumber).toBe(2);
    expect(JSON.parse(stageRows.mock.calls[0][0].rowsJson)).toHaveLength(2);
    expect(startDryRun).toHaveBeenCalledWith({ batchId: 'a02' });
    expect(element.shadowRoot.querySelector('[data-id="results"]')).not.toBeNull();
  });

  it('sends the mapping the administrator settled on, not the suggestion alone', async () => {
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    const picker = element.shadowRoot.querySelectorAll('[data-id="column-row"] lightning-combobox');
    picker[2].dispatchEvent(new CustomEvent('change', { detail: { value: 'Contact1.Phone' } }));
    await flush();
    click(element, 'next');
    await flush();
    click(element, 'dry-run');
    await flush();

    const sent = JSON.parse(createBatch.mock.calls[0][0].mappingDocument);
    expect(sent.columns[2]).toEqual({ source: 'Notes', target: 'Contact1.Phone' });
  });

  it('commits only after the dry run has completed', async () => {
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    click(element, 'next');
    await flush();
    click(element, 'dry-run');
    await flush();

    const commit = element.shadowRoot.querySelector('[data-id="commit"]');
    expect(commit.disabled).toBe(false);
    commit.click();
    await flush();
    expect(startCommit).toHaveBeenCalledWith({ batchId: 'a02' });
  });

  it('leaves the commit button disabled while the dry run is still going', async () => {
    startDryRun.mockResolvedValue({ ...DRY_RUN_BATCH, status: 'Dry run', isFinished: false });
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    click(element, 'next');
    await flush();
    click(element, 'dry-run');
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="commit"]').disabled).toBe(true);
  });

  it('reports a server failure in words rather than swallowing it', async () => {
    getTemplates.mockRejectedValue({ body: { message: 'That mapping no longer exists.' } });
    const element = render();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="message"]').textContent).toBe(
      'That mapping no longer exists.'
    );
  });

  it('goes back to the start without leaving the last run on the screen', async () => {
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    click(element, 'next');
    await flush();
    click(element, 'dry-run');
    await flush();
    element.shadowRoot.querySelector('[data-id="commit"]').click();
    await flush();
    click(element, 'start-over');
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="template"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="results"]')).toBeNull();
  });

  /** Walks to the matching step with the default file. */
  async function toMatchingStep() {
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    click(element, 'next');
    await flush();
    return element;
  }

  function type(element, id, value) {
    const input = element.shadowRoot.querySelector(`[data-id="${id}"]`);
    input.value = value;
    input.dispatchEvent(new CustomEvent('change'));
  }

  it('sends the control totals with the batch, and none when the boxes are empty', async () => {
    let element = await toMatchingStep();
    // No module reads gift amounts here, so only the row count is offered.
    expect(element.shadowRoot.querySelector('[data-id="expected-amount"]')).toBeNull();
    type(element, 'expected-count', '2');
    await flush();
    click(element, 'dry-run');
    await flush();
    expect(JSON.parse(createBatch.mock.calls[0][0].optionsJson)).toEqual({
      expectedCount: 2,
      expectedAmount: null,
      matching: {
        personMatchField: null,
        organizationRule: 'Name exact',
        organizationMatchField: null,
        severalMatches: 'Reject the row'
      }
    });

    document.body.removeChild(element);
    createBatch.mockClear();
    element = await toMatchingStep();
    click(element, 'dry-run');
    await flush();
    expect(JSON.parse(createBatch.mock.calls[0][0].optionsJson)).toEqual({
      expectedCount: null,
      expectedAmount: null,
      matching: {
        personMatchField: null,
        organizationRule: 'Name exact',
        organizationMatchField: null,
        severalMatches: 'Reject the row'
      }
    });
  });

  it('offers the gift columns an installed module loads, and the amount control total', async () => {
    getEntityTargets.mockResolvedValue([{ value: 'Gift.Amount__c', label: 'Gift: amount' }]);
    suggestMapping.mockResolvedValue(
      JSON.stringify({
        version: 1,
        columns: [
          { source: 'Last Name', target: 'Contact1.LastName' },
          { source: 'Email', target: 'Contact1.Email' },
          { source: 'Notes', target: 'Gift.Amount__c' }
        ]
      })
    );
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    const picker = element.shadowRoot.querySelector('[data-id="column-row"] lightning-combobox');
    const labels = picker.options.map((option) => option.label);
    expect(labels).toContain('Gift: amount');
    expect(labels).not.toContain('Gift: amount (kept with the row, not loaded yet)');
    click(element, 'next');
    await flush();
    type(element, 'expected-amount', '125.50');
    await flush();
    click(element, 'dry-run');
    await flush();
    expect(JSON.parse(createBatch.mock.calls[0][0].optionsJson).expectedAmount).toBe(125.5);
  });

  it('offers no gift column without a module, and leaves a suggested one unloaded', async () => {
    suggestMapping.mockResolvedValue(
      JSON.stringify({
        version: 1,
        columns: [
          { source: 'Last Name', target: 'Contact1.LastName' },
          { source: 'Email', target: 'Contact1.Email' },
          { source: 'Notes', target: 'Gift.Amount__c' }
        ]
      })
    );
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    const pickers = element.shadowRoot.querySelectorAll(
      '[data-id="column-row"] lightning-combobox'
    );
    const labels = pickers[0].options.map((option) => option.label);
    expect(labels.some((label) => label.startsWith('Gift'))).toBe(false);
    expect(pickers[2].value).toBe('Ignore');
    expect(pickers[0].value).toBe('Contact1.LastName');
  });

  it('shows how gifts match scheduled payments, from the template, and saves the choice', async () => {
    getEntityTargets.mockResolvedValue([{ value: 'Gift.Amount__c', label: 'Gift: amount' }]);
    getTemplates.mockResolvedValue([
      { ...TEMPLATE, paymentMatching: 'Match only', matchDateWindowDays: 3 }
    ]);
    suggestMapping.mockResolvedValue(
      JSON.stringify({
        version: 1,
        columns: [
          { source: 'Last Name', target: 'Contact1.LastName' },
          { source: 'Email', target: 'Contact1.Email' },
          { source: 'Notes', target: 'Gift.Amount__c' }
        ]
      })
    );
    const element = await toMatchingStep();
    const choice = element.shadowRoot.querySelector('[data-id="payment-matching"]');
    expect(choice.value).toBe('Match only');
    expect(element.shadowRoot.querySelector('[data-id="match-window"]').value).toBe('3');
    choice.dispatchEvent(new CustomEvent('change', { detail: { value: 'Never match' } }));
    type(element, 'match-tolerance', '0.50');
    await flush();
    click(element, 'dry-run');
    await flush();
    expect(JSON.parse(createBatch.mock.calls[0][0].optionsJson)).toEqual({
      expectedCount: null,
      expectedAmount: null,
      matching: {
        personMatchField: null,
        organizationRule: 'Name exact',
        organizationMatchField: null,
        severalMatches: 'Reject the row'
      },
      savePaymentMatching: true,
      paymentMatching: 'Never match',
      matchDateWindowDays: 3,
      matchAmountTolerance: 0.5
    });
  });

  it('does not offer payment matching where no module loads gifts', async () => {
    const element = await toMatchingStep();
    expect(element.shadowRoot.querySelector('[data-id="payment-matching"]')).toBeNull();
    click(element, 'dry-run');
    await flush();
    expect(
      JSON.parse(createBatch.mock.calls[0][0].optionsJson).savePaymentMatching
    ).toBeUndefined();
  });

  it('will not commit a file that disagrees with its control totals, and can go back', async () => {
    const disagrees = { ...DRY_RUN_BATCH, controlTotalsAgree: false };
    createBatch.mockResolvedValue(disagrees);
    startDryRun.mockResolvedValue(disagrees);
    getBatch.mockResolvedValue(disagrees);
    const element = await toMatchingStep();
    click(element, 'dry-run');
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="commit"]').disabled).toBe(true);
    click(element, 'back');
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="expected-count"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="results"]')).toBeNull();
  });

  it('asks for the ID field under External ID, and warns when no column holds it', async () => {
    getMatchFields.mockResolvedValue({
      contact: [{ value: 'Member_Number__c', label: 'Member Number' }],
      account: []
    });
    const element = await toMatchingStep();
    expect(element.shadowRoot.querySelector('[data-id="person-field"]')).toBeNull();
    const rule = element.shadowRoot.querySelector('[data-id="rule"]');
    rule.dispatchEvent(new CustomEvent('change', { detail: { value: 'External ID' } }));
    await flush();
    const field = element.shadowRoot.querySelector('[data-id="person-field"]');
    expect(field.value).toBe('Member_Number__c');
    expect(element.shadowRoot.querySelector('[data-id="person-field-warning"]').textContent).toBe(
      'c.Core_Import_MatchFieldNotMapped'
    );
    click(element, 'dry-run');
    await flush();
    const sent = JSON.parse(createBatch.mock.calls[0][0].optionsJson);
    expect(sent.matching.personMatchField).toBe('Member_Number__c');
    expect(createBatch.mock.calls[0][0].matchingRule).toBe('External ID');
  });

  it('offers each ID field as a column for either person and the organization', async () => {
    getMatchFields.mockResolvedValue({
      contact: [{ value: 'Member_Number__c', label: 'Member Number' }],
      account: [{ value: 'Charity_Number__c', label: 'Charity Number' }]
    });
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    const picker = element.shadowRoot.querySelector('[data-id="column-row"] lightning-combobox');
    const values = picker.options.map((option) => option.value);
    expect(values).toEqual(
      expect.arrayContaining([
        'Contact1.Member_Number__c',
        'Contact2.Member_Number__c',
        'Organization.Charity_Number__c'
      ])
    );
  });

  it('offers record ID columns and the org own fields, each once', async () => {
    getMatchFields.mockResolvedValue({
      contact: [{ value: 'Member_Number__c', label: 'Member Number' }],
      account: [],
      personFields: [
        { value: 'Department', label: 'Department' },
        { value: 'Member_Number__c', label: 'Member Number' }
      ],
      organizationFields: [
        { value: 'Industry', label: 'Industry' },
        { value: 'Name', label: 'Account Name' }
      ]
    });
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    const picker = element.shadowRoot.querySelector('[data-id="column-row"] lightning-combobox');
    const values = picker.options.map((option) => option.value);
    expect(values).toEqual(
      expect.arrayContaining([
        'Contact1.Id',
        'Contact2.Id',
        'Organization.Id',
        'Contact1.Department',
        'Contact2.Department',
        'Organization.Industry'
      ])
    );
    expect(values.filter((value) => value === 'Contact1.Member_Number__c')).toHaveLength(1);
    const names = picker.options.filter((option) => option.value === 'Organization.Name');
    expect(names).toHaveLength(1);
    expect(names[0].label).toBe('Organization: name');
  });

  it('sends Match only when ticked, and never offers a person ID as a value for every row', async () => {
    const element = await toMatchingStep();
    const matchOnly = element.shadowRoot.querySelector('[data-id="match-only"]');
    expect(matchOnly.checked).toBe(false);
    matchOnly.checked = true;
    matchOnly.dispatchEvent(new CustomEvent('change'));
    click(element, 'add-file-value');
    await flush();
    const offered = element.shadowRoot
      .querySelector('[data-id="file-value-row"] lightning-combobox')
      .options.map((option) => option.value);
    expect(offered).not.toContain('Contact1.Id');
    expect(offered).not.toContain('Contact2.Id');
    expect(offered).toContain('Organization.Id');
    click(element, 'dry-run');
    await flush();
    expect(JSON.parse(createBatch.mock.calls[0][0].optionsJson).matchOnly).toBe(true);
  });

  it('will not dry run under External ID when no field can be matched on, and says why', async () => {
    getTemplates.mockResolvedValue([{ ...TEMPLATE, matchingRule: 'External ID' }]);
    const element = await toMatchingStep();
    expect(element.shadowRoot.querySelector('[data-id="no-person-fields"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="dry-run"]').disabled).toBe(true);
  });

  it('shows each matching rule by its label and stores the rule name', async () => {
    const element = await toMatchingStep();
    expect(element.shadowRoot.querySelector('[data-id="rule"]').options).toEqual([
      { label: 'c.Core_Import_RuleEmailExact', value: 'Email exact' },
      { label: 'c.Core_Import_RuleNamePostalCode', value: 'Name plus postal code' },
      { label: 'c.Core_Import_RuleExternalId', value: 'External ID' }
    ]);
  });

  it('offers the organization rule only where the file names an organization', async () => {
    let element = await toMatchingStep();
    expect(element.shadowRoot.querySelector('[data-id="organization-rule"]')).toBeNull();
    document.body.removeChild(element);

    suggestMapping.mockResolvedValue(
      JSON.stringify({
        version: 1,
        columns: [
          { source: 'Last Name', target: 'Contact1.LastName' },
          { source: 'Email', target: 'Contact1.Email' },
          { source: 'Notes', target: 'Organization.Name' }
        ]
      })
    );
    element = await toMatchingStep();
    const rule = element.shadowRoot.querySelector('[data-id="organization-rule"]');
    expect(rule.value).toBe('Name exact');
    expect(rule.options.map((option) => option.label)).toEqual([
      'c.Core_Import_RuleNameExact',
      'c.Core_Import_RuleExternalId'
    ]);
    expect(element.shadowRoot.querySelector('[data-id="organization-rule-help"]').textContent).toBe(
      'c.Core_Import_OrganizationNameHelp'
    );
  });

  it('rejects several matches by default, says what each choice risks, and sends the choice', async () => {
    const element = await toMatchingStep();
    const several = element.shadowRoot.querySelector('[data-id="several-matches"]');
    expect(several.value).toBe('Reject the row');
    expect(element.shadowRoot.querySelector('[data-id="several-help"]').textContent).toBe(
      'c.Core_Import_SeveralRejectHelp'
    );
    several.dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Use the most recently changed' } })
    );
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="several-help"]').textContent).toBe(
      'c.Core_Import_SeveralRecentHelp'
    );
    click(element, 'dry-run');
    await flush();
    expect(JSON.parse(createBatch.mock.calls[0][0].optionsJson).matching.severalMatches).toBe(
      'Use the most recently changed'
    );
  });

  it('sends values for every row, never offers a person name for one, and drops blanks', async () => {
    const element = await toMatchingStep();
    click(element, 'add-file-value');
    await flush();
    click(element, 'add-file-value');
    await flush();
    const rows = element.shadowRoot.querySelectorAll('[data-id="file-value-row"]');
    expect(rows).toHaveLength(2);
    const target = rows[0].querySelector('lightning-combobox');
    const offered = target.options.map((option) => option.value);
    expect(offered).toContain('Contact1.MailingCity');
    expect(offered).toContain('Organization.Name');
    expect(offered).not.toContain('Contact1.LastName');
    expect(offered).not.toContain('Contact2.Email');
    expect(offered).not.toContain('Ignore');
    target.dispatchEvent(new CustomEvent('change', { detail: { value: 'Contact1.MailingCity' } }));
    const input = rows[0].querySelector('lightning-input');
    input.value = ' Portland ';
    input.dispatchEvent(new CustomEvent('change'));
    await flush();
    click(element, 'dry-run');
    await flush();
    expect(JSON.parse(createBatch.mock.calls[0][0].optionsJson).fileValues).toEqual([
      { target: 'Contact1.MailingCity', value: 'Portland' }
    ]);
  });

  it('removes a value for every row', async () => {
    const element = await toMatchingStep();
    click(element, 'add-file-value');
    await flush();
    element.shadowRoot.querySelector('[data-id="file-value-row"] lightning-button-icon').click();
    await flush();
    expect(element.shadowRoot.querySelectorAll('[data-id="file-value-row"]')).toHaveLength(0);
  });

  it('edits a column changes, shows how many, and sends them with the mapping', async () => {
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    const buttons = element.shadowRoot.querySelectorAll('[data-id="edit-changes"]');
    expect(buttons[0].label).toBe('c.Core_Import_ChangesButton');
    buttons[0].click();
    await flush();
    const panel = element.shadowRoot.querySelector('[data-id="column-changes"]');
    expect(panel.source).toBe('Last Name');
    expect(panel.columnNames).toEqual(['Last Name', 'Email', 'Notes']);
    expect(panel.sampleRows).toHaveLength(2);
    panel.dispatchEvent(
      new CustomEvent('change', {
        detail: { source: 'Last Name', transforms: [{ op: 'trim' }, { op: 'proper' }] }
      })
    );
    panel.dispatchEvent(new CustomEvent('done'));
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="column-changes"]')).toBeNull();
    expect(element.shadowRoot.querySelectorAll('[data-id="edit-changes"]')[0].label).toBe(
      'c.Core_Import_ChangesButtonCount'
    );
    click(element, 'next');
    await flush();
    click(element, 'dry-run');
    await flush();
    const sent = JSON.parse(createBatch.mock.calls[0][0].mappingDocument);
    expect(sent.columns[0]).toEqual({
      source: 'Last Name',
      target: 'Contact1.LastName',
      transforms: [{ op: 'trim' }, { op: 'proper' }]
    });
    expect(sent.columns[1].transforms).toBeUndefined();
  });

  it('starts from the changes the mapping already holds', async () => {
    suggestMapping.mockResolvedValue(
      JSON.stringify({
        version: 1,
        columns: [
          { source: 'Last Name', target: 'Contact1.LastName' },
          { source: 'Email', target: 'Contact1.Email', transforms: [{ op: 'lower' }] }
        ]
      })
    );
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    const buttons = element.shadowRoot.querySelectorAll('[data-id="edit-changes"]');
    expect(buttons[1].label).toBe('c.Core_Import_ChangesButtonCount');
    buttons[1].click();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="column-changes"]').transforms).toEqual([
      { op: 'lower' }
    ]);
  });

  it('sends the duplicate rules choice, and warns when no rule is switched on', async () => {
    getMatchFields.mockResolvedValue({ contact: [], account: [], contactRules: false });
    const element = await toMatchingStep();
    const box = element.shadowRoot.querySelector('[data-id="duplicate-rules"]');
    expect(box.checked).toBe(false);
    expect(element.shadowRoot.querySelector('[data-id="duplicate-rules-none"]')).toBeNull();
    box.checked = true;
    box.dispatchEvent(new CustomEvent('change'));
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="duplicate-rules-none"]')).not.toBeNull();
    click(element, 'dry-run');
    await flush();
    expect(JSON.parse(createBatch.mock.calls[0][0].optionsJson).matching.useDuplicateRules).toBe(
      true
    );
  });

  it('starts with the duplicate rules choice the mapping holds', async () => {
    getTemplates.mockResolvedValue([{ ...TEMPLATE, useDuplicateRules: true }]);
    getMatchFields.mockResolvedValue({ contact: [], account: [], contactRules: true });
    const element = await toMatchingStep();
    expect(element.shadowRoot.querySelector('[data-id="duplicate-rules"]').checked).toBe(true);
    expect(element.shadowRoot.querySelector('[data-id="duplicate-rules-none"]')).toBeNull();
  });

  it('shows the values a finished dry run changed', async () => {
    jest.useFakeTimers({ doNotFake: ['setTimeout', 'nextTick', 'queueMicrotask'] });
    const changed = [{ rowNumber: 2, column: 'Email', before: 'A@X.ORG', after: 'a@x.org' }];
    getChangedValues.mockResolvedValue(changed);
    try {
      const element = await toMatchingStep();
      click(element, 'dry-run');
      await flush();
      jest.advanceTimersByTime(3000);
      await flush();
      expect(getChangedValues).toHaveBeenCalledWith({ batchId: 'a02' });
      expect(element.shadowRoot.querySelector('[data-id="results"]').changedValues).toEqual(
        changed
      );
    } finally {
      jest.useRealTimers();
    }
  });
});

describe('the import wizard loading one object', () => {
  const OBJECT_TEMPLATE = {
    id: 'a05',
    name: 'Program sessions',
    matchingRule: 'Email exact',
    mapping: '{"version":1,"columns":[]}',
    targetObject: 'Program_Session__c',
    targetObjectLabel: 'Program Session',
    loadOperation: 'Insert',
    loadOperations: ['Insert', 'Update by record Id', 'Upsert by external ID'],
    lookupNotFound: 'Reject the row'
  };
  const SESSIONS = 'Session Key,Program,Notes\nS-1,Reading,first\nS-2,Math,';

  beforeEach(() => {
    canImport.mockResolvedValue(true);
    getTemplates.mockResolvedValue([OBJECT_TEMPLATE]);
    getEntityTargets.mockResolvedValue([]);
    getMatchFields.mockResolvedValue({ contact: [], account: [] });
    getObjectFields.mockResolvedValue([
      { value: 'Record.Id', label: 'Salesforce record ID', isLookup: false, lookupFields: [] },
      { value: 'Record.Session_Key__c', label: 'Session Key', isLookup: false, lookupFields: [] },
      {
        value: 'Record.Program__c',
        label: 'Program',
        isLookup: true,
        lookupFields: [
          { value: 'Id', label: 'Salesforce record ID' },
          { value: 'Name', label: 'Program Name' }
        ]
      }
    ]);
    getKeyFields.mockResolvedValue([{ value: 'Session_Key__c', label: 'Session Key' }]);
    suggestMapping.mockResolvedValue(
      JSON.stringify({
        version: 1,
        columns: [
          { source: 'Session Key', target: 'Record.Session_Key__c' },
          { source: 'Program', target: 'Record.Program__c', lookupField: 'Name' },
          { source: 'Notes', target: 'Contact1.Email' }
        ]
      })
    );
    saveFile.mockResolvedValue('069000000000001');
    createBatch.mockResolvedValue(DRY_RUN_BATCH);
    stageRows.mockResolvedValue(2);
    startDryRun.mockResolvedValue(DRY_RUN_BATCH);
    getBatch.mockResolvedValue(DRY_RUN_BATCH);
    getRows.mockResolvedValue([]);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  async function toColumnsStep() {
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element, SESSIONS, 'sessions.csv');
    return element;
  }

  function loadOptions(element) {
    return element.shadowRoot.querySelector('[data-id="load-options"]');
  }

  it('creates a one-object mapping from the objects the user may load and chooses it', async () => {
    getTemplates.mockResolvedValue([TEMPLATE]);
    getLoadableObjects.mockResolvedValue([
      { value: 'Program_Session__c', label: 'Program Session' }
    ]);
    createObjectTemplate.mockResolvedValue(OBJECT_TEMPLATE);
    const element = render();
    await flush();
    click(element, 'choose-object');
    await flush();
    const object = element.shadowRoot.querySelector('[data-id="new-object"]');
    expect(object.options).toEqual([{ label: 'Program Session', value: 'Program_Session__c' }]);
    expect(element.shadowRoot.querySelector('[data-id="create-object-template"]').disabled).toBe(
      true
    );
    object.dispatchEvent(new CustomEvent('change', { detail: { value: 'Program_Session__c' } }));
    const name = element.shadowRoot.querySelector('[data-id="new-template-name"]');
    name.value = 'Program sessions';
    name.dispatchEvent(new CustomEvent('change'));
    await flush();
    click(element, 'create-object-template');
    await flush();

    expect(createObjectTemplate).toHaveBeenCalledWith({
      name: 'Program sessions',
      objectName: 'Program_Session__c'
    });
    expect(element.shadowRoot.querySelector('[data-id="template"]').value).toBe('a05');
    expect(element.shadowRoot.querySelector('[data-id="new-object"]')).toBeNull();
  });

  it('offers the object fields, and a lookup picker that keeps the saved choice', async () => {
    const element = await toColumnsStep();
    expect(getObjectFields).toHaveBeenCalledWith({ templateId: 'a05' });
    const pickers = element.shadowRoot.querySelectorAll('[data-id="column-row"]');
    const values = pickers[0].querySelector('lightning-combobox').options.map((o) => o.value);
    expect(values).toEqual(['Ignore', 'Record.Id', 'Record.Session_Key__c', 'Record.Program__c']);
    // A suggestion outside the object is not shown as chosen.
    expect(pickers[2].querySelector('lightning-combobox').value).toBe('Ignore');
    const lookups = element.shadowRoot.querySelectorAll('[data-id="lookup-field"]');
    expect(lookups).toHaveLength(1);
    expect(lookups[0].value).toBe('Name');
    expect(lookups[0].options.map((o) => o.value)).toEqual(['Id', 'Name']);
  });

  it('shows the load choices instead of the people rules, and sends them with the batch', async () => {
    const element = await toColumnsStep();
    click(element, 'next');
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="rule"]')).toBeNull();
    const options = loadOptions(element);
    expect(options.operations).toEqual(OBJECT_TEMPLATE.loadOperations);
    expect(options.keyFields).toEqual([{ value: 'Session_Key__c', label: 'Session Key' }]);

    options.dispatchEvent(
      new CustomEvent('change', {
        detail: {
          operation: 'Upsert by external ID',
          matchField: '',
          lookupNotFound: 'Leave it empty'
        }
      })
    );
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="dry-run"]').disabled).toBe(true);
    options.dispatchEvent(
      new CustomEvent('change', {
        detail: {
          operation: 'Upsert by external ID',
          matchField: 'Session_Key__c',
          lookupNotFound: 'Leave it empty'
        }
      })
    );
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="dry-run"]').disabled).toBe(false);
    click(element, 'dry-run');
    await flush();

    const call = createBatch.mock.calls[0][0];
    expect(JSON.parse(call.optionsJson).load).toEqual({
      operation: 'Upsert by external ID',
      matchField: 'Session_Key__c',
      lookupNotFound: 'Leave it empty',
      severalMatches: 'Reject the row'
    });
    expect(JSON.parse(call.mappingDocument).columns).toEqual([
      { source: 'Session Key', target: 'Record.Session_Key__c' },
      { source: 'Program', target: 'Record.Program__c', lookupField: 'Name' },
      { source: 'Notes', target: 'Ignore' }
    ]);
  });

  it('needs a record ID column before an update can dry run', async () => {
    const element = await toColumnsStep();
    click(element, 'next');
    await flush();
    loadOptions(element).dispatchEvent(
      new CustomEvent('change', {
        detail: {
          operation: 'Update by record Id',
          matchField: '',
          lookupNotFound: 'Reject the row'
        }
      })
    );
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="dry-run"]').disabled).toBe(true);
    click(element, 'back');
    await flush();
    const rows = element.shadowRoot.querySelectorAll('[data-id="column-row"]');
    rows[2]
      .querySelector('lightning-combobox')
      .dispatchEvent(new CustomEvent('change', { detail: { value: 'Record.Id' } }));
    await flush();
    click(element, 'next');
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="dry-run"]').disabled).toBe(false);
  });

  it('never offers the record ID or the upsert key as a value for every row', async () => {
    const element = await toColumnsStep();
    click(element, 'next');
    await flush();
    loadOptions(element).dispatchEvent(
      new CustomEvent('change', {
        detail: {
          operation: 'Upsert by external ID',
          matchField: 'Session_Key__c',
          lookupNotFound: 'Reject the row'
        }
      })
    );
    click(element, 'add-file-value');
    await flush();
    const target = element.shadowRoot.querySelector(
      '[data-id="file-value-row"] lightning-combobox'
    );
    expect(target.options.map((o) => o.value)).toEqual(['Record.Program__c']);
  });
});
