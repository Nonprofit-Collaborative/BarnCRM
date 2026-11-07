import { createElement } from 'lwc';
import EventRepeatModal from 'c/eventRepeatModal';

jest.mock('@salesforce/i18n/locale', () => ({ default: 'en-US' }), { virtual: true });
jest.mock('@salesforce/i18n/timeZone', () => ({ default: 'UTC' }), { virtual: true });

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

function render() {
  const element = createElement('c-event-repeat-modal', { is: EventRepeatModal });
  element.eventName = 'Monthly Class';
  element.startsAt = new Date(2026, 0, 31, 9, 0).toISOString();
  document.body.appendChild(element);
  return element;
}

const one = (element, selector) => element.shadowRoot.querySelector(selector);

describe('c-event-repeat-modal', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('previews four weekly dates by default and returns them when confirmed', async () => {
    const element = render();
    await flush();
    expect(one(element, '[data-id="repeat-preview"]').querySelectorAll('li')).toHaveLength(4);
    const closed = jest.fn();
    element.addEventListener('close', closed);
    one(element, '[data-id="repeat-confirm"]').click();
    const { starts } = closed.mock.calls[0][0].detail;
    expect(starts).toHaveLength(4);
    expect(starts[0]).toBe(new Date(2026, 1, 7, 9, 0).toISOString());
  });

  it('follows the chosen pattern and count', async () => {
    const element = render();
    one(element, '[data-id="repeat-frequency"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'monthly' } })
    );
    one(element, '[data-id="repeat-count"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: '2' } })
    );
    await flush();
    const closed = jest.fn();
    element.addEventListener('close', closed);
    one(element, '[data-id="repeat-confirm"]').click();
    expect(closed.mock.calls[0][0].detail.starts).toEqual([
      new Date(2026, 1, 28, 9, 0).toISOString(),
      new Date(2026, 2, 31, 9, 0).toISOString()
    ]);
  });

  it('cannot be confirmed with a count out of range, and Cancel saves nothing', async () => {
    const element = render();
    one(element, '[data-id="repeat-count"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: '99' } })
    );
    await flush();
    expect(one(element, '[data-id="repeat-confirm"]').disabled).toBe(true);
    const closed = jest.fn();
    element.addEventListener('close', closed);
    one(element, '[data-id="repeat-cancel"]').click();
    expect(closed.mock.calls[0][0].detail).toBeFalsy();
  });
});
