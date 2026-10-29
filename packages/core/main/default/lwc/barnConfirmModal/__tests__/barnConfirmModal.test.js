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

  it('story: no type-to-confirm field unless asked for', async () => {
    const element = render({
      label: 'Sure?',
      message: 'Go',
      confirmLabel: 'Go',
      cancelLabel: 'No'
    });
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="type-to-confirm"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="confirm"]').disabled).toBe(false);
  });

  it('story: type the count before a destructive confirm works', async () => {
    const element = render({
      label: 'Delete 1250 records?',
      message: 'They go to the Recycle Bin.',
      confirmLabel: 'Delete 1250 Records',
      cancelLabel: 'Cancel',
      confirmVariant: 'destructive',
      typeToConfirm: '1250',
      typeToConfirmLabel: 'Type 1250 to delete these records'
    });
    await flush();
    const closed = jest.fn();
    element.addEventListener('close', closed);
    const root = element.shadowRoot;
    const field = root.querySelector('[data-id="type-to-confirm"]');
    const confirm = root.querySelector('[data-id="confirm"]');
    expect(field.label).toBe('Type 1250 to delete these records');
    expect(confirm.disabled).toBe(true);

    confirm.click();
    expect(closed).not.toHaveBeenCalled();

    field.value = '125';
    field.dispatchEvent(new CustomEvent('change'));
    await flush();
    expect(confirm.disabled).toBe(true);

    field.value = ' 1250 ';
    field.dispatchEvent(new CustomEvent('change'));
    await flush();
    expect(confirm.disabled).toBe(false);
    confirm.click();
    expect(closed.mock.calls[0][0].detail).toBe(true);
  });

  it('story: a list of names, one choice and tick boxes resolve what was picked', async () => {
    const element = render({
      label: 'Move?',
      message: 'These people move:',
      items: ['Luis Garcia', 'Luis Garcia'],
      choices: [
        { label: 'The Nowak Family', value: 'n' },
        { label: 'The Garcia Family', value: 'g' }
      ],
      choicesLabel: 'Which household?',
      choice: 'n',
      checks: [{ label: 'Ana Garcia', value: 'a' }],
      checksLabel: 'Also move',
      confirmLabel: 'Move',
      cancelLabel: 'Cancel'
    });
    await flush();
    const closed = jest.fn();
    element.addEventListener('close', closed);
    const root = element.shadowRoot;
    expect(root.querySelectorAll('[data-id="items"] li')).toHaveLength(2);
    const choices = root.querySelector('[data-id="choices"]');
    expect(choices.label).toBe('Which household?');
    expect(choices.value).toBe('n');
    expect(root.querySelector('[data-id="checks"]').value).toEqual([]);

    choices.dispatchEvent(new CustomEvent('change', { detail: { value: 'g' } }));
    root
      .querySelector('[data-id="checks"]')
      .dispatchEvent(new CustomEvent('change', { detail: { value: ['a'] } }));
    root.querySelector('[data-id="confirm"]').click();
    root.querySelector('[data-id="cancel"]').click();

    expect(closed.mock.calls.map((call) => call[0].detail)).toEqual([
      { choice: 'g', checked: ['a'] },
      false
    ]);
  });
});
