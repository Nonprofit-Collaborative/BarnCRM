import { createElement } from 'lwc';
import BarnVisualPicker from 'c/barnVisualPicker';
import { expectAccessible } from 'barn/a11y';

describe('c-barn-visual-picker accessibility', () => {
  afterEach(() => document.body.replaceChildren());

  it('passes the accessibility checks', async () => {
    const element = createElement('c-barn-visual-picker', { is: BarnVisualPicker });
    Object.assign(element, {
      label: 'What To Import',
      value: 'people',
      options: [
        {
          value: 'people',
          label: 'People and Organizations',
          description: 'People, households and organizations.',
          iconName: 'standard:household'
        },
        { value: 'gifts', label: 'Gifts', description: 'Gifts.', iconName: 'custom:custom17' }
      ]
    });
    document.body.appendChild(element);
    await Promise.resolve();
    await expectAccessible(element);
  });
});
