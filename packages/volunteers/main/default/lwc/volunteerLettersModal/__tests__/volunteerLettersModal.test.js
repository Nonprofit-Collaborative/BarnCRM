import { createElement } from 'lwc';
import VolunteerLettersModal from 'c/volunteerLettersModal';
import getListContext from '@salesforce/apex/VolunteerLetterController.getListContext';
import startLetters from '@salesforce/apex/VolunteerLetterController.startLetters';
import NEED_PERMISSION from '@salesforce/label/c.Volunteers_Letter_NeedManagePermission';
import BAD_PERIOD from '@salesforce/label/c.Volunteers_Letter_BadPeriod';
import { setHelpTextForTest, clearHelpTextForTest } from 'c/barnHelpText';
import { periodDates, LAST_YEAR, THIS_YEAR } from 'c/volunteerPeriods';

jest.mock(
  '@salesforce/apex/VolunteerLetterController.getListContext',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/VolunteerLetterController.startLetters',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const TEMPLATE_ID = 'a0X000000000001';
const PERSON_ID = '003000000000001';
const READY = {
  canManage: true,
  personObject: 'Contact',
  templates: [{ label: 'Hours letter', value: TEMPLATE_ID }]
};

async function flush() {
  for (let i = 0; i < 5; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
}

/** The dialog as Approve Hours opens it; closed records what it resolved with. */
async function open(context = READY) {
  getListContext.mockResolvedValue(context);
  const element = createElement('c-volunteer-letters-modal', { is: VolunteerLettersModal });
  const closed = jest.fn();
  element.addEventListener('close', (event) => closed(event.detail));
  document.body.appendChild(element);
  await flush();
  return { element, closed, root: element.shadowRoot };
}

function find(root, id) {
  return root.querySelector(`[data-id="${id}"]`);
}

function change(root, id, detail) {
  find(root, id).dispatchEvent(new CustomEvent('change', { detail }));
}

describe('c-volunteer-letters-modal', () => {
  beforeEach(() => {
    setHelpTextForTest({
      Volunteers_Letters_Started: 'Letters are being made for {0} people.',
      Volunteers_Letters_Nobody: 'Nobody has approved hours in this period.',
      Volunteers_Letters_ChooseSomeone: 'Choose at least one person.'
    });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    clearHelpTextForTest();
    jest.clearAllMocks();
  });

  it('starts letters for everyone this year and resolves with the sentence', async () => {
    startLetters.mockResolvedValue(12);
    const { root, closed } = await open();
    expect(find(root, 'template').value).toBe(TEMPLATE_ID);
    expect(find(root, 'person-picker')).toBeNull();

    find(root, 'make').click();
    await flush();

    const dates = periodDates(THIS_YEAR);
    expect(startLetters).toHaveBeenCalledWith({
      templateId: TEMPLATE_ID,
      fromDate: dates.fromDate,
      toDate: dates.toDate,
      personIds: []
    });
    expect(closed).toHaveBeenCalledWith('Letters are being made for 12 people.');
  });

  it('sends only the chosen people, each once, for last year', async () => {
    startLetters.mockResolvedValue(1);
    const { root, closed } = await open();
    change(root, 'period', { value: LAST_YEAR });
    change(root, 'who', { value: 'chosen' });
    await flush();

    find(root, 'make').click();
    await flush();
    expect(find(root, 'notice').message).toBe('Choose at least one person.');
    expect(startLetters).not.toHaveBeenCalled();

    change(root, 'person-picker', { recordId: PERSON_ID });
    change(root, 'person-picker', { recordId: PERSON_ID });
    await flush();
    expect(root.querySelectorAll('lightning-pill')).toHaveLength(1);

    find(root, 'make').click();
    await flush();
    const dates = periodDates(LAST_YEAR);
    expect(startLetters).toHaveBeenCalledWith({
      templateId: TEMPLATE_ID,
      fromDate: dates.fromDate,
      toDate: dates.toDate,
      personIds: [PERSON_ID]
    });
    expect(closed).toHaveBeenCalled();
  });

  it('says so when nobody has hours, and refuses a reversed period', async () => {
    startLetters.mockResolvedValue(0);
    const { root, closed } = await open();
    find(root, 'make').click();
    await flush();
    expect(find(root, 'notice').message).toBe('Nobody has approved hours in this period.');
    expect(closed).not.toHaveBeenCalled();

    change(root, 'period', { value: 'custom' });
    await flush();
    change(root, 'from', { value: '2026-05-01' });
    change(root, 'to', { value: '2026-04-01' });
    find(root, 'make').click();
    await flush();
    expect(find(root, 'notice').message).toBe(BAD_PERIOD);
  });

  it('tells someone without Manage Volunteers why not', async () => {
    const { root } = await open({ canManage: false, templates: [] });
    expect(find(root, 'blocker').message).toBe(NEED_PERMISSION);
    expect(find(root, 'make').disabled).toBe(true);
  });
});
