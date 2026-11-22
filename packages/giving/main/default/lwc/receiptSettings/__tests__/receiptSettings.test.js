import { createElement } from 'lwc';
import { graphql } from 'lightning/graphql';
import ReceiptSettings from 'c/receiptSettings';
import getDefaultStatementYear from '@salesforce/apex/ReceiptController.getDefaultStatementYear';
import startStatementRun from '@salesforce/apex/ReceiptController.startStatementRun';
import getCanManageTemplates from '@salesforce/apex/ReceiptController.getCanManageTemplates';
import restoreDefaultTemplates from '@salesforce/apex/ReceiptController.restoreDefaultTemplates';
import saveTemplate from '@salesforce/apex/ReceiptController.saveTemplate';
import previewTemplate from '@salesforce/apex/ReceiptController.previewTemplate';

jest.mock(
  '@salesforce/apex/ReceiptController.getDefaultStatementYear',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ReceiptController.getCanManageTemplates',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ReceiptController.restoreDefaultTemplates',
  () => ({ default: jest.fn(() => Promise.resolve([])) }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ReceiptController.saveTemplate',
  () => ({ default: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ReceiptController.previewTemplate',
  () => ({ default: jest.fn(() => Promise.resolve('<p>Dear Alex Sample,</p>')) }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ReceiptController.activateTemplate',
  () => ({ default: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ReceiptController.startStatementRun',
  () => ({ default: jest.fn(() => Promise.resolve({ id: 'a03000000000001' })) }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Core_Format_Parenthetical', () => ({ default: '{0} ({1})' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Giving_Receipt_LetterOptionOff',
  () => ({ default: '{0} ({1}), not in use' }),
  { virtual: true }
);

const TEMPLATES = [
  {
    id: 'a04000000000001',
    name: 'Per gift receipt',
    type: 'Per gift',
    body: '<p>Dear {{DonorName}},</p>',
    active: true
  },
  {
    id: 'a04000000000002',
    name: 'Consolidated statement',
    type: 'Consolidated statement',
    body: '<p>{{GiftLines}}</p>',
    active: false
  }
];

const field = (value) => ({ value });

/**
 * The letters and the runs as their two GraphQL wires receive them. The test adapter sends one
 * answer to every graphql wire, so each answer holds both lists and each wire reads its own.
 */
function emitLists(templates, runs, refresh) {
  graphql.emit(
    {
      uiapi: {
        query: {
          Receipt_Template__c: {
            edges: templates.map((letter) => ({
              node: {
                Id: letter.id,
                Name: field(letter.name),
                Type__c: field(letter.type),
                Body__c: field(letter.body),
                Active__c: field(letter.active)
              }
            }))
          },
          Receipt_Run__c: {
            edges: runs.map((run) => ({
              node: {
                Id: run.id,
                Name: field(run.name),
                Statement_Year__c: field(run.statementYear),
                Status__c: field(run.status),
                Donors_Processed__c: field(null),
                Receipts_Issued__c: field(null),
                Errors__c: field(run.errors)
              }
            }))
          }
        }
      }
    },
    undefined,
    refresh
  );
}

function build() {
  const element = createElement('c-receipt-settings', { is: ReceiptSettings });
  document.body.appendChild(element);
  return element;
}

function flush() {
  return Promise.resolve();
}

function byId(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

async function loaded(canManage) {
  const element = build();
  emitLists(TEMPLATES, []);
  getCanManageTemplates.emit(canManage);
  await flush();
  return element;
}

describe('c-receipt-settings', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('opens with the page header titled Receipt Letters from the help catalog', async () => {
    const element = await loaded(true);

    const shell = byId(element, 'shell');
    expect(shell.title).toBeTruthy();
    expect(shell.purpose).toBeTruthy();
  });

  it('loads the first letter into a rich text editor, not a plain text box', async () => {
    const element = await loaded(true);

    const editor = byId(element, 'editor');
    expect(editor.tagName).toBe('LIGHTNING-INPUT-RICH-TEXT');
    expect(editor.value).toBe('<p>Dear {{DonorName}},</p>');
    expect(editor.formats).not.toContain('image');
    expect(element.shadowRoot.querySelector('lightning-textarea')).toBeNull();
  });

  it('names each letter and says which one is not in use', async () => {
    const element = await loaded(true);

    const labels = byId(element, 'letter').options.map((option) => option.label);
    expect(labels).toEqual([
      'Per gift receipt (Per gift)',
      'Consolidated statement (Consolidated statement), not in use'
    ]);
  });

  it('saves what the editor holds', async () => {
    const element = await loaded(true);

    const editor = byId(element, 'editor');
    editor.value = '<p>Thank you, {{DonorName}}.</p>';
    editor.dispatchEvent(new CustomEvent('change'));
    await flush();
    byId(element, 'save').click();
    await flush();

    expect(saveTemplate).toHaveBeenCalledWith({
      templateId: 'a04000000000001',
      body: '<p>Thank you, {{DonorName}}.</p>'
    });
  });

  it('previews the unsaved draft for its kind of letter, and shows the result', async () => {
    const element = await loaded(true);

    byId(element, 'preview').click();
    await flush();
    await flush();

    expect(previewTemplate).toHaveBeenCalledWith({
      receiptType: 'Per gift',
      body: '<p>Dear {{DonorName}},</p>'
    });
    const shown = byId(element, 'preview-box').querySelector('lightning-formatted-rich-text');
    expect(shown.value).toBe('<p>Dear Alex Sample,</p>');
  });

  it('offers to switch on a letter that is not in use', async () => {
    const element = await loaded(true);
    expect(byId(element, 'use-letter')).toBeNull();

    const picker = byId(element, 'letter');
    picker.dispatchEvent(new CustomEvent('change', { detail: { value: 'a04000000000002' } }));
    await flush();

    expect(byId(element, 'use-letter')).not.toBeNull();
    expect(byId(element, 'editor').value).toBe('<p>{{GiftLines}}</p>');
  });

  it('offers to restore the shipped letters when the org has none', async () => {
    const refresh = jest.fn(() => Promise.resolve());
    const element = build();
    emitLists([], [], refresh);
    getCanManageTemplates.emit(true);
    await flush();

    expect(byId(element, 'editor')).toBeNull();
    byId(element, 'restore').click();
    await flush();
    await flush();

    expect(restoreDefaultTemplates).toHaveBeenCalled();
    expect(refresh).toHaveBeenCalled();
  });

  it('says so, and locks the editor, for somebody who cannot manage settings', async () => {
    const element = await loaded(false);

    expect(byId(element, 'read-only').variant).toBe('info');
    expect(byId(element, 'save').disabled).toBe(true);
    expect(byId(element, 'editor').disabled).toBe(true);
  });

  it('explains the disabled restore button when there are no letters and no permission', async () => {
    const element = build();
    emitLists([], []);
    getCanManageTemplates.emit(false);
    await flush();

    expect(byId(element, 'no-templates')).not.toBeNull();
    expect(byId(element, 'read-only').variant).toBe('info');
    expect(byId(element, 'restore').disabled).toBe(true);
  });

  it('starts a run for the year the settings name', async () => {
    const element = await loaded(true);
    getDefaultStatementYear.emit(2026);
    await flush();

    byId(element, 'generate').click();
    await flush();
    await flush();

    expect(startStatementRun).toHaveBeenCalledWith({ statementYear: 2026 });
    expect(byId(element, 'result').variant).toBe('success');
    expect(byId(element, 'result').message).toBe('c.Giving_Receipt_StartedMessage');
  });

  it('keeps a refused save on the page as an error notice', async () => {
    saveTemplate.mockRejectedValueOnce({ body: { message: 'You cannot change settings.' } });
    const element = await loaded(true);

    byId(element, 'save').click();
    await flush();
    await flush();

    expect(byId(element, 'result').variant).toBe('error');
    expect(byId(element, 'result').message).toBe('You cannot change settings.');
  });

  it('shows each run status as a badge, and an empty state before the first run', async () => {
    const element = await loaded(true);
    expect(byId(element, 'no-runs').heading).toBe('c.Giving_Receipt_NoRuns');

    emitLists(TEMPLATES, [
      { id: 'r1', name: 'RR-1', statementYear: 2025, status: 'Completed with errors', errors: 2 },
      { id: 'r2', name: 'RR-2', statementYear: 2025, status: 'Failed', errors: 0 }
    ]);
    await flush();

    const badges = element.shadowRoot.querySelectorAll('[data-id="run-status"]');
    expect([...badges].map((badge) => badge.status)).toEqual(['warning', 'failed']);
    expect(badges[0].label).toBe('Completed with errors');
    expect(byId(element, 'no-runs')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="run"]').textContent).toContain('2025');
  });

  it('says the letters could not be read when the query fails', async () => {
    const element = build();
    graphql.emitErrors([{ message: 'No access' }]);
    getCanManageTemplates.emit(true);
    await flush();

    expect(byId(element, 'load-error').message).toBe('c.Giving_Receipt_UnexpectedError');
  });
});
