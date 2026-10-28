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
import startTrial from '@salesforce/apex/ImportController.startTrial';
import getBatch from '@salesforce/apex/ImportController.getBatch';
import getRowPage from '@salesforce/apex/ImportController.getRowPage';
import saveRecurring from '@salesforce/apex/ImportController.saveRecurring';
import getEntityTargets from '@salesforce/apex/ImportController.getEntityTargets';
import getMatchFields from '@salesforce/apex/ImportController.getMatchFields';
import getLoadableObjects from '@salesforce/apex/ImportController.getLoadableObjects';
import createObjectTemplate from '@salesforce/apex/ImportController.createObjectTemplate';
import getObjectFields from '@salesforce/apex/ImportController.getObjectFields';
import getKeyFields from '@salesforce/apex/ImportController.getKeyFields';
import getRowMatchFields from '@salesforce/apex/ImportController.getRowMatchFields';
import getRelatedOptions from '@salesforce/apex/ImportController.getRelatedOptions';
import getRelatedFields from '@salesforce/apex/ImportController.getRelatedFields';
import getChangedValues from '@salesforce/apex/ImportController.getChangedValues';
import previewChanges from '@salesforce/apex/ImportController.previewChanges';
import openRetry from '@salesforce/apex/ImportController.openRetry';
import copyTemplate from '@salesforce/apex/ImportController.copyTemplate';
import { EnclosingTabId, setTabIcon, setTabLabel } from 'lightning/platformWorkspaceApi';
import { readSheetNames, readXlsx } from '../xlsx';

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
// And for what a template creates (D-136).
jest.mock(
  '@salesforce/label/c.Core_Import_CreatesSummary',
  () => ({ default: 'This file can create: {0}.' }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Core_Import_LoadsSummary', () => ({ default: 'Loads: {0}' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_Import_DeletesSummary', () => ({ default: 'Deletes: {0}' }), {
  virtual: true
});
// The Delete card is for holders of Bulk Delete Records; importKinds.test.js covers the others.
jest.mock('@salesforce/customPermission/Bulk_Delete_Records', () => ({ default: true }), {
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
jest.mock('@salesforce/apex/ImportController.startTrial', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.getBatch', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.saveRecurring', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.getRowPage', () => ({ default: jest.fn() }), {
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
jest.mock('@salesforce/apex/ImportController.getRowMatchFields', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.getRelatedOptions', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.getRelatedFields', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.getChangedValues', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.previewChanges', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.openRetry', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.copyTemplate', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_Import_CopyTemplateDefaultName',
  () => ({ default: 'Copy of {0}' }),
  { virtual: true }
);
// The workbook reader runs for real (jsdom has no DecompressionStream, so a real workbook
// cannot be opened here); a test that needs sheets gives their contents once.
jest.mock('../xlsx', () => {
  const actual = jest.requireActual('../xlsx');
  return {
    ...actual,
    readSheetNames: jest.fn((...args) => actual.readSheetNames(...args)),
    readXlsx: jest.fn((...args) => actual.readXlsx(...args))
  };
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

const EMPTY_PAGE = { cursor: null, rows: [], nextIndex: 0, total: 0, hasMore: false };

const FILE_TEXT = 'Last Name,Email,Notes\nRamirez,ana@example.org,vip\nOkafor,ben@example.org,';

/** The fixed columns of a people file, as the server lists them (ImportFieldCatalog). */
const FIXED_TARGETS = [
  { value: 'Contact1.FirstName', label: 'Person: first name' },
  { value: 'Contact1.LastName', label: 'Person: last name' },
  { value: 'Contact1.Email', label: 'Person: email' },
  { value: 'Contact1.Phone', label: 'Person: phone' },
  { value: 'Contact1.MailingCity', label: 'Person: city' },
  { value: 'Contact2.Email', label: 'Second person: email' },
  { value: 'Organization.Name', label: 'Organization: name' },
  { value: 'Affiliation.Role__c', label: 'Affiliation: role' }
];

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
async function chooseFile(element, text = FILE_TEXT, name = 'donors.csv', size = undefined) {
  const input = element.shadowRoot.querySelector('[data-id="file"]');
  const file = new File([text], name, { type: 'text/csv' });
  if (size !== undefined) {
    Object.defineProperty(file, 'size', { value: size });
  }
  Object.defineProperty(input, 'files', { value: [file], configurable: true });
  input.dispatchEvent(new CustomEvent('change'));
  await flush();
}

/**
 * Clicks a control by its data-id. Back lives in the step flow's footer, and a results
 * download is an item of the Download menu, which fires select on the menu.
 */
function click(element, id) {
  const root = element.shadowRoot;
  if (id === 'back') {
    root.querySelector('c-barn-step-flow').shadowRoot.querySelector('[data-id="back"]').click();
    return;
  }
  const node = root.querySelector(`[data-id="${id}"]`);
  if (node.tagName === 'LIGHTNING-MENU-ITEM') {
    root
      .querySelector('[data-id="download-menu"]')
      .dispatchEvent(new CustomEvent('select', { detail: { value: node.value } }));
    return;
  }
  node.click();
}

/** Chooses one of the first step's cards on the visual picker (D-136, D-140). */
async function chooseKind(element, kind) {
  element.shadowRoot
    .querySelector('[data-id="kind-picker"]')
    .dispatchEvent(new CustomEvent('change', { detail: { value: kind } }));
  await flush();
}

/**
 * Renders the wizard and chooses the first template, as the first step's dropdown used to:
 * through People and Organizations when the first template is a people one, otherwise from
 * Your Templates.
 */
async function open() {
  const element = render();
  await flush();
  if (!element.shadowRoot.querySelector('[data-id="kind-picker"]')) {
    return element;
  }
  await chooseKind(element, 'people');
  const templates = (await getTemplates.mock.results[0].value) || [];
  const picker = element.shadowRoot.querySelector('[data-id="template"]');
  if (templates.length > 0 && picker.value !== templates[0].id) {
    await chooseKind(element, 'templates');
    element.shadowRoot.querySelector('[data-id="use-template"]').click();
    await flush();
  }
  return element;
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
    getRowPage.mockResolvedValue(EMPTY_PAGE);
    getEntityTargets.mockResolvedValue([]);
    getMatchFields.mockResolvedValue({ fixedTargets: FIXED_TARGETS, contact: [], account: [] });
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
    const element = await open();
    expect(element.shadowRoot.querySelector('[data-id="template"]').options).toEqual([
      { label: 'Generic contact list', value: 'a01' }
    ]);
  });

  it('opens on the choice cards, without Gifts when no template loads gifts', async () => {
    const element = render();
    await flush();
    const kindPicker = element.shadowRoot.querySelector('[data-id="kind-picker"]');
    expect(kindPicker.label).toBe('c.Core_Import_StepKind');
    expect(kindPicker.value).toBeUndefined();
    expect(kindPicker.options.map((option) => option.value)).toEqual([
      'people',
      'object',
      'related',
      'delete',
      'templates'
    ]);
    expect(kindPicker.options.find((option) => option.value === 'delete').warning).toBe(true);
    expect(kindPicker.options.every((option) => option.iconName && option.label)).toBe(true);
    expect(element.shadowRoot.querySelector('[data-id="next"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="template"]')).toBeNull();
  });

  it('shows the six steps on the path, Back only from step two', async () => {
    const element = await open();
    const flow = element.shadowRoot.querySelector('[data-id="flow"]');
    expect(flow.steps.map((step) => step.label)).toEqual([
      'c.Core_Import_StepFileType',
      'c.Core_Import_StepUpload',
      'c.Core_Import_StepColumns',
      'c.Core_Import_StepMatching',
      'c.Core_Import_StepPreview',
      'c.Core_Import_StepResults'
    ]);
    expect(flow.currentStep).toBe('1');
    expect(flow.canGoBack).toBe(false);
    // The picker stays on screen with the choice, and the kind's templates show below it.
    expect(element.shadowRoot.querySelector('[data-id="kind-picker"]').value).toBe('people');
    click(element, 'next');
    await flush();
    expect(flow.currentStep).toBe('2');
    expect(flow.canGoBack).toBe(true);
    click(element, 'back');
    await flush();
    expect(flow.currentStep).toBe('1');
  });

  it('shows Gifts when a template maps a gift column, offering only the gift templates', async () => {
    const giftTemplate = {
      ...TEMPLATE,
      id: 'a09',
      name: 'Generic gift list',
      mapping: JSON.stringify({
        version: 1,
        columns: [
          { source: 'Email', target: 'Contact1.Email' },
          { source: 'Amount', target: 'Gift.Amount' }
        ]
      })
    };
    getTemplates.mockResolvedValue([TEMPLATE, giftTemplate]);
    const element = render();
    await flush();
    await chooseKind(element, 'gifts');
    expect(element.shadowRoot.querySelector('[data-id="template"]').options).toEqual([
      { label: 'Generic gift list', value: 'a09' }
    ]);
    expect(element.shadowRoot.querySelector('[data-id="template"]').value).toBe('a09');
    expect(element.shadowRoot.querySelector('[data-id="template-creates"]').textContent).toContain(
      'This file can create: c.Core_Import_CreatesPeople, c.Core_Import_CreatesGifts.'
    );
    await chooseKind(element, 'people');
    expect(element.shadowRoot.querySelector('[data-id="template"]').options).toEqual([
      { label: 'Generic contact list', value: 'a01' }
    ]);
  });

  it('says what a people template creates, linking people to organizations', async () => {
    getTemplates.mockResolvedValue([
      {
        ...TEMPLATE,
        mapping: JSON.stringify({
          version: 1,
          columns: [
            { source: 'Email', target: 'Contact1.Email' },
            { source: 'Partner Email', target: 'Contact2.Email' },
            { source: 'Household', target: 'Household.Name' },
            { source: 'Employer', target: 'Organization.Name' }
          ]
        })
      }
    ]);
    const element = await open();
    expect(element.shadowRoot.querySelector('[data-id="template-creates"]').textContent).toContain(
      'This file can create: c.Core_Import_CreatesPeople, c.Core_Import_CreatesSecondPerson, ' +
        'c.Core_Import_CreatesHouseholds, c.Core_Import_CreatesOrganizations, ' +
        'c.Core_Import_CreatesAffiliations.'
    );
    expect(element.shadowRoot.querySelector('[data-id="next"]').disabled).toBe(false);
  });

  it('starts People and Organizations on the general template, whatever its name', async () => {
    getTemplates.mockResolvedValue([
      { ...TEMPLATE, id: 'a10', name: 'Couples and Households', templateKey: 'couples' },
      { ...TEMPLATE, name: 'People and Organizations List', templateKey: 'generic_contact_list' }
    ]);
    const element = render();
    await flush();
    await chooseKind(element, 'people');
    expect(element.shadowRoot.querySelector('[data-id="template"]').value).toBe('a01');
  });

  it('starts a new people template from the chosen one and chooses it', async () => {
    copyTemplate.mockResolvedValue({ ...TEMPLATE, id: 'a11', name: 'Event sign-ups' });
    const element = await open();
    click(element, 'start-copy');
    await flush();
    const name = element.shadowRoot.querySelector('[data-id="copy-name"]');
    expect(name.value).toBe('Copy of Generic contact list');
    name.value = 'Event sign-ups';
    name.dispatchEvent(new CustomEvent('change'));
    await flush();
    click(element, 'create-copy');
    await flush();

    expect(copyTemplate).toHaveBeenCalledWith({ templateId: 'a01', name: 'Event sign-ups' });
    const picker = element.shadowRoot.querySelector('[data-id="template"]');
    expect(picker.value).toBe('a11');
    expect(picker.options.map((option) => option.value)).toEqual(['a01', 'a11']);
    expect(element.shadowRoot.querySelector('[data-id="copy-name"]')).toBeNull();
  });

  it('says why a new template could not be started, and stays put', async () => {
    copyTemplate.mockRejectedValue({ body: { message: 'Give the template a name.' } });
    const element = await open();
    click(element, 'start-copy');
    await flush();
    click(element, 'create-copy');
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="message"]').textContent).toBe(
      'Give the template a name.'
    );
    expect(element.shadowRoot.querySelector('[data-id="copy-name"]')).not.toBeNull();
  });

  it('lists every template under Your Templates with what it loads and when', async () => {
    getTemplates.mockResolvedValue([
      { ...TEMPLATE, lastImportDate: '2026-10-01' },
      {
        id: 'a07',
        name: 'Volunteer hours',
        description: 'Hours from a sign-in sheet.',
        mapping: '{"version":1,"columns":[]}',
        targetObject: 'Volunteer_Hours__c',
        targetObjectLabel: 'Volunteer Hours',
        loadOperation: 'Insert',
        loadOperations: ['Insert']
      }
    ]);
    const element = render();
    await flush();
    await chooseKind(element, 'templates');
    const items = element.shadowRoot.querySelectorAll('[data-id="template-item"]');
    expect(items).toHaveLength(2);
    expect(items[0].querySelector('lightning-formatted-date-time').value).toBe('2026-10-01');
    expect(items[1].textContent).toContain('Loads: Volunteer Hours');
    expect(items[1].textContent).toContain('c.Core_Import_NotLoadedYet');
    expect(element.shadowRoot.querySelector('[data-id="next"]').disabled).toBe(true);

    items[1].querySelector('[data-id="use-template"]').click();
    await flush();
    expect(items[1].querySelector('[data-id="use-template"]').variant).toBe('brand');
    expect(element.shadowRoot.querySelector('[data-id="next"]').disabled).toBe(false);
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
    const element = await open();
    expect(element.shadowRoot.querySelector('[data-id="read-only"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="template"]')).toBeNull();
  });

  it('saves the recurring mark and its source name before leaving the first step', async () => {
    saveRecurring.mockResolvedValue(undefined);
    const element = await open();
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
    const element = await open();
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
    const element = await open();
    click(element, 'next');
    await flush();
    expect(saveRecurring).not.toHaveBeenCalled();
  });

  it('shows the chosen template description so the choice can be checked', async () => {
    const element = await open();
    expect(element.shadowRoot.querySelector('[data-id="template-help"]').textContent).toContain(
      'A list of people'
    );
  });

  it('shows a row of the column picker for every column in the file', async () => {
    const element = await open();
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

    await chooseKind(element, 'people');
    click(element, 'next');
    await flush();
    await chooseFile(element);

    expect(setTabLabel).toHaveBeenLastCalledWith('tab0', 'c.Core_Import_TabLabel: donors.csv');
  });

  it('shows the first values of each column beside the choice', async () => {
    const element = await open();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    const rows = element.shadowRoot.querySelectorAll('[data-id="column-row"]');
    expect(rows[0].textContent).toContain('Ramirez, Okafor');
  });

  it('refuses a file with no rows under its heading', async () => {
    const element = await open();
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
    const element = await open();
    click(element, 'next');
    await flush();
    await chooseFile(element, 'not really a workbook', 'donors.xlsx');
    expect(element.shadowRoot.querySelector('[data-id="message"]').textContent).toBe(
      'c.Core_Import_XlsxUnreadable'
    );
    expect(element.shadowRoot.querySelectorAll('[data-id="column-row"]')).toHaveLength(0);
  });

  it('reads a semicolon file by its own separator and offers to change it', async () => {
    const element = await open();
    click(element, 'next');
    await flush();
    await chooseFile(element, 'Last Name;Email;Notes\nRamirez;ana@example.org;vip', 'eu.csv');
    expect(element.shadowRoot.querySelectorAll('[data-id="column-row"]')).toHaveLength(3);
    const picker = element.shadowRoot.querySelector('[data-id="delimiter"]');
    expect(picker.value).toBe(';');
    expect(picker.options.map((option) => option.value)).toEqual([',', ';', '\t', '|']);
    expect(element.shadowRoot.querySelector('[data-id="sheet"]')).toBeNull();
  });

  it('reads the file again when the separator is changed, and back', async () => {
    const element = await open();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    const picker = element.shadowRoot.querySelector('[data-id="delimiter"]');
    expect(picker.value).toBe(',');
    picker.dispatchEvent(new CustomEvent('change', { detail: { value: ';' } }));
    await flush();
    const rows = element.shadowRoot.querySelectorAll('[data-id="column-row"]');
    expect(rows).toHaveLength(1);
    expect(rows[0].textContent).toContain('Last Name,Email,Notes');
    expect(suggestMapping).toHaveBeenLastCalledWith({
      templateId: 'a01',
      headers: ['Last Name,Email,Notes']
    });
    element.shadowRoot
      .querySelector('[data-id="delimiter"]')
      .dispatchEvent(new CustomEvent('change', { detail: { value: ',' } }));
    await flush();
    expect(element.shadowRoot.querySelectorAll('[data-id="column-row"]')).toHaveLength(3);
  });

  it('offers the sheets of a workbook that has several, and reads the one chosen', async () => {
    readSheetNames
      .mockResolvedValueOnce(['Read me', 'Donors'])
      .mockResolvedValueOnce(['Read me', 'Donors']);
    readXlsx
      .mockResolvedValueOnce([['About this export'], ['Exported 1 October']])
      .mockResolvedValueOnce([
        ['Last Name', 'Email'],
        ['Ramirez', 'ana@example.org']
      ]);
    const element = await open();
    click(element, 'next');
    await flush();
    await chooseFile(element, 'zip bytes', 'donors.xlsx');
    const picker = element.shadowRoot.querySelector('[data-id="sheet"]');
    expect(picker.value).toBe('Read me');
    expect(picker.options).toEqual([
      { label: 'Read me', value: 'Read me' },
      { label: 'Donors', value: 'Donors' }
    ]);
    expect(element.shadowRoot.querySelector('[data-id="delimiter"]')).toBeNull();
    picker.dispatchEvent(new CustomEvent('change', { detail: { value: 'Donors' } }));
    await flush();
    expect(readXlsx).toHaveBeenLastCalledWith(expect.anything(), { sheet: 'Donors' });
    const rows = element.shadowRoot.querySelectorAll('[data-id="column-row"]');
    expect(rows).toHaveLength(2);
    expect(rows[0].textContent).toContain('Last Name');
  });

  it('shows no columns and will not go on when the chosen sheet has no rows', async () => {
    readSheetNames
      .mockResolvedValueOnce(['Donors', 'Empty'])
      .mockResolvedValueOnce(['Donors', 'Empty']);
    readXlsx
      .mockResolvedValueOnce([
        ['Last Name', 'Email'],
        ['Ramirez', 'ana@example.org']
      ])
      .mockResolvedValueOnce([['Last Name']]);
    const element = await open();
    click(element, 'next');
    await flush();
    await chooseFile(element, 'zip bytes', 'donors.xlsx');
    expect(element.shadowRoot.querySelector('[data-id="next"]').disabled).toBe(false);
    element.shadowRoot
      .querySelector('[data-id="sheet"]')
      .dispatchEvent(new CustomEvent('change', { detail: { value: 'Empty' } }));
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="message"]').textContent).toBe(
      'c.Core_Import_NoHeaderRow'
    );
    expect(element.shadowRoot.querySelectorAll('[data-id="column-row"]')).toHaveLength(0);
    expect(element.shadowRoot.querySelector('[data-id="next"]').disabled).toBe(true);
  });

  it('explains what the chosen matching rule risks', async () => {
    const element = await open();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    click(element, 'next');
    await flush();
    const help = element.shadowRoot.querySelector('[data-id="rule-help"]');
    expect(help.textContent).toBe('c.Core_Import_MatchingEmailHelp');
  });

  it('writes nothing before the dry run', async () => {
    const element = await open();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    click(element, 'next');
    await flush();
    expect(createBatch).not.toHaveBeenCalled();
    expect(startDryRun).not.toHaveBeenCalled();
  });

  it('stages the file in pages and then dry runs it', async () => {
    const element = await open();
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
    const element = await open();
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
    const element = await open();
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
    const element = await open();
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
    const element = await open();
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
    const element = await open();
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

  it('offers the fixed columns the server lists, with its labels', async () => {
    const element = await open();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    const picker = element.shadowRoot.querySelector('[data-id="column-row"] lightning-combobox');
    expect(picker.options).toEqual(
      expect.arrayContaining([
        { value: 'Contact1.LastName', label: 'Person: last name' },
        { value: 'Affiliation.Role__c', label: 'Affiliation: role' }
      ])
    );
  });

  it('imports a file too large to keep without its original, and says so', async () => {
    const element = await open();
    click(element, 'next');
    await flush();
    await chooseFile(element, FILE_TEXT, 'donors.csv', 3000000);
    click(element, 'next');
    await flush();
    click(element, 'dry-run');
    await flush();
    expect(saveFile).not.toHaveBeenCalled();
    expect(createBatch.mock.calls[0][0].fileId).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="original-not-kept"]').textContent).toContain(
      'c.Core_Import_OriginalTooLargeToKeep'
    );
  });

  it('says when the original could not be kept, and imports anyway', async () => {
    saveFile.mockRejectedValue({ body: { message: 'Heap too large' } });
    const element = await toMatchingStep();
    click(element, 'dry-run');
    await flush();
    expect(createBatch).toHaveBeenCalled();
    // The label mock has no {0} to fill; the real label carries the reason.
    expect(element.shadowRoot.querySelector('[data-id="original-not-kept"]').textContent).toContain(
      'c.Core_Import_OriginalNotKept'
    );
  });

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
    const element = await open();
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
    const element = await open();
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
      fixedTargets: FIXED_TARGETS,
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
      fixedTargets: FIXED_TARGETS,
      contact: [{ value: 'Member_Number__c', label: 'Member Number' }],
      account: [{ value: 'Charity_Number__c', label: 'Charity Number' }]
    });
    const element = await open();
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
      fixedTargets: FIXED_TARGETS,
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
    const element = await open();
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

  it('keeps values, totals and payments under More Options, open once one is set', async () => {
    const element = await toMatchingStep();
    const more = element.shadowRoot.querySelector('[data-id="more-options"]');
    expect(more.activeSectionName).toBe('');
    expect(more.querySelector('[data-id="add-file-value"]')).not.toBeNull();
    expect(more.querySelector('[data-id="expected-count"]')).not.toBeNull();
    const count = element.shadowRoot.querySelector('[data-id="expected-count"]');
    count.value = '3';
    count.dispatchEvent(new CustomEvent('change'));
    await flush();
    expect(more.activeSectionName).toBe('more');
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
    const element = await open();
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
    const element = await open();
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

  it('starts from the rows to load the mapping holds and sends the ones settled on', async () => {
    suggestMapping.mockResolvedValue(
      JSON.stringify({
        version: 1,
        columns: [{ source: 'Last Name', target: 'Contact1.LastName' }],
        uniqueBy: ['Email']
      })
    );
    const element = await open();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    const panel = element.shadowRoot.querySelector('[data-id="row-rules"]');
    expect(panel.uniqueBy).toEqual(['Email']);
    expect(panel.columnNames).toEqual(['Last Name', 'Email', 'Notes']);
    expect(element.shadowRoot.querySelector('[data-id="blank-clears"]')).toBeNull();
    const skipRows = [{ column: 'Notes', test: 'contains', text: 'test' }];
    panel.dispatchEvent(new CustomEvent('change', { detail: { skipRows, uniqueBy: [] } }));
    await flush();
    click(element, 'next');
    await flush();
    click(element, 'dry-run');
    await flush();
    const sent = JSON.parse(createBatch.mock.calls[0][0].mappingDocument);
    expect(sent.skipRows).toEqual(skipRows);
    expect(sent.uniqueBy).toBeUndefined();
  });

  it('sends the duplicate rules choice, and warns when no rule is switched on', async () => {
    getMatchFields.mockResolvedValue({
      fixedTargets: FIXED_TARGETS,
      contact: [],
      account: [],
      contactRules: false
    });
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
    getMatchFields.mockResolvedValue({
      fixedTargets: FIXED_TARGETS,
      contact: [],
      account: [],
      contactRules: true
    });
    const element = await toMatchingStep();
    expect(element.shadowRoot.querySelector('[data-id="duplicate-rules"]').checked).toBe(true);
    expect(element.shadowRoot.querySelector('[data-id="duplicate-rules-none"]')).toBeNull();
  });

  it('warns for person accounts when only an organization rule is switched on', async () => {
    getTemplates.mockResolvedValue([
      { ...TEMPLATE, personMode: 'Person Accounts', useDuplicateRules: true }
    ]);
    getMatchFields.mockResolvedValue({
      contact: [],
      account: [],
      contactRules: true,
      accountRules: true,
      personAccountRules: false
    });
    const element = await toMatchingStep();
    expect(element.shadowRoot.querySelector('[data-id="duplicate-rules-none"]')).not.toBeNull();
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

  describe('the exceptions file', () => {
    const RealBlob = global.Blob;
    let written;

    /** A cursor of `total` rejected rows, served from whatever start index is asked for. */
    function serveRejected(total) {
      getRowPage.mockImplementation(({ cursor, startIndex, pageSize }) => {
        const rows = [];
        for (let i = startIndex; i < Math.min(startIndex + pageSize, total); i++) {
          rows.push({
            id: `r${i}`,
            rowNumber: i + 2,
            status: 'Rejected',
            errorMessage: 'Last name is missing.',
            values: JSON.stringify({
              'Last Name': i === 0 ? '=HYPERLINK("x")' : `Person ${i}`,
              Email: '',
              Notes: i === 1 ? '-25.00' : 'n'
            })
          });
        }
        const nextIndex = startIndex + rows.length;
        return Promise.resolve({
          cursor: cursor || { token: 'cursor-1' },
          rows,
          nextIndex,
          total,
          hasMore: nextIndex < total
        });
      });
    }

    beforeEach(() => {
      written = undefined;
      global.Blob = function CapturingBlob(parts, options) {
        written = parts.join('');
        return new RealBlob(parts, options);
      };
      global.URL.createObjectURL = jest.fn(() => 'blob:exceptions');
      global.URL.revokeObjectURL = jest.fn();
      jest.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});
      jest.useFakeTimers({ doNotFake: ['setTimeout', 'nextTick', 'queueMicrotask'] });
    });

    afterEach(() => {
      global.Blob = RealBlob;
      HTMLAnchorElement.prototype.click.mockRestore();
      jest.useRealTimers();
    });

    async function toFinishedDryRun(rejected) {
      getBatch.mockResolvedValue({ ...DRY_RUN_BATCH, rejected });
      const element = await toMatchingStep();
      click(element, 'dry-run');
      await flush();
      jest.advanceTimersByTime(3000);
      await flush();
      return element;
    }

    it('holds every rejected row, read page by page through one cursor', async () => {
      serveRejected(1250);
      const element = await toFinishedDryRun(1250);
      const results = element.shadowRoot.querySelector('[data-id="results"]');
      expect(results.rejectedRows).toHaveLength(200);
      getRowPage.mockClear();

      click(element, 'download');
      await flush();

      // A fresh cursor, then the same one handed back from where each page ended.
      expect(getRowPage.mock.calls.map(([args]) => [args.startIndex, args.cursor])).toEqual([
        [0, null],
        [500, { token: 'cursor-1' }],
        [1000, { token: 'cursor-1' }]
      ]);
      const lines = written.split('\r\n').filter((line) => line.length > 0);
      expect(lines).toHaveLength(1251);
      expect(lines[0]).toBe(
        '﻿c.Core_Import_ResultsRow,Last Name,Email,Notes,c.Core_Import_ResultsReason'
      );
      // The shared writer defuses a formula and leaves a negative amount alone.
      expect(lines[1]).toBe('2,"\'=HYPERLINK(""x"")",,n,Last name is missing.');
      expect(lines[2]).toBe('3,Person 1,,-25.00,Last name is missing.');
      expect(lines[1250].startsWith('1251,Person 1249,')).toBe(true);
      expect(global.URL.createObjectURL).toHaveBeenCalledTimes(1);
      expect(element.shadowRoot.querySelector('[data-id="message"]')).toBeNull();
    });

    it('says so when the file holds fewer rows than were rejected', async () => {
      serveRejected(3);
      const element = await toFinishedDryRun(5);
      click(element, 'download');
      await flush();
      expect(written.split('\r\n').filter((line) => line.length > 0)).toHaveLength(4);
      expect(element.shadowRoot.querySelector('[data-id="message"]').textContent).toBe(
        'c.Core_Import_ExceptionsCapped'
      );
    });

    it('reports a failed read in words and saves no file', async () => {
      serveRejected(2);
      const element = await toFinishedDryRun(2);
      getRowPage.mockRejectedValue({ body: { message: 'Cursor expired.' } });
      click(element, 'download');
      await flush();
      expect(written).toBeUndefined();
      expect(element.shadowRoot.querySelector('[data-id="message"]').textContent).toBe(
        'Cursor expired.'
      );
    });

    it('never reads the file again from the top when a page does not move forward', async () => {
      serveRejected(2);
      const element = await toFinishedDryRun(2);
      getRowPage.mockClear();
      getRowPage.mockResolvedValue({
        cursor: { token: 'cursor-1' },
        rows: [{ id: 'r0', rowNumber: 2, errorMessage: 'Bad.', values: '{}' }],
        nextIndex: 0,
        total: 2,
        hasMore: true
      });
      click(element, 'download');
      await flush();
      expect(getRowPage).toHaveBeenCalledTimes(1);
      expect(written.split('\r\n').filter((line) => line.length > 0)).toHaveLength(2);
    });
  });

  describe('the results file', () => {
    const RealBlob = global.Blob;
    let written;
    let fileName;

    /** Every row of the import, each with what became of it. */
    function serveAll(total) {
      getRowPage.mockImplementation(({ cursor, startIndex, pageSize, status }) => {
        const rows = [];
        for (let i = startIndex; i < Math.min(startIndex + pageSize, total); i++) {
          const rejected = i === total - 1;
          rows.push({
            id: `r${i}`,
            rowNumber: i + 2,
            status: rejected ? 'Rejected' : 'Created',
            errorMessage: rejected ? 'Last name is missing.' : undefined,
            person1Id: rejected ? undefined : `003${i}`,
            householdId: rejected ? undefined : `a0H${i}`,
            resultingRecordId: rejected ? undefined : `a0S${i}`,
            values: JSON.stringify({ 'Last Name': `Person ${i}`, Email: '', Notes: 'n' })
          });
        }
        const nextIndex = startIndex + rows.length;
        return Promise.resolve({
          cursor: cursor || { token: `cursor-${status || 'all'}` },
          rows,
          nextIndex,
          total,
          hasMore: nextIndex < total
        });
      });
    }

    beforeEach(() => {
      written = undefined;
      fileName = undefined;
      global.Blob = function CapturingBlob(parts, options) {
        written = parts.join('');
        return new RealBlob(parts, options);
      };
      global.URL.createObjectURL = jest.fn(() => 'blob:results');
      global.URL.revokeObjectURL = jest.fn();
      jest.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(function capture() {
        fileName = this.download;
      });
    });

    afterEach(() => {
      global.Blob = RealBlob;
      HTMLAnchorElement.prototype.click.mockRestore();
    });

    async function toCommitted(rowCount) {
      startCommit.mockResolvedValue({
        ...DRY_RUN_BATCH,
        status: 'Complete',
        isDryRun: false,
        rowCount
      });
      const element = await toMatchingStep();
      click(element, 'dry-run');
      await flush();
      element.shadowRoot.querySelector('[data-id="commit"]').click();
      await flush();
      return element;
    }

    it('holds every row with its outcome, the records it became, and its reason', async () => {
      serveAll(700);
      const element = await toCommitted(700);
      getRowPage.mockClear();
      click(element, 'download-results');
      await flush();

      // Every row, not only one status, through one cursor.
      expect(getRowPage.mock.calls.map(([args]) => [args.status, args.startIndex])).toEqual([
        [null, 0],
        [null, 500]
      ]);
      const lines = written.split('\r\n').filter((line) => line.length > 0);
      expect(lines).toHaveLength(701);
      expect(lines[0]).toBe(
        '﻿c.Core_Import_ResultsRow,c.Core_Import_ResultsOutcome,' +
          'c.Core_Import_ResultsPersonId,c.Core_Import_ResultsSecondPersonId,' +
          'c.Core_Import_ResultsHouseholdId,c.Core_Import_ResultsOrganizationId,' +
          'c.Core_Import_ResultsModuleRecordId,c.Core_Import_ResultsReason,' +
          'Last Name,Email,Notes'
      );
      expect(lines[1]).toBe('2,Created,0030,,a0H0,,a0S0,,Person 0,,n');
      expect(lines[700]).toBe('701,Rejected,,,,,,Last name is missing.,Person 699,,n');
      expect(fileName).toBe('IB-000001-results.csv');
      expect(element.shadowRoot.querySelector('[data-id="message"]')).toBeNull();
    });

    it('says so when the file holds fewer rows than the import', async () => {
      serveAll(3);
      const element = await toCommitted(5);
      click(element, 'download-results');
      await flush();
      expect(written.split('\r\n').filter((line) => line.length > 0)).toHaveLength(4);
      expect(element.shadowRoot.querySelector('[data-id="message"]').textContent).toBe(
        'c.Core_Import_ResultsCapped'
      );
    });
  });

  describe('trying the first rows', () => {
    const PREVIEWED = { ...DRY_RUN_BATCH, rowCount: 300, defaultTrialRows: 25 };

    async function toPreview() {
      startDryRun.mockResolvedValue(PREVIEWED);
      const element = await toMatchingStep();
      click(element, 'dry-run');
      await flush();
      return element;
    }

    it('offers the org size, imports that many first rows, and shows the results', async () => {
      startTrial.mockResolvedValue({ ...PREVIEWED, status: 'Committing', isFinished: false });
      const element = await toPreview();
      const rows = element.shadowRoot.querySelector('[data-id="trial-rows"]');
      expect(rows.value).toBe('25');
      click(element, 'trial-button');
      await flush();
      expect(startTrial).toHaveBeenCalledWith({ batchId: 'a02', rowCount: 25 });
      expect(startCommit).not.toHaveBeenCalled();
      expect(element.shadowRoot.querySelector('[data-id="start-over"]')).not.toBeNull();
    });

    it('takes a size typed for this file, and refuses one out of range', async () => {
      startTrial.mockResolvedValue({ ...PREVIEWED, status: 'Committing', isFinished: false });
      const element = await toPreview();
      const rows = element.shadowRoot.querySelector('[data-id="trial-rows"]');
      rows.value = '0';
      rows.dispatchEvent(new CustomEvent('change'));
      await flush();
      expect(element.shadowRoot.querySelector('[data-id="trial-button"]').disabled).toBe(true);
      rows.value = '10';
      rows.dispatchEvent(new CustomEvent('change'));
      await flush();
      click(element, 'trial-button');
      await flush();
      expect(startTrial).toHaveBeenCalledWith({ batchId: 'a02', rowCount: 10 });
    });

    it('is not offered while the preview cannot be imported', async () => {
      startDryRun.mockResolvedValue({ ...PREVIEWED, controlTotalsAgree: false });
      const element = await toMatchingStep();
      click(element, 'dry-run');
      await flush();
      expect(element.shadowRoot.querySelector('[data-id="trial"]')).toBeNull();
    });

    it('after the trial, says what is left and imports it into the same import', async () => {
      startTrial.mockResolvedValue({
        ...PREVIEWED,
        status: 'Trial complete',
        isDryRun: false,
        isFinished: true,
        trialRows: 25
      });
      startCommit.mockResolvedValue({
        ...PREVIEWED,
        status: 'Committing',
        isDryRun: false,
        isFinished: false,
        trialRows: 25
      });
      const element = await toPreview();
      click(element, 'trial-button');
      await flush();
      expect(element.shadowRoot.querySelector('[data-id="trial-done"]').textContent).toContain(
        'c.Core_Import_TrialDone'
      );
      click(element, 'remaining-button');
      await flush();
      expect(startCommit).toHaveBeenCalledWith({ batchId: 'a02' });
      expect(element.shadowRoot.querySelector('[data-id="remaining"]')).toBeNull();
    });
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
    getMatchFields.mockResolvedValue({ fixedTargets: FIXED_TARGETS, contact: [], account: [] });
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
    getRowMatchFields.mockResolvedValue([
      { value: 'Notes__c', label: 'Notes' },
      { value: 'Session_Key__c', label: 'Session Key' }
    ]);
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
    getRowPage.mockResolvedValue(EMPTY_PAGE);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  async function toColumnsStep() {
    const element = await open();
    click(element, 'next');
    await flush();
    await chooseFile(element, SESSIONS, 'sessions.csv');
    return element;
  }

  function loadOptions(element) {
    return element.shadowRoot.querySelector('[data-id="load-options"]');
  }

  async function toObjectMatchingStep() {
    const element = await toColumnsStep();
    click(element, 'next');
    await flush();
    return element;
  }

  function chooseOperation(element, operation, matchField = '') {
    loadOptions(element).dispatchEvent(
      new CustomEvent('change', {
        detail: { operation, matchField, lookupNotFound: 'Reject the row' }
      })
    );
  }

  it('offers the duplicate rules box under Insert, and sends it', async () => {
    const element = await toObjectMatchingStep();
    const box = element.shadowRoot.querySelector('[data-id="duplicate-rules"]');
    expect(box).not.toBeNull();
    expect(box.fieldLevelHelp).toBe('c.Core_Import_DuplicateRulesObjectHelp');
    box.checked = true;
    box.dispatchEvent(new CustomEvent('change'));
    await flush();
    // A one-object mapping never warns about people rules.
    expect(element.shadowRoot.querySelector('[data-id="duplicate-rules-none"]')).toBeNull();
    click(element, 'dry-run');
    await flush();
    expect(JSON.parse(createBatch.mock.calls[0][0].optionsJson).matching.useDuplicateRules).toBe(
      true
    );
  });

  it('offers the box under Upsert, and hides it under an operation that never creates', async () => {
    getTemplates.mockResolvedValue([{ ...OBJECT_TEMPLATE, useDuplicateRules: true }]);
    const element = await toObjectMatchingStep();
    chooseOperation(element, 'Upsert by external ID', 'Session_Key__c');
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="duplicate-rules"]')).not.toBeNull();
    chooseOperation(element, 'Update by a matching field', 'Session_Key__c');
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="duplicate-rules"]')).toBeNull();
    click(element, 'dry-run');
    await flush();
    // A choice the mapping held is not sent where the box is not offered.
    expect(
      JSON.parse(createBatch.mock.calls[0][0].optionsJson).matching.useDuplicateRules
    ).toBeUndefined();
  });

  it('creates a one-object mapping from the objects the user may load and chooses it', async () => {
    getTemplates.mockResolvedValue([TEMPLATE]);
    getLoadableObjects.mockResolvedValue([
      { value: 'Program_Session__c', label: 'Program Session' }
    ]);
    createObjectTemplate.mockResolvedValue(OBJECT_TEMPLATE);
    const element = render();
    await flush();
    await chooseKind(element, 'object');
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
    expect(element.shadowRoot.querySelector('[data-id="template-creates"]').textContent).toContain(
      'Loads: Program Session'
    );
    expect(element.shadowRoot.querySelector('[data-id="next"]').disabled).toBe(false);
    expect(element.shadowRoot.querySelector('[data-id="new-object"]')).toBeNull();
    // One Kind of Record makes a new one-object template; there is nothing to copy.
    expect(element.shadowRoot.querySelector('[data-id="start-copy"]')).toBeNull();
  });

  it('starts a template made from the related records card on upsert', async () => {
    getLoadableObjects.mockResolvedValue([
      { value: 'Program_Session__c', label: 'Program Session' }
    ]);
    createObjectTemplate.mockResolvedValue(OBJECT_TEMPLATE);
    getRelatedOptions.mockResolvedValue([]);
    const element = render();
    await flush();
    await chooseKind(element, 'related');
    const object = element.shadowRoot.querySelector('[data-id="new-object"]');
    object.dispatchEvent(new CustomEvent('change', { detail: { value: 'Program_Session__c' } }));
    const name = element.shadowRoot.querySelector('[data-id="new-template-name"]');
    name.value = 'Sessions and attendees';
    name.dispatchEvent(new CustomEvent('change'));
    await flush();
    click(element, 'create-object-template');
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element, SESSIONS, 'sessions.csv');
    click(element, 'next');
    await flush();
    expect(loadOptions(element).operation).toBe('Upsert by external ID');
  });

  it('starts a template made from the delete card on delete by record ID', async () => {
    getLoadableObjects.mockResolvedValue([
      { value: 'Program_Session__c', label: 'Program Session' }
    ]);
    createObjectTemplate.mockResolvedValue({
      ...OBJECT_TEMPLATE,
      id: 'a06',
      loadOperations: [...OBJECT_TEMPLATE.loadOperations, 'Delete by record Id']
    });
    const element = render();
    await flush();
    await chooseKind(element, 'delete');
    const object = element.shadowRoot.querySelector('[data-id="new-object"]');
    object.dispatchEvent(new CustomEvent('change', { detail: { value: 'Program_Session__c' } }));
    const name = element.shadowRoot.querySelector('[data-id="new-template-name"]');
    name.value = 'Sessions to delete';
    name.dispatchEvent(new CustomEvent('change'));
    await flush();
    click(element, 'create-object-template');
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="template-creates"]').textContent).toContain(
      'Deletes: Program Session'
    );
  });

  it('says so when the delete card makes a template for an object it may not delete', async () => {
    getLoadableObjects.mockResolvedValue([
      { value: 'Program_Session__c', label: 'Program Session' }
    ]);
    createObjectTemplate.mockResolvedValue(OBJECT_TEMPLATE);
    const element = render();
    await flush();
    await chooseKind(element, 'delete');
    const object = element.shadowRoot.querySelector('[data-id="new-object"]');
    object.dispatchEvent(new CustomEvent('change', { detail: { value: 'Program_Session__c' } }));
    const name = element.shadowRoot.querySelector('[data-id="new-template-name"]');
    name.value = 'Sessions';
    name.dispatchEvent(new CustomEvent('change'));
    await flush();
    click(element, 'create-object-template');
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="message"]').textContent).toBe(
      'c.Core_Import_NoDeleteForObject'
    );
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

  it('updates by a field the user chooses, which a column must feed', async () => {
    const element = await toColumnsStep();
    click(element, 'next');
    await flush();
    const options = loadOptions(element);
    expect(options.rowMatchFields).toEqual([
      { value: 'Notes__c', label: 'Notes' },
      { value: 'Session_Key__c', label: 'Session Key' }
    ]);
    options.dispatchEvent(
      new CustomEvent('change', {
        detail: {
          operation: 'Update by a matching field',
          matchField: 'Notes__c',
          lookupNotFound: 'Reject the row'
        }
      })
    );
    await flush();
    // No column feeds Notes, so nothing can find the records.
    expect(element.shadowRoot.querySelector('[data-id="dry-run"]').disabled).toBe(true);
    options.dispatchEvent(
      new CustomEvent('change', {
        detail: {
          operation: 'Update by a matching field',
          matchField: 'Session_Key__c',
          lookupNotFound: 'Reject the row'
        }
      })
    );
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="dry-run"]').disabled).toBe(false);
    click(element, 'dry-run');
    await flush();
    expect(JSON.parse(createBatch.mock.calls[0][0].optionsJson).load).toEqual({
      operation: 'Update by a matching field',
      matchField: 'Session_Key__c',
      lookupNotFound: 'Reject the row',
      severalMatches: 'Reject the row'
    });
  });

  it('sends empty cells clear the field for a one-object column that ticks it', async () => {
    const element = await toColumnsStep();
    const boxes = element.shadowRoot.querySelectorAll('[data-id="blank-clears"]');
    expect(boxes).toHaveLength(3);
    boxes[0].checked = true;
    boxes[0].dispatchEvent(new CustomEvent('change'));
    await flush();
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
    await flush();
    click(element, 'dry-run');
    await flush();
    const columns = JSON.parse(createBatch.mock.calls[0][0].mappingDocument).columns;
    expect(columns[0]).toEqual({
      source: 'Session Key',
      target: 'Record.Session_Key__c',
      blankClears: true
    });
    expect(columns[1].blankClears).toBeUndefined();
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

  it('confirms a delete by file through the bulk delete panel, not Commit', async () => {
    const element = await toColumnsStep();
    const rows = element.shadowRoot.querySelectorAll('[data-id="column-row"]');
    rows[2]
      .querySelector('lightning-combobox')
      .dispatchEvent(new CustomEvent('change', { detail: { value: 'Record.Id' } }));
    await flush();
    click(element, 'next');
    await flush();
    loadOptions(element).dispatchEvent(
      new CustomEvent('change', {
        detail: {
          operation: 'Delete by record Id',
          matchField: '',
          lookupNotFound: 'Reject the row'
        }
      })
    );
    await flush();
    click(element, 'dry-run');
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="commit"]')).toBeNull();
    // A trial commit would bypass the confirmed count, so it is not offered either.
    expect(element.shadowRoot.querySelector('[data-id="trial"]')).toBeNull();
    const panel = element.shadowRoot.querySelector('[data-id="delete-by-file"]');
    expect(panel).not.toBeNull();
    expect(panel.batchId).toBe('a02');
    expect(startCommit).not.toHaveBeenCalled();
  });

  it('writes the results file with one record ID per row', async () => {
    const RealBlob = global.Blob;
    let written;
    global.Blob = function CapturingBlob(parts, options) {
      written = parts.join('');
      return new RealBlob(parts, options);
    };
    global.URL.createObjectURL = jest.fn(() => 'blob:results');
    global.URL.revokeObjectURL = jest.fn();
    jest.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});
    try {
      startCommit.mockResolvedValue({ ...DRY_RUN_BATCH, status: 'Complete', isDryRun: false });
      getRowPage.mockResolvedValue({
        cursor: { token: 'c' },
        rows: [
          {
            id: 'r0',
            rowNumber: 2,
            status: 'Updated',
            resultingRecordId: 'a0S000000000001',
            values: JSON.stringify({ 'Session Key': 'S-1', Program: 'Reading', Notes: 'first' })
          },
          {
            id: 'r1',
            rowNumber: 3,
            status: 'Rejected',
            errorMessage: 'No Program is named Math.',
            values: JSON.stringify({ 'Session Key': 'S-2', Program: 'Math', Notes: '' })
          }
        ],
        nextIndex: 2,
        total: 2,
        hasMore: false
      });
      const element = await toColumnsStep();
      click(element, 'next');
      await flush();
      click(element, 'dry-run');
      await flush();
      element.shadowRoot.querySelector('[data-id="commit"]').click();
      await flush();
      click(element, 'download-results');
      await flush();

      const lines = written.split('\r\n').filter((line) => line.length > 0);
      expect(lines).toEqual([
        '﻿c.Core_Import_ResultsRow,c.Core_Import_ResultsOutcome,' +
          'c.Core_Import_ResultsRecordId,c.Core_Import_ResultsReason,Session Key,Program,Notes',
        '2,Updated,a0S000000000001,,S-1,Reading,first',
        '3,Rejected,,No Program is named Math.,S-2,Math,'
      ]);
    } finally {
      global.Blob = RealBlob;
      HTMLAnchorElement.prototype.click.mockRestore();
    }
  });

  it('offers the related record fields and sends the related records under a key', async () => {
    getTemplates.mockResolvedValue([
      {
        ...OBJECT_TEMPLATE,
        loadOperation: 'Upsert by external ID',
        loadMatchField: 'Session_Key__c',
        related: 'Attendance__c.Session__c'
      }
    ]);
    getRelatedOptions.mockResolvedValue([
      { value: 'Attendance__c.Session__c', label: 'Attendance (Session)' }
    ]);
    getRelatedFields.mockResolvedValue([
      { value: 'Related.Status__c', label: 'Attendance: Status', isLookup: false, lookupFields: [] }
    ]);
    const element = await toColumnsStep();
    expect(getRelatedFields).toHaveBeenCalledWith({
      templateId: 'a05',
      related: 'Attendance__c.Session__c'
    });
    const rows = element.shadowRoot.querySelectorAll('[data-id="column-row"]');
    const picker = rows[2].querySelector('lightning-combobox');
    expect(picker.options.map((o) => o.value)).toContain('Related.Status__c');
    picker.dispatchEvent(new CustomEvent('change', { detail: { value: 'Related.Status__c' } }));
    await flush();
    click(element, 'next');
    await flush();
    const options = loadOptions(element);
    expect(options.related).toBe('Attendance__c.Session__c');
    expect(options.relatedOptions).toEqual([
      { value: 'Attendance__c.Session__c', label: 'Attendance (Session)' }
    ]);
    click(element, 'dry-run');
    await flush();
    const call = createBatch.mock.calls[0][0];
    expect(JSON.parse(call.optionsJson).load.related).toBe('Attendance__c.Session__c');
    expect(JSON.parse(call.mappingDocument).columns[2].target).toBe('Related.Status__c');
  });

  it('drops the related records under Insert, which has no parent key', async () => {
    getRelatedOptions.mockResolvedValue([]);
    getRelatedFields.mockResolvedValue([]);
    const element = await toColumnsStep();
    click(element, 'next');
    await flush();
    loadOptions(element).dispatchEvent(
      new CustomEvent('change', {
        detail: {
          operation: 'Insert',
          matchField: '',
          lookupNotFound: 'Reject the row',
          related: 'Attendance__c.Session__c'
        }
      })
    );
    await flush();
    click(element, 'dry-run');
    await flush();
    expect(JSON.parse(createBatch.mock.calls[0][0].optionsJson).load.related).toBeUndefined();
  });

  /** Commits the default file into an import with one rejected row the user may retry. */
  async function toRetryableResults() {
    startCommit.mockResolvedValue({
      ...DRY_RUN_BATCH,
      status: 'Complete',
      isDryRun: false,
      rejected: 1,
      canRetry: true,
      retrying: false
    });
    const element = await open();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    click(element, 'next');
    await flush();
    click(element, 'dry-run');
    await flush();
    click(element, 'commit');
    await flush();
    return element;
  }

  async function chooseRetryFile(element, text) {
    const input = element.shadowRoot.querySelector('[data-id="retry-file"]');
    const file = new File([text], 'fixed.csv', { type: 'text/csv' });
    Object.defineProperty(input, 'files', { value: [file], configurable: true });
    input.dispatchEvent(new CustomEvent('change'));
    await flush();
  }

  it('retries the fixed rejected rows into the same import and previews only them', async () => {
    const retrying = { ...DRY_RUN_BATCH, retrying: true, canRetry: true };
    openRetry.mockResolvedValue({ ...retrying, status: 'Retrying', isFinished: false });
    startDryRun.mockResolvedValue(retrying);
    const element = await toRetryableResults();
    stageRows.mockClear();
    startDryRun.mockClear();

    await chooseRetryFile(element, 'Row,Last Name,Email,Notes,Reason\n3,Okafor,ben@example.org,,x');

    expect(openRetry).toHaveBeenCalledWith({ batchId: 'a02' });
    expect(stageRows).toHaveBeenCalledTimes(1);
    expect(stageRows.mock.calls[0][0].batchId).toBe('a02');
    expect(stageRows.mock.calls[0][0].firstRowNumber).toBe(2);
    expect(JSON.parse(stageRows.mock.calls[0][0].rowsJson)).toHaveLength(1);
    expect(startDryRun).toHaveBeenCalledWith({ batchId: 'a02' });
    expect(element.shadowRoot.querySelector('[data-id="commit"]').disabled).toBe(false);
    // The retry belongs to a committed import, so there is no earlier step to go back to.
    expect(element.shadowRoot.querySelector('[data-id="back"]')).toBeNull();
  });

  it('refuses a fixed rows file missing a column of the original, and opens no retry', async () => {
    const element = await toRetryableResults();
    await chooseRetryFile(element, 'Last Name,Notes\nOkafor,');
    expect(openRetry).not.toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('[data-id="message"]').textContent).toBe(
      'c.Core_Import_RetryColumnsMissing'
    );
  });

  it('offers no retry when the import cannot take one', async () => {
    startCommit.mockResolvedValue({
      ...DRY_RUN_BATCH,
      status: 'Complete',
      isDryRun: false,
      canRetry: false
    });
    const element = await open();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    click(element, 'next');
    await flush();
    click(element, 'dry-run');
    await flush();
    click(element, 'commit');
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="start-over"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="retry-file"]')).toBeNull();
  });
});
