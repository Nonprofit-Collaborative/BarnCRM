import { createElement } from 'lwc';
import SettingsSearch from 'c/settingsSearch';
import search from '@salesforce/apex/SettingsController.search';

jest.mock('@salesforce/apex/SettingsController.search', () => ({ default: jest.fn() }), {
  virtual: true
});

const HITS = [
  { key: 'Formal_Greeting_Pattern__c', label: 'Formal greeting pattern', section: 'Households' },
  { key: 'Informal_Greeting_Pattern__c', label: 'Informal greeting', section: 'Households' }
];

function build() {
  const element = createElement('c-settings-search', { is: SettingsSearch });
  document.body.appendChild(element);
  return element;
}

async function settle() {
  await Promise.resolve();
  await Promise.resolve();
}

describe('c-settings-search', () => {
  beforeEach(() => {
    jest.useFakeTimers();
    search.mockResolvedValue(HITS);
  });

  afterEach(() => {
    jest.useRealTimers();
    jest.clearAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('waits for Maria to stop typing before searching', async () => {
    const element = build();
    const input = element.shadowRoot.querySelector('lightning-input');

    input.value = 'greeting';
    input.dispatchEvent(new CustomEvent('change'));
    expect(search).not.toHaveBeenCalled();

    jest.runAllTimers();
    await settle();

    expect(search).toHaveBeenCalledTimes(1);
    expect(search).toHaveBeenCalledWith({ term: 'greeting' });
    expect(element.shadowRoot.querySelectorAll('li')).toHaveLength(2);
  });

  it('tells the console which section to open', async () => {
    const element = build();
    const handler = jest.fn();
    element.addEventListener('settingselect', handler);

    const input = element.shadowRoot.querySelector('lightning-input');
    input.value = 'greeting';
    input.dispatchEvent(new CustomEvent('change'));
    jest.runAllTimers();
    await settle();

    element.shadowRoot.querySelector('button').click();

    expect(handler).toHaveBeenCalled();
    expect(handler.mock.calls[0][0].detail.section).toBe('Households');
  });

  it('says so plainly when nothing matches', async () => {
    search.mockResolvedValue([]);
    const element = build();

    const input = element.shadowRoot.querySelector('lightning-input');
    input.value = 'zzz';
    input.dispatchEvent(new CustomEvent('change'));
    jest.runAllTimers();
    await settle();

    expect(element.shadowRoot.querySelector('p[role="status"]')).not.toBeNull();
  });

  it('shows an error, not "no results", when the search fails (UI-16)', async () => {
    search.mockRejectedValue(new Error('down'));
    const element = build();

    const input = element.shadowRoot.querySelector('lightning-input');
    input.value = 'zzz';
    input.dispatchEvent(new CustomEvent('change'));
    jest.runAllTimers();
    await settle();

    expect(element.shadowRoot.querySelector('p[role="alert"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('p[role="status"]')).toBeNull();
  });

  it('ignores a slow answer to an earlier term (UI-16)', async () => {
    let answerSlow;
    search.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          answerSlow = resolve;
        })
    );
    search.mockResolvedValueOnce([HITS[1]]);
    const element = build();
    const input = element.shadowRoot.querySelector('lightning-input');

    input.value = 'gre';
    input.dispatchEvent(new CustomEvent('change'));
    jest.runAllTimers();
    await settle();
    input.value = 'greeting';
    input.dispatchEvent(new CustomEvent('change'));
    jest.runAllTimers();
    await settle();
    answerSlow(HITS);
    await settle();

    const rows = element.shadowRoot.querySelectorAll('li');
    expect(rows).toHaveLength(1);
    expect(rows[0].textContent).toContain('Informal greeting');
  });

  it('does not bring results back after the box was cleared (UI-16)', async () => {
    let answerSlow;
    search.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          answerSlow = resolve;
        })
    );
    const element = build();
    const input = element.shadowRoot.querySelector('lightning-input');

    input.value = 'greeting';
    input.dispatchEvent(new CustomEvent('change'));
    jest.runAllTimers();
    await settle();
    input.value = '';
    input.dispatchEvent(new CustomEvent('change'));
    jest.runAllTimers();
    await settle();
    answerSlow(HITS);
    await settle();

    expect(element.shadowRoot.querySelectorAll('li')).toHaveLength(0);
  });

  it('does not search for an empty box', async () => {
    const element = build();

    const input = element.shadowRoot.querySelector('lightning-input');
    input.value = '   ';
    input.dispatchEvent(new CustomEvent('change'));
    jest.runAllTimers();
    await settle();

    expect(search).not.toHaveBeenCalled();
  });
});
