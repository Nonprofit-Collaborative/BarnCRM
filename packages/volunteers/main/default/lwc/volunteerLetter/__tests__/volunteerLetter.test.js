import { createElement } from 'lwc';
import Toast from 'lightning/toast';
import VolunteerLetter from 'c/volunteerLetter';
import getActionContext from '@salesforce/apex/VolunteerLetterController.getActionContext';
import previewLetter from '@salesforce/apex/VolunteerLetterController.preview';
import generateLetter from '@salesforce/apex/VolunteerLetterController.generate';
import BAD_PERIOD from '@salesforce/label/c.Volunteers_Letter_BadPeriod';
import ACTION_FAILED from '@salesforce/label/c.Volunteers_Letter_ActionFailed';
import NO_ACTIVE_TEMPLATE from '@salesforce/label/c.Volunteers_Letter_NoActiveTemplate';

jest.mock(
  '@salesforce/apex/VolunteerLetterController.getActionContext',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock('@salesforce/apex/VolunteerLetterController.preview', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/VolunteerLetterController.generate', () => ({ default: jest.fn() }), {
  virtual: true
});

const PERSON_ID = '003000000000001';
const TEMPLATE_ID = 'a0X000000000001';
const READY = {
  canManage: true,
  isPerson: true,
  templates: [{ label: 'Hours letter (Hours letter)', value: TEMPLATE_ID }]
};

function build() {
  const element = createElement('c-volunteer-letter', { is: VolunteerLetter });
  element.recordId = PERSON_ID;
  document.body.appendChild(element);
  return element;
}

function find(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

/** Lets the Apex promise, the handler after it and the re-render all settle. */
async function flush() {
  for (let i = 0; i < 5; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
}

describe('c-volunteer-letter', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('offers the active template and a labelled period', async () => {
    const element = build();
    getActionContext.emit(READY);
    await flush();

    expect(find(element, 'template').value).toBe(TEMPLATE_ID);
    expect(find(element, 'from').label).toBeTruthy();
    expect(find(element, 'to').label).toBeTruthy();
    expect(find(element, 'generate').disabled).toBe(false);
  });

  it('says why on an account that is not a person, and offers nothing', async () => {
    const element = build();
    getActionContext.emit({ canManage: true, isPerson: false, templates: [] });
    await flush();

    expect(find(element, 'blocker')).not.toBeNull();
    expect(find(element, 'template')).toBeNull();
    expect(find(element, 'generate').disabled).toBe(true);
  });

  it('says why without Manage Volunteers', async () => {
    const element = build();
    getActionContext.emit({ canManage: false, isPerson: true, templates: [] });
    await flush();

    expect(find(element, 'blocker')).not.toBeNull();
    expect(find(element, 'template')).toBeNull();
  });

  it('shows the preview for the chosen period', async () => {
    previewLetter.mockResolvedValue({ body: '<p>5 hours</p>', skipReason: null });
    const element = build();
    getActionContext.emit(READY);
    await flush();

    find(element, 'from').dispatchEvent(
      new CustomEvent('change', { detail: { value: '2026-03-01' } })
    );
    find(element, 'preview-button').click();
    await flush();

    expect(previewLetter).toHaveBeenCalledWith(
      expect.objectContaining({
        recordId: PERSON_ID,
        templateId: TEMPLATE_ID,
        fromDate: '2026-03-01'
      })
    );
    expect(find(element, 'preview')).not.toBeNull();
  });

  it('tells the coordinator when the person has no approved hours', async () => {
    generateLetter.mockResolvedValue({ versionId: null, skipReason: 'No approved hours.' });
    const element = build();
    getActionContext.emit(READY);
    await flush();

    find(element, 'generate').click();
    await flush();

    expect(find(element, 'notice').textContent).toBe('No approved hours.');
  });

  it('saves the letter and confirms it', async () => {
    generateLetter.mockResolvedValue({ versionId: '068000000000001', skipReason: null });
    const toast = jest.spyOn(Toast, 'show');
    const element = build();
    getActionContext.emit(READY);
    await flush();

    find(element, 'generate').click();
    await flush();

    expect(generateLetter).toHaveBeenCalled();
    expect(toast.mock.calls[0][0].variant).toBe('success');
  });

  it('shows a spinner until the first answer arrives', async () => {
    const element = build();
    expect(find(element, 'loading')).not.toBeNull();
    getActionContext.emit(READY);
    await flush();
    expect(find(element, 'loading')).toBeNull();
  });

  it('refuses a From date after the To date inline, with no server call', async () => {
    const element = build();
    getActionContext.emit(READY);
    await flush();

    find(element, 'from').dispatchEvent(
      new CustomEvent('change', { detail: { value: '2026-04-01' } })
    );
    find(element, 'to').dispatchEvent(
      new CustomEvent('change', { detail: { value: '2026-03-01' } })
    );
    find(element, 'preview-button').click();
    await flush();
    expect(find(element, 'notice').textContent).toBe(BAD_PERIOD);

    find(element, 'generate').click();
    await flush();
    expect(find(element, 'notice').textContent).toBe(BAD_PERIOD);
    expect(previewLetter).not.toHaveBeenCalled();
    expect(generateLetter).not.toHaveBeenCalled();
  });

  it('says to ask an administrator when no template is active', async () => {
    const element = build();
    getActionContext.emit({ canManage: true, isPerson: true, templates: [] });
    await flush();

    expect(find(element, 'blocker').textContent).toBe(NO_ACTIVE_TEMPLATE);
  });

  it('warns before the letter when the organization legal name is blank', async () => {
    const element = build();
    getActionContext.emit({ ...READY, organizationNameBlank: true });
    await flush();
    expect(find(element, 'legal-name-warning')).not.toBeNull();
  });

  it('does not warn when the legal name is filled in', async () => {
    const element = build();
    getActionContext.emit({ ...READY, organizationNameBlank: false });
    await flush();
    expect(find(element, 'legal-name-warning')).toBeNull();
  });

  it('shows a plain sentence for an error with no readable message', async () => {
    generateLetter.mockRejectedValue({ body: { message: { code: 500 } } });
    const element = build();
    getActionContext.emit(READY);
    await flush();

    find(element, 'generate').click();
    await flush();

    expect(find(element, 'notice').textContent).toBe(ACTION_FAILED);
    expect(find(element, 'notice').textContent).not.toContain('[object Object]');
  });

  it('shows a refusal from the server', async () => {
    generateLetter.mockRejectedValue({ body: { message: 'Choose a From date.' } });
    const element = build();
    getActionContext.emit(READY);
    await flush();

    find(element, 'generate').click();
    await flush();

    expect(find(element, 'notice').textContent).toBe('Choose a From date.');
  });
});
