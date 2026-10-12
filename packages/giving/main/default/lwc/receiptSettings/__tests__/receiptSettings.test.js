import { createElement } from 'lwc';
import ReceiptSettings from 'c/receiptSettings';
import getTemplates from '@salesforce/apex/ReceiptController.getTemplates';
import getRuns from '@salesforce/apex/ReceiptController.getRuns';
import getDefaultStatementYear from '@salesforce/apex/ReceiptController.getDefaultStatementYear';
import startStatementRun from '@salesforce/apex/ReceiptController.startStatementRun';
import getCanManageTemplates from '@salesforce/apex/ReceiptController.getCanManageTemplates';
import restoreDefaultTemplates from '@salesforce/apex/ReceiptController.restoreDefaultTemplates';
import saveTemplate from '@salesforce/apex/ReceiptController.saveTemplate';
import previewTemplate from '@salesforce/apex/ReceiptController.previewTemplate';

jest.mock(
  '@salesforce/apex/ReceiptController.getTemplates',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ReceiptController.getRuns',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
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
jest.mock('@salesforce/apex', () => ({ refreshApex: jest.fn(() => Promise.resolve()) }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Giving_Receipt_LetterOption', () => ({ default: '{0} ({1})' }), {
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
  getTemplates.emit(TEMPLATES);
  getRuns.emit([]);
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
    const element = build();
    getTemplates.emit([]);
    getRuns.emit([]);
    getCanManageTemplates.emit(true);
    await flush();

    expect(byId(element, 'editor')).toBeNull();
    byId(element, 'restore').click();
    await flush();

    expect(restoreDefaultTemplates).toHaveBeenCalled();
  });

  it('says so, and locks the editor, for somebody who cannot manage settings', async () => {
    const element = await loaded(false);

    expect(byId(element, 'read-only')).not.toBeNull();
    expect(byId(element, 'save').disabled).toBe(true);
    expect(byId(element, 'editor').disabled).toBe(true);
  });

  it('starts a run for the year the settings name', async () => {
    const element = await loaded(true);
    getDefaultStatementYear.emit(2026);
    await flush();

    byId(element, 'generate').click();
    await flush();

    expect(startStatementRun).toHaveBeenCalledWith({ statementYear: 2026 });
  });
});
