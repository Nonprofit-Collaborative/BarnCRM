import { createElement } from 'lwc';
import BarnConfirmModal from 'c/barnConfirmModal';

function render(props) {
  const element = createElement('c-barn-confirm-modal', { is: BarnConfirmModal });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

function flush() {
  return Promise.resolve();
}

describe('c-barn-confirm-modal', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('shows the heading, message, details and the caller button labels', async () => {
    const element = render({
      label: 'Merge these households?',
      message: 'Garcia Household will be merged into The Garcia Family.',
      details: ['First line', '', 'Second line'],
      confirmLabel: 'Merge households',
      cancelLabel: 'Cancel',
      confirmVariant: 'destructive'
    });
    await flush();

    const root = element.shadowRoot;
    expect(root.querySelector('lightning-modal-header').label).toBe('Merge these households?');
    expect(root.querySelector('[data-id="message"]').textContent).toBe(
      'Garcia Household will be merged into The Garcia Family.'
    );
    const details = Array.from(root.querySelectorAll('[data-id="detail"]')).map(
      (node) => node.textContent
    );
    expect(details).toEqual(['First line', 'Second line']);
    const confirm = root.querySelector('[data-id="confirm"]');
    expect(confirm.label).toBe('Merge households');
    expect(confirm.variant).toBe('destructive');
    expect(root.querySelector('[data-id="cancel"]').label).toBe('Cancel');
  });

  it('uses the brand button when no variant is given', async () => {
    const element = render({
      label: 'Sure?',
      message: 'Go',
      confirmLabel: 'Go',
      cancelLabel: 'No'
    });
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="confirm"]').variant).toBe('brand');
    expect(element.shadowRoot.querySelectorAll('[data-id="detail"]')).toHaveLength(0);
  });

  it('closes with true on confirm and false on cancel', async () => {
    const element = render({
      label: 'Sure?',
      message: 'Go',
      confirmLabel: 'Go',
      cancelLabel: 'No'
    });
    await flush();
    const closed = jest.fn();
    element.addEventListener('close', closed);

    element.shadowRoot.querySelector('[data-id="confirm"]').click();
    element.shadowRoot.querySelector('[data-id="cancel"]').click();

    expect(closed.mock.calls.map((call) => call[0].detail)).toEqual([true, false]);
  });
});
