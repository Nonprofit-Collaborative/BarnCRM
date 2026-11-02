import { createElement } from 'lwc';
import GrantProgram from 'c/grantProgram';
import getProgram from '@salesforce/apex/GrantProgramController.getProgram';
import setProgram from '@salesforce/apex/GrantProgramController.setProgram';

jest.mock('@salesforce/apex/GrantProgramController.getProgram', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/GrantProgramController.setProgram', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Funders_Program_None', () => ({ default: 'No program' }), {
  virtual: true
});

const GRANT_ID = 'a01000000000001AAA';
const PROGRAM_ID = 'a02000000000001AAA';

const CARD = {
  available: true,
  canEdit: true,
  programId: null,
  programName: null,
  missing: false,
  options: [{ label: 'After School', value: PROGRAM_ID }]
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render(card = CARD) {
  getProgram.mockResolvedValue(card);
  const element = createElement('c-grant-program', { is: GrantProgram });
  element.recordId = GRANT_ID;
  document.body.appendChild(element);
  await flush();
  return element;
}

const one = (element, selector) => element.shadowRoot.querySelector(selector);

describe('c-grant-program', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('offers No program and every program, and saves the choice', async () => {
    setProgram.mockResolvedValue();
    const element = await render();
    const combo = one(element, '[data-id="program"]');
    expect(combo.options.map((option) => option.label)).toEqual(['No program', 'After School']);
    expect(one(element, '[data-id="save"]').disabled).toBe(true);

    combo.dispatchEvent(new CustomEvent('change', { detail: { value: PROGRAM_ID } }));
    await flush();
    expect(one(element, '[data-id="save"]').disabled).toBe(false);
    one(element, '[data-id="save"]').click();
    await flush();

    expect(setProgram).toHaveBeenCalledWith({ grantId: GRANT_ID, programId: PROGRAM_ID });
    expect(getProgram).toHaveBeenCalledTimes(2);
  });

  it('clears the program with No program', async () => {
    setProgram.mockResolvedValue();
    const element = await render({ ...CARD, programId: PROGRAM_ID, programName: 'After School' });
    one(element, '[data-id="program"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: '' } })
    );
    await flush();
    one(element, '[data-id="save"]').click();
    await flush();
    expect(setProgram).toHaveBeenCalledWith({ grantId: GRANT_ID, programId: null });
  });

  it('says so without the Programs module', async () => {
    const element = await render({ ...CARD, available: false, canEdit: false, options: [] });
    expect(one(element, '[data-id="not-installed"]')).not.toBeNull();
    expect(one(element, '[data-id="program"]')).toBeNull();
  });

  it('says so when the named program has gone', async () => {
    const element = await render({ ...CARD, programId: PROGRAM_ID, missing: true });
    expect(one(element, '[data-id="missing"]')).not.toBeNull();
  });

  it('shows a reader the program by name', async () => {
    const element = await render({ ...CARD, canEdit: false, programName: 'After School' });
    expect(one(element, '[data-id="read-only"]').textContent.trim()).toBe('After School');
    expect(one(element, '[data-id="program"]')).toBeNull();
  });

  it('shows the reason when the card cannot load or save', async () => {
    getProgram.mockRejectedValue({ body: { message: 'No access' } });
    const element = createElement('c-grant-program', { is: GrantProgram });
    element.recordId = GRANT_ID;
    document.body.appendChild(element);
    await flush();
    expect(one(element, '[data-id="error-message"]').textContent.trim()).toBe('No access');
  });
});
