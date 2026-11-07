import { createElement } from 'lwc';
import EventRecordModal from 'c/eventRecordModal';

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

function render(props) {
  const element = createElement('c-event-record-modal', { is: EventRecordModal });
  Object.assign(element, { objectApiName: 'Ticket_Type__c', ...props });
  document.body.appendChild(element);
  return element;
}

const all = (element, selector) => [...element.shadowRoot.querySelectorAll(selector)];
const one = (element, selector) => element.shadowRoot.querySelector(selector);

describe('c-event-record-modal', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('shows the fields asked for and keeps the event out of sight on a new record', async () => {
    const element = render({
      fields: ['Name', 'Price__c'],
      defaults: { Event__c: 'a01000000000001AAA' }
    });
    await flush();
    expect(all(element, '[data-id="field"]').map((field) => field.fieldName)).toEqual([
      'Name',
      'Price__c'
    ]);
    const hidden = all(element, '[data-id="hidden-field"]');
    expect(hidden).toHaveLength(1);
    expect(hidden[0].value).toBe('a01000000000001AAA');
  });

  it('sets no defaults when editing', async () => {
    const element = render({
      recordId: 'a02000000000001AAA',
      fields: ['Name'],
      defaults: { Event__c: 'a01000000000001AAA' }
    });
    await flush();
    expect(all(element, '[data-id="hidden-field"]')).toHaveLength(0);
  });

  it('closes with the saved record and closes empty on cancel', async () => {
    const element = render({ fields: ['Name'] });
    const closed = jest.fn();
    element.addEventListener('close', closed);
    await flush();
    one(element, 'lightning-record-edit-form').dispatchEvent(
      new CustomEvent('success', { detail: { id: 'a02000000000001AAA' } })
    );
    one(element, '[data-id="record-cancel"]').click();
    expect(closed.mock.calls[0][0].detail).toEqual({ id: 'a02000000000001AAA' });
    expect(closed.mock.calls[1][0].detail).toBeFalsy();
  });
});
