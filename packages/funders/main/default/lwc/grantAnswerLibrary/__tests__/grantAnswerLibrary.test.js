/* eslint-disable @lwc/lwc/no-unexpected-wire-adapter-usages */
import { createElement } from 'lwc';
import GrantAnswerLibrary from 'c/grantAnswerLibrary';
import { graphql } from 'lightning/graphql';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { updateRecord } from 'lightning/uiRecordApi';

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

const node = (id, name, topics, text, lastUsed) => ({
  Id: id,
  Name: { value: name },
  Topics__c: { value: topics },
  Answer__c: { value: text },
  Last_Used_Date__c: { value: lastUsed }
});

const ANSWERS = [
  node('a1', 'Mission', 'Mission, Organization', 'We teach reading.', null),
  node('a2', 'Need', 'Need', LONG, '2026-01-15'),
  node('a3', 'Blank draft', 'Budget', null, null)
];

const payload = (nodes) => ({
  uiapi: { query: { Grant_Answer__c: { edges: nodes.map((each) => ({ node: each })) } } }
});

const INFO = { createable: true, fields: { Last_Used_Date__c: { updateable: true } } };

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render(nodes = ANSWERS, info = INFO) {
  const element = createElement('c-grant-answer-library', { is: GrantAnswerLibrary });
  document.body.appendChild(element);
  graphql.emit(payload(nodes));
  getObjectInfo.emit(info);
  await flush();
  return element;
}

const all = (element, selector) => [...element.shadowRoot.querySelectorAll(selector)];
const one = (element, selector) => element.shadowRoot.querySelector(selector);
const copyButton = (element, id) =>
  all(element, 'lightning-button').find(
    (button) => button.dataset.id === id && button.iconName === 'utility:copy'
  );

describe('c-grant-answer-library', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists the answers with text, with topics, words and last use, and offers every topic', async () => {
    const element = await render();
    expect(all(element, '[data-id="answer"]')).toHaveLength(2);
    expect(one(element, '[data-id="topic"]').options.map((option) => option.label)).toEqual([
      'All topics',
      'Mission',
      'Need',
      'Organization'
    ]);
    const meta = all(element, '[data-id="meta"]').map((each) => each.textContent);
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
    const texts = () => all(element, '[data-id="text"]').map((each) => each.textContent);
    expect(texts()[1].endsWith('...')).toBe(true);
    const toggle = all(element, 'lightning-button').find((button) => button.variant === 'base');
    toggle.click();
    await flush();
    expect(texts()[1]).toBe(LONG);
  });

  it('copies to the clipboard and stamps today through Lightning Data Service', async () => {
    const writeText = jest.fn().mockResolvedValue();
    Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true });
    const element = await render();
    copyButton(element, 'a1').click();
    await flush();
    await flush();
    expect(writeText).toHaveBeenCalledWith('We teach reading.');
    expect(updateRecord).toHaveBeenCalledTimes(1);
    const { fields } = updateRecord.mock.calls[0][0];
    expect(fields.Id).toBe('a1');
    expect(fields.Last_Used_Date__c).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(all(element, '[data-id="meta"]')[0].textContent).not.toContain('Never used');
  });

  it('copies without stamping for a person who cannot edit the date', async () => {
    const writeText = jest.fn().mockResolvedValue();
    Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true });
    const element = await render(ANSWERS, {
      createable: false,
      fields: { Last_Used_Date__c: { updateable: false } }
    });
    copyButton(element, 'a1').click();
    await flush();
    expect(writeText).toHaveBeenCalled();
    expect(updateRecord).not.toHaveBeenCalled();
  });

  it('says why when the stamp is refused', async () => {
    const writeText = jest.fn().mockResolvedValue();
    Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true });
    updateRecord.mockRejectedValueOnce({
      body: { message: 'An error occurred.', output: { errors: [{ message: 'Locked' }] } }
    });
    const element = await render();
    const toasts = [];
    element.addEventListener('lightning__showtoast', (event) => toasts.push(event.detail));
    copyButton(element, 'a1').click();
    await flush();
    await flush();
    expect(toasts.map((toast) => toast.message)).toContain('Locked');
    expect(all(element, '[data-id="meta"]')[0].textContent).toContain('Never used');
  });

  it('does not stamp when the browser refuses the clipboard', async () => {
    const writeText = jest.fn().mockRejectedValue(new Error('denied'));
    Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true });
    const element = await render();
    copyButton(element, 'a1').click();
    await flush();
    expect(updateRecord).not.toHaveBeenCalled();
  });

  it('reads the answers again when the card is opened again', async () => {
    const refresh = jest.fn();
    const element = createElement('c-grant-answer-library', { is: GrantAnswerLibrary });
    document.body.appendChild(element);
    graphql.emit(payload(ANSWERS), undefined, refresh);
    await flush();
    expect(refresh).not.toHaveBeenCalled();
    document.body.removeChild(element);
    document.body.appendChild(element);
    expect(refresh).toHaveBeenCalledTimes(1);
  });

  it('says when there are no answers yet, and shows a load error', async () => {
    let element = await render([], { createable: false, fields: {} });
    expect(one(element, '[data-id="empty"]')).not.toBeNull();
    expect(one(element, '[data-id="new"]')).toBeNull();
    document.body.removeChild(element);

    element = createElement('c-grant-answer-library', { is: GrantAnswerLibrary });
    document.body.appendChild(element);
    graphql.emitErrors([{ message: 'Broken' }]);
    await flush();
    expect(one(element, '[data-id="error-message"]').textContent).toBe(
      'c.Funders_Answers_ErrorLoad'
    );
    expect(one(element, '[data-id="empty"]')).toBeNull();
  });
});
