import { createElement } from 'lwc';
import AccountingExport from 'c/accountingExport';
import getPaymentMethods from '@salesforce/apex/AccountingExportController.getPaymentMethods';
import exportGifts from '@salesforce/apex/AccountingExportController.exportGifts';
import markPosted from '@salesforce/apex/AccountingExportController.markPosted';

jest.mock(
  '@salesforce/apex/AccountingExportController.getPaymentMethods',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/AccountingExportController.exportGifts',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);

jest.mock(
  '@salesforce/apex/AccountingExportController.markPosted',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock('@salesforce/customPermission/Post_Gifts', () => ({ default: true }), {
  virtual: true
});

jest.mock(
  '@salesforce/label/c.Mirror_AccountingExport_Marked',
  () => ({ default: 'Marked {0} gifts posted.' }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Mirror_AccountingExport_Summary',
  () => ({ default: '{0} rows from {1} gifts. Net total {2}.' }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Mirror_AccountingExport_NoGifts',
  () => ({ default: 'No gifts in this range.' }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Mirror_AccountingExport_ErrorDatesRequired',
  () => ({ default: 'Choose a From date and a To date.' }),
  { virtual: true }
);

jest.mock('@salesforce/i18n/locale', () => ({ default: 'en-US' }), { virtual: true });
jest.mock('@salesforce/i18n/currency', () => ({ default: 'USD' }), { virtual: true });

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

function mount() {
  const element = createElement('c-accounting-export', { is: AccountingExport });
  document.body.appendChild(element);
  return element;
}

function change(element, id, detail) {
  element.shadowRoot
    .querySelector(`[data-id="${id}"]`)
    .dispatchEvent(new CustomEvent('change', { detail }));
}

function chooseAugust(element) {
  change(element, 'from', { value: '2026-08-01' });
  change(element, 'to', { value: '2026-08-31' });
}

function click(element) {
  element.shadowRoot.querySelector('[data-id="download"]').click();
}

function text(element, id) {
  const node = element.shadowRoot.querySelector(`[data-id="${id}"]`);
  return node ? node.textContent.trim() : null;
}

describe('c-accounting-export', () => {
  let clicked;

  let blobParts;
  const RealBlob = global.Blob;

  beforeEach(() => {
    jest.useFakeTimers();
    blobParts = [];
    global.Blob = class {
      constructor(parts) {
        blobParts.push(parts);
      }
    };
    clicked = [];
    global.URL.createObjectURL = jest.fn(() => 'blob:export');
    global.URL.revokeObjectURL = jest.fn();
    jest.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(function record() {
      clicked.push({ href: this.href, download: this.download });
    });
  });

  afterEach(() => {
    jest.useRealTimers();
    global.Blob = RealBlob;
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    jest.restoreAllMocks();
  });

  it('offers every payment method after All payment methods', async () => {
    const element = mount();
    getPaymentMethods.emit([
      { label: 'Card', value: 'Card' },
      { label: 'Check', value: 'Check' }
    ]);
    await flush();

    const options = element.shadowRoot.querySelector('[data-id="method"]').options;
    expect(options.map((option) => option.value)).toEqual(['', 'Card', 'Check']);
  });

  it('downloads the file and says what it held', async () => {
    exportGifts.mockResolvedValue({
      csv: 'Date,Gift Number\r\n',
      fileName: 'accounting-export-2026-08-01-to-2026-08-31.csv',
      rowCount: 5,
      giftCount: 4,
      total: 410
    });
    const element = mount();
    chooseAugust(element);
    change(element, 'fund', { recordId: 'a01000000000001AAA' });
    change(element, 'method', { value: 'Check' });
    await flush();

    click(element);
    await flush();

    expect(exportGifts).toHaveBeenCalledWith({
      fromDate: '2026-08-01',
      toDate: '2026-08-31',
      fundId: 'a01000000000001AAA',
      paymentMethod: 'Check',
      onlyUnposted: false
    });
    expect(clicked).toEqual([
      { href: 'blob:export', download: 'accounting-export-2026-08-01-to-2026-08-31.csv' }
    ]);
    expect(blobParts).toEqual([['\uFEFF', 'Date,Gift Number\r\n']]);
    expect(global.URL.revokeObjectURL).not.toHaveBeenCalled();
    jest.runAllTimers();
    expect(global.URL.revokeObjectURL).toHaveBeenCalledWith('blob:export');
    expect(text(element, 'message')).toBe('5 rows from 4 gifts. Net total $410.00.');
  });

  it('sends empty choices as null and saves nothing for an empty range', async () => {
    exportGifts.mockResolvedValue({ csv: null, rowCount: 0, giftCount: 0, total: 0 });
    const element = mount();
    chooseAugust(element);
    await flush();

    click(element);
    await flush();

    expect(exportGifts).toHaveBeenCalledWith({
      fromDate: '2026-08-01',
      toDate: '2026-08-31',
      fundId: null,
      paymentMethod: null,
      onlyUnposted: false
    });
    expect(clicked).toEqual([]);
    expect(text(element, 'message')).toBe('No gifts in this range.');
  });

  it('asks for both dates before calling the server', async () => {
    const element = mount();
    change(element, 'from', { value: '2026-08-01' });
    await flush();

    click(element);
    await flush();

    expect(exportGifts).not.toHaveBeenCalled();
    expect(text(element, 'error')).toBe('Choose a From date and a To date.');
  });

  it("shows the server's refusal in its own words", async () => {
    exportGifts.mockRejectedValue({ body: { message: 'The To date is before the From date.' } });
    const element = mount();
    chooseAugust(element);
    await flush();

    click(element);
    await flush();

    expect(clicked).toEqual([]);
    expect(text(element, 'error')).toBe('The To date is before the From date.');
  });

  describe('marking the file posted', () => {
    const AUGUST = {
      csv: 'Date,Gift Number\r\n',
      fileName: 'accounting-export-2026-08-01-to-2026-08-31.csv',
      rowCount: 5,
      giftCount: 4,
      total: 410,
      digest: 'abc123'
    };

    async function downloadAugust(element) {
      exportGifts.mockResolvedValue(AUGUST);
      chooseAugust(element);
      await flush();
      click(element);
      await flush();
    }

    it('offers nothing before a download', async () => {
      const element = mount();
      chooseAugust(element);
      await flush();
      expect(element.shadowRoot.querySelector('[data-id="mark-posted"]')).toBeNull();
    });

    it('marks the downloaded gifts, sending the digest of the file', async () => {
      markPosted.mockResolvedValue(4);
      const element = mount();
      await downloadAugust(element);

      element.shadowRoot.querySelector('[data-id="mark-posted"]').click();
      await flush();

      expect(markPosted).toHaveBeenCalledWith({
        fromDate: '2026-08-01',
        toDate: '2026-08-31',
        fundId: null,
        paymentMethod: null,
        onlyUnposted: false,
        digest: 'abc123'
      });
      expect(text(element, 'message')).toBe('Marked 4 gifts posted.');
      expect(element.shadowRoot.querySelector('[data-id="mark-posted"]')).toBeNull();
    });

    it('forgets the download when a choice changes', async () => {
      const element = mount();
      await downloadAugust(element);
      expect(element.shadowRoot.querySelector('[data-id="mark-posted"]')).not.toBeNull();

      change(element, 'only-unposted', { checked: true });
      await flush();

      expect(element.shadowRoot.querySelector('[data-id="mark-posted"]')).toBeNull();
    });

    it('asks for all funds instead of marking a one-fund file', async () => {
      exportGifts.mockResolvedValue(AUGUST);
      const element = mount();
      chooseAugust(element);
      change(element, 'fund', { recordId: 'a01000000000001AAA' });
      await flush();
      click(element);
      await flush();

      expect(element.shadowRoot.querySelector('[data-id="mark-posted"]')).toBeNull();
      expect(element.shadowRoot.querySelector('[data-id="needs-all-funds"]')).not.toBeNull();
    });

    it('sends Only gifts not yet posted with the download', async () => {
      exportGifts.mockResolvedValue(AUGUST);
      const element = mount();
      chooseAugust(element);
      change(element, 'only-unposted', { checked: true });
      await flush();
      click(element);
      await flush();

      expect(exportGifts).toHaveBeenCalledWith(expect.objectContaining({ onlyUnposted: true }));
    });

    it("shows the server's refusal when the gifts changed", async () => {
      markPosted.mockRejectedValue({
        body: { message: 'Gifts in this range changed since you downloaded the file.' }
      });
      const element = mount();
      await downloadAugust(element);

      element.shadowRoot.querySelector('[data-id="mark-posted"]').click();
      await flush();

      expect(text(element, 'error')).toBe(
        'Gifts in this range changed since you downloaded the file.'
      );
      expect(element.shadowRoot.querySelector('[data-id="mark-posted"]')).not.toBeNull();
    });
  });
});
