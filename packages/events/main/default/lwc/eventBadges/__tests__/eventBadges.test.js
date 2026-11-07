import { createElement } from 'lwc';
import EventBadges from 'c/eventBadges';
import getBadges from '@salesforce/apex/EventBadgesController.getBadges';

jest.mock('@salesforce/apex/EventBadgesController.getBadges', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/resourceUrl/BarnQrCode', () => ({ default: 'qr.js' }), {
  virtual: true
});
jest.mock(
  'lightning/platformResourceLoader',
  () => ({ loadScript: jest.fn(() => Promise.resolve()) }),
  {
    virtual: true
  }
);

const EVENT_ID = 'a01000000000001AAA';
const DATA = {
  eventName: 'Spring Gala',
  eventStart: '2026-12-01T18:00:00.000Z',
  venue: 'Grand Hall',
  truncated: false,
  attendees: [
    { id: 'a1', name: 'Ann Lee', organization: 'Acme', ticketName: 'VIP' },
    { id: 'a2', name: 'Bo Kim', ticketName: 'General' }
  ],
  sessions: [{ id: 's1', name: 'Keynote', startsAt: '2026-12-01T19:00:00.000Z', room: 'Main' }]
};

function textOf(blob) {
  return new Promise((resolve) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.readAsText(blob);
  });
}

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render(data = DATA) {
  getBadges.mockResolvedValue(data);
  const element = createElement('c-event-badges', { is: EventBadges });
  element.recordId = EVENT_ID;
  document.body.appendChild(element);
  await flush();
  return element;
}

const one = (element, selector) => element.shadowRoot.querySelector(selector);
const change = (node, detail) => node.dispatchEvent(new CustomEvent('change', { detail }));

describe('c-event-badges', () => {
  let printWindow;
  beforeEach(() => {
    printWindow = {
      addEventListener: jest.fn((name, fn) => fn()),
      focus: jest.fn(),
      print: jest.fn()
    };
    window.open = jest.fn(() => printWindow);
    URL.createObjectURL = jest.fn(() => 'blob:x');
    URL.revokeObjectURL = jest.fn();
    window.qrcode = jest.fn(() => ({
      addData: jest.fn(),
      make: jest.fn(),
      createDataURL: jest.fn(() => 'data:image/gif;base64,QQ==')
    }));
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    delete window.qrcode;
  });

  it('shows the empty state when nobody holds a seat', async () => {
    const element = await render({ ...DATA, attendees: [] });
    expect(one(element, '[data-id="empty-state"]')).not.toBeNull();
    expect(one(element, '[data-id="print-badges"]')).toBeNull();
  });

  it('prints badges for the people chosen, with QR codes when switched on', async () => {
    const element = await render();
    change(one(element, '[data-id="search"]'), { value: 'ann' });
    change(one(element, '[data-id="show-qr"]'), { checked: true });
    await flush();
    one(element, '[data-id="print-badges"]').click();
    await flush();
    expect(window.open).toHaveBeenCalledTimes(1);
    expect(printWindow.print).toHaveBeenCalled();
    const html = await textOf(URL.createObjectURL.mock.calls[0][0]);
    expect(html).toContain('Ann Lee');
    expect(html).not.toContain('Bo Kim');
    expect(html).toContain('data:image/gif;base64,QQ==');
  });

  it('prints a sign-in sheet for a session', async () => {
    const element = await render();
    change(one(element, '[data-id="scope"]'), { value: 's1' });
    await flush();
    one(element, '[data-id="print-sheet"]').click();
    await flush();
    const html = await textOf(URL.createObjectURL.mock.calls[0][0]);
    expect(html).toContain('Ann Lee');
    expect(html).toContain('Bo Kim');
    expect(html).toContain('class="blank"');
  });

  it('warns when the browser blocks the window', async () => {
    window.open = jest.fn(() => null);
    const element = await render();
    one(element, '[data-id="print-sheet"]').click();
    await flush();
    expect(URL.revokeObjectURL).toHaveBeenCalled();
  });

  it('shows a load failure', async () => {
    getBadges.mockRejectedValue({ body: { message: 'No' } });
    const element = createElement('c-event-badges', { is: EventBadges });
    element.recordId = EVENT_ID;
    document.body.appendChild(element);
    await flush();
    expect(one(element, '[data-id="error-message"]')).not.toBeNull();
  });
});
