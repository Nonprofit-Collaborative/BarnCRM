import { createElement } from 'lwc';
import WhatsNew from 'c/whatsNew';
import getWhatsNew from '@salesforce/apex/WhatsNewController.getWhatsNew';
import dismiss from '@salesforce/apex/WhatsNewController.dismiss';

jest.mock('@salesforce/apex/WhatsNewController.getWhatsNew', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/WhatsNewController.dismiss', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_WhatsNew_Version', () => ({ default: 'Version {0}' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_WhatsNew_Failed', () => ({ default: 'Could not update.' }), {
  virtual: true
});

const RELEASES = [
  {
    version: '0.12',
    notes: [
      { key: 'A', headline: 'Newest change', details: ['One', 'Two'], module: 'Core' },
      { key: 'B', headline: 'Another change', details: [], module: null }
    ]
  },
  { version: '0.9', notes: [{ key: 'C', headline: 'Older change', details: [], module: 'Giving' }] }
];

function flush() {
  return Promise.resolve().then(() => Promise.resolve());
}

async function createComponent() {
  const element = createElement('c-whats-new', { is: WhatsNew });
  document.body.appendChild(element);
  await flush();
  return element;
}

describe('c-whats-new', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists each release newest first with its notes', async () => {
    getWhatsNew.mockResolvedValue(RELEASES);
    const element = await createComponent();

    const releases = element.shadowRoot.querySelectorAll('[data-id="release"]');
    expect(releases.length).toBe(2);
    expect(releases[0].querySelector('h2').textContent).toBe('Version 0.12');
    expect(releases[1].querySelector('h2').textContent).toBe('Version 0.9');
    const notes = releases[0].querySelectorAll('[data-id="note"]');
    expect(notes.length).toBe(2);
    expect(notes[0].textContent).toContain('Newest change');
    expect(notes[0].querySelectorAll('li').length).toBe(2);
    expect(notes[0].querySelector('lightning-badge').label).toBe('Core');
    expect(notes[1].querySelector('lightning-badge')).toBeNull();
  });

  it('renders nothing when nothing is new', async () => {
    getWhatsNew.mockResolvedValue([]);
    const element = await createComponent();

    expect(element.shadowRoot.querySelector('lightning-card')).toBeNull();
  });

  it('renders nothing when the notes cannot be loaded', async () => {
    getWhatsNew.mockRejectedValue({ body: { message: 'Could not update.' } });
    const element = await createComponent();

    expect(element.shadowRoot.querySelector('lightning-card')).toBeNull();
  });

  it('dismisses and hides the card', async () => {
    getWhatsNew.mockResolvedValue(RELEASES);
    dismiss.mockResolvedValue();
    const element = await createComponent();

    element.shadowRoot.querySelector('[data-id="dismiss"]').click();
    await flush();

    expect(dismiss).toHaveBeenCalledTimes(1);
    expect(element.shadowRoot.querySelector('lightning-card')).toBeNull();
  });

  it('keeps the card and says so when dismissing fails', async () => {
    getWhatsNew.mockResolvedValue(RELEASES);
    dismiss.mockRejectedValue({ body: { message: 'Could not update.' } });
    const element = await createComponent();

    element.shadowRoot.querySelector('[data-id="dismiss"]').click();
    await flush();
    await flush();

    expect(element.shadowRoot.querySelector('lightning-card')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[role="alert"]').textContent).toContain(
      'Could not update.'
    );
    expect(element.shadowRoot.querySelector('[data-id="dismiss"]').disabled).toBe(false);
  });
});
