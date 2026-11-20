import { createElement } from 'lwc';
import ConnectorAppPollSetup from 'c/connectorAppPollSetup';
import { expectAccessible } from 'barn/a11y';

const TRIGGER = {
  kind: 'appPoll',
  connection: 'BarnConn_rest_abc123',
  path: '/lists/{listId}/members',
  pathValues: [{ name: 'listId', value: 'a1b2' }],
  query: [{ name: 'since_last_changed', path: 'trigger.watermark' }],
  items: 'members',
  id: 'id',
  stamp: 'last_changed',
  mode: 'each'
};
const CONNECTIONS = [{ label: 'Mailchimp', value: 'BarnConn_rest_abc123' }];

const flush = () => Promise.resolve().then(() => Promise.resolve());
const find = (element, selector) => element.shadowRoot.querySelector(selector);

function render(readOnly = false, trigger = TRIGGER) {
  const element = createElement('c-connector-app-poll-setup', { is: ConnectorAppPollSetup });
  element.trigger = trigger;
  element.connections = CONNECTIONS;
  element.readOnly = readOnly;
  const changes = [];
  element.addEventListener('triggerchange', (event) => changes.push(event.detail));
  document.body.appendChild(element);
  return { element, changes };
}

function change(target, value) {
  target.value = value;
  target.dispatchEvent(new CustomEvent('change', { detail: { value } }));
}

describe('c-connector-app-poll-setup (CN-13)', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('shows the trigger with the watermark value as typed', async () => {
    const { element } = render();
    await flush();
    expect(find(element, '[data-id="connection"]').options).toEqual(CONNECTIONS);
    expect(find(element, '[data-id="path"]').value).toBe('/lists/{listId}/members');
    expect(find(element, '[data-list="pathValues"]').value).toBe('a1b2');
    expect(find(element, '[data-list="query"][data-field="shown"]').value).toBe(
      'trigger.watermark'
    );
    expect(find(element, '[data-id="mode"]').options.map((option) => option.value)).toEqual([
      'each',
      'batch'
    ]);
    await expectAccessible(element);
  });

  it('hands each change to the editor: path slots, the watermark as a path, a number limit', async () => {
    const { element, changes } = render();
    await flush();
    change(find(element, '[data-id="path"]'), '/events/{eventId}/attendees');
    expect(changes.pop()).toEqual({
      path: '/events/{eventId}/attendees',
      pathValues: [{ name: 'eventId', path: '' }]
    });

    change(find(element, '[data-list="query"][data-field="shown"]'), 'trigger.watermark');
    expect(changes.pop()).toEqual({
      query: [{ name: 'since_last_changed', path: 'trigger.watermark' }]
    });
    change(find(element, '[data-list="query"][data-field="shown"]'), 'unsubscribed');
    expect(changes.pop()).toEqual({
      query: [{ name: 'since_last_changed', value: 'unsubscribed' }]
    });

    change(find(element, '[data-id="limit"]'), '50');
    expect(changes.pop()).toEqual({ limit: 50 });
    change(find(element, '[data-id="limit"]'), '');
    expect(changes.pop()).toEqual({ limit: undefined });

    change(find(element, '[data-id="stamp"]'), 'changed_at');
    expect(changes.pop()).toEqual({ stamp: 'changed_at' });
  });

  it('adds and removes query parameters', async () => {
    const { element, changes } = render();
    await flush();
    find(element, '[data-id="add-query"]').click();
    expect(changes.pop().query).toHaveLength(2);
    find(element, 'lightning-button-icon').click();
    expect(changes.pop()).toEqual({ query: [] });
  });

  it('is read only for a viewer', async () => {
    const { element } = render(true);
    await flush();
    expect(find(element, '[data-id="add-query"]')).toBeNull();
    expect(find(element, 'lightning-button-icon')).toBeNull();
    expect(find(element, '[data-id="path"]').readOnly).toBe(true);
    expect(find(element, '[data-id="mode"]').disabled).toBe(true);
  });
});
