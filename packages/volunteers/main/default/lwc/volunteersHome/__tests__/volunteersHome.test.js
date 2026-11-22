import { createElement } from 'lwc';

const mockNavigate = jest.fn();

jest.mock(
  'lightning/navigation',
  () => {
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) =>
      class extends Base {
        [Navigate](...args) {
          mockNavigate(...args);
        }
      };
    NavigationMixin.Navigate = Navigate;
    return { NavigationMixin, __esModule: true };
  },
  { virtual: true }
);
import VolunteersHome from 'c/volunteersHome';
import getHome from '@salesforce/apex/VolunteersHomeController.getHome';
import getFirstRun from '@salesforce/apex/VolunteersHomeController.getFirstRun';
import { setHelpTextForTest, clearHelpTextForTest } from 'c/barnHelpText';
import { badgeStatusFor, pageReferenceFor, valueFor } from '../volunteersHomeModel';
// The object info test wire adapter is emitted to on purpose, which is how a wired component is
// driven from a test.
/* eslint-disable @lwc/lwc/no-unexpected-wire-adapter-usages */
import { getObjectInfo } from 'lightning/uiObjectInfoApi';

jest.mock('@salesforce/apex/VolunteersHomeController.getHome', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/VolunteersHomeController.getFirstRun', () => ({ default: jest.fn() }), {
  virtual: true
});

const TILES = [
  {
    name: 'hoursThisMonth',
    label: 'Hours This Month',
    value: 42.5,
    badgeLabel: 'Approved',
    badgeStatus: 'done',
    objectApiName: 'Volunteer_Hours__c',
    filterName: 'All_Volunteer_Hours'
  },
  {
    name: 'hoursToApprove',
    label: 'Volunteer Hours',
    value: 0,
    badgeLabel: 'Submitted',
    badgeStatus: 'due',
    objectApiName: 'Volunteer_Hours__c',
    tabName: 'Volunteer_Approve_Hours'
  }
];

async function flush() {
  for (let i = 0; i < 5; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
}

function build() {
  const element = createElement('c-volunteers-home', { is: VolunteersHome });
  document.body.appendChild(element);
  return element;
}

describe('c-volunteers-home', () => {
  beforeEach(() => {
    setHelpTextForTest({
      Volunteers_Home_LoadError: 'The figures were not loaded.',
      Volunteers_Home_FirstRunHeading: 'Set Up Your First Volunteer Job',
      Volunteers_Home_FirstRunNewJob: 'New Volunteer Job',
      Volunteers_Home_FirstRunImport: 'Import a File'
    });
    getFirstRun.mockResolvedValue({ show: false, canImport: false });
  });

  it('offers a first job and a file import before any job exists', async () => {
    getHome.mockResolvedValue(TILES);
    getFirstRun.mockResolvedValue({ show: true, canImport: true });
    const element = build();
    await flush();

    const panel = element.shadowRoot.querySelector('[data-id="first-run"]');
    expect(panel.heading).toBe('Set Up Your First Volunteer Job');
    expect(panel.illustration).toBe('setup');
    expect(element.shadowRoot.querySelector('[data-id="tiles"]')).toBeNull();
    element.shadowRoot.querySelector('[data-id="first-run-job"]').click();
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__objectPage',
      attributes: { objectApiName: 'Volunteer_Job__c', actionName: 'new' }
    });
    element.shadowRoot.querySelector('[data-id="first-run-import"]').click();
    await flush();
    expect(mockNavigate).toHaveBeenLastCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'Import' }
    });
  });

  it('shows the figures when the first-run state cannot be read', async () => {
    getHome.mockResolvedValue(TILES);
    getFirstRun.mockRejectedValue({ body: { message: 'no' } });
    const element = build();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="first-run"]')).toBeNull();
    expect(element.shadowRoot.querySelectorAll('c-barn-stat-tile')).toHaveLength(2);
  });

  it('uses the shared page shell and explains the empty charts only when nothing is counted', async () => {
    setHelpTextForTest({
      Volunteers_Home_Title: 'Volunteers Home',
      Volunteers_Home_Purpose: 'See hours.',
      Volunteers_Home_ChartsEmpty: 'Charts fill in later.'
    });
    getHome.mockResolvedValue(TILES);
    let element = build();
    await flush();
    const shell = element.shadowRoot.querySelector('c-barn-page-shell');
    expect(shell.title).toBe('Volunteers Home');
    expect(shell.titleHidden).toBeFalsy();
    expect(element.shadowRoot.querySelector('[data-id="charts-note"]')).toBeNull();

    document.body.removeChild(element);
    getHome.mockResolvedValue(TILES.map((tile) => ({ ...tile, value: 0 })));
    element = build();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="charts-note"]').message).toBe(
      'Charts fill in later.'
    );
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    clearHelpTextForTest();
    jest.clearAllMocks();
  });

  it('shows each figure and opens its list or tab', async () => {
    getHome.mockResolvedValue(TILES);
    const element = build();
    await flush();

    const tiles = element.shadowRoot.querySelectorAll('c-barn-stat-tile');
    expect(tiles).toHaveLength(2);
    expect(tiles[0].value).toBe(42.5);
    expect(tiles[0].badgeVariant).toBe('done');
    expect(tiles[1].badgeVariant).toBe('neutral');

    tiles[1].dispatchEvent(new CustomEvent('select', { detail: { name: 'hoursToApprove' } }));
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'Volunteer_Approve_Hours' }
    });
  });

  it('shows New Volunteer Job in the header only to someone who may create jobs', async () => {
    getHome.mockResolvedValue(TILES);
    const element = build();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="new-job"]')).toBeNull();

    getObjectInfo.emit({ apiName: 'Volunteer_Job__c', createable: true });
    await flush();
    const button = element.shadowRoot.querySelector('[data-id="new-job"]');
    expect(button.label).toBe('New Volunteer Job');
    button.click();
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__objectPage',
      attributes: { objectApiName: 'Volunteer_Job__c', actionName: 'new' }
    });
  });

  it('keeps New Volunteer Job out of the header while the first-run panel offers it', async () => {
    getHome.mockResolvedValue(TILES);
    getFirstRun.mockResolvedValue({ show: true, canImport: false });
    const element = build();
    await flush();
    getObjectInfo.emit({ apiName: 'Volunteer_Job__c', createable: true });
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="new-job"]')).toBeNull();
  });

  it('says so when the figures do not load', async () => {
    getHome.mockRejectedValue({ body: { message: 'no' } });
    const element = build();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="error"]').message).toBe(
      'The figures were not loaded.'
    );
  });

  it('opens a list view and shows a capped count with a plus', () => {
    expect(pageReferenceFor(TILES[0])).toEqual({
      type: 'standard__objectPage',
      attributes: { objectApiName: 'Volunteer_Hours__c', actionName: 'list' },
      state: { filterName: 'All_Volunteer_Hours' }
    });
    expect(valueFor({ value: 2000, capped: true }, 'en-US')).toBe('2,000+');
    expect(valueFor({ value: 104.37, currencyCode: 'USD' }, 'en-US')).toBe('$104.37');
    expect(badgeStatusFor({ value: 3 })).toBeUndefined();
  });
});
