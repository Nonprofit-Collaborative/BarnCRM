import { createElement } from 'lwc';
import QuickGiftEntryAction from 'c/quickGiftEntryAction';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';

jest.mock(
  '@salesforce/apex/QuickGiftEntryController.getDefaults',
  () => ({ default: jest.fn(() => Promise.resolve({ giftTypes: [] })) }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/QuickGiftEntryController.getPaymentChoices',
  () => ({ default: jest.fn(() => Promise.resolve({ choices: [] })) }),
  { virtual: true }
);

const CONTACT_ID = '003000000000000AAA';

function build() {
  const element = createElement('c-quick-gift-entry-action', { is: QuickGiftEntryAction });
  element.recordId = CONTACT_ID;
  element.objectApiName = 'Contact';
  document.body.appendChild(element);
  return element;
}

async function settle() {
  await Promise.resolve();
  await Promise.resolve();
}

describe('c-quick-gift-entry-action', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('opens Quick Gift Entry for the record, without its own title', () => {
    const element = build();
    const entry = element.shadowRoot.querySelector('[data-id="entry"]');
    expect(entry.recordId).toBe(CONTACT_ID);
    expect(entry.objectApiName).toBe('Contact');
    expect(entry.inAction).toBe(true);
  });

  it('refreshes the page and closes after Save', async () => {
    const element = build();
    const closed = jest.fn();
    element.addEventListener('lightning__closeactionscreen', closed);
    const entry = element.shadowRoot.querySelector('[data-id="entry"]');

    entry.dispatchEvent(new CustomEvent('giftsaved', { detail: { startAnother: false } }));
    await settle();

    expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([{ recordId: CONTACT_ID }]);
    expect(closed).toHaveBeenCalled();
  });

  it('stays open after Save and New', async () => {
    const element = build();
    const closed = jest.fn();
    element.addEventListener('lightning__closeactionscreen', closed);
    const entry = element.shadowRoot.querySelector('[data-id="entry"]');

    entry.dispatchEvent(new CustomEvent('giftsaved', { detail: { startAnother: true } }));
    await settle();

    expect(closed).not.toHaveBeenCalled();
  });
});
