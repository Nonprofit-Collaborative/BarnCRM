import { createElement } from 'lwc';
import GrantAnswerLibrary from 'c/grantAnswerLibrary';
import getLibrary from '@salesforce/apex/GrantAnswerController.getLibrary';
import markUsed from '@salesforce/apex/GrantAnswerController.markUsed';

jest.mock('@salesforce/apex/GrantAnswerController.getLibrary', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/GrantAnswerController.markUsed', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Funders_Answers_AllTopics', () => ({ default: 'All topics' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Funders_Answers_Words', () => ({ default: '{0} words' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Funders_Answers_NeverUsed', () => ({ default: 'Never used' }), {
  virtual: true
});

const LONG = `${'word '.repeat(80)}end`;
const LIBRARY = {
  canCreate: true,
  answers: [
    {
      id: 'a1',
      title: 'Mission',
      topics: 'Mission, Organization',
      text: 'We teach reading.',
      lastUsed: null
    },
    { id: 'a2', title: 'Need', topics: 'Need', text: LONG, lastUsed: '2026-01-15' }
  ]
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render(library = LIBRARY) {
  getLibrary.mockResolvedValue(library);
  const element = createElement('c-grant-answer-library', { is: GrantAnswerLibrary });
  document.body.appendChild(element);
  await flush();
  return element;
}

const all = (element, selector) => [...element.shadowRoot.querySelectorAll(selector)];
const one = (element, selector) => element.shadowRoot.querySelector(selector);

describe('c-grant-answer-library', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists the answers with topics, words and last use, and offers every topic', async () => {
    const element = await render();
    expect(all(element, '[data-id="answer"]')).toHaveLength(2);
    expect(one(element, '[data-id="topic"]').options.map((option) => option.label)).toEqual([
      'All topics',
      'Mission',
      'Need',
      'Organization'
    ]);
    const meta = all(element, '[data-id="meta"]').map((node) => node.textContent);
    expect(meta[0]).toContain('3 words');
    expect(meta[0]).toContain('Never used');
    expect(one(element, '[data-id="new"]')).not.toBeNull();
  });

  it('narrows by topic and by search', async () => {
    const element = await render();
    one(element, '[data-id="topic"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Need' } })
    );
    await flush();
    expect(all(element, '[data-id="answer"]')).toHaveLength(1);

    one(element, '[data-id="topic"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: '' } })
    );
    one(element, '[data-id="search"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'nothing like this' } })
    );
    await flush();
    expect(all(element, '[data-id="answer"]')).toHaveLength(0);
    expect(one(element, '[data-id="no-match"]')).not.toBeNull();
  });

  it('shortens a long answer until Show All', async () => {
    const element = await render();
    const texts = () => all(element, '[data-id="text"]').map((node) => node.textContent);
    expect(texts()[1].endsWith('...')).toBe(true);
    const toggle = all(element, 'lightning-button').find((button) => button.variant === 'base');
    toggle.click();
    await flush();
    expect(texts()[1]).toBe(LONG);
  });

  it('copies to the clipboard and shows the stamped date', async () => {
    const writeText = jest.fn().mockResolvedValue();
    Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true });
    markUsed.mockResolvedValue('2026-11-02');
    const element = await render();
    const copy = all(element, 'lightning-button').find(
      (button) => button.dataset.id === 'a1' && button.iconName === 'utility:copy'
    );
    copy.click();
    await flush();
    await flush();
    expect(writeText).toHaveBeenCalledWith('We teach reading.');
    expect(markUsed).toHaveBeenCalledWith({ answerId: 'a1' });
    expect(all(element, '[data-id="meta"]')[0].textContent).not.toContain('Never used');
  });

  it('does not stamp when the browser refuses the clipboard', async () => {
    const writeText = jest.fn().mockRejectedValue(new Error('denied'));
    Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true });
    const element = await render();
    all(element, 'lightning-button')
      .find((button) => button.dataset.id === 'a1' && button.iconName === 'utility:copy')
      .click();
    await flush();
    expect(markUsed).not.toHaveBeenCalled();
  });

  it('says when there are no answers yet, and shows a load error', async () => {
    let element = await render({ canCreate: false, answers: [] });
    expect(one(element, '[data-id="empty"]')).not.toBeNull();
    expect(one(element, '[data-id="new"]')).toBeNull();
    document.body.removeChild(element);

    getLibrary.mockRejectedValue({ body: { message: 'Broken' } });
    element = createElement('c-grant-answer-library', { is: GrantAnswerLibrary });
    document.body.appendChild(element);
    await flush();
    expect(one(element, '[data-id="error-message"]').textContent).toBe('Broken');
  });
});
