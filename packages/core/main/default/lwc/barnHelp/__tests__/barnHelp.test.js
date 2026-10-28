import { createElement } from 'lwc';
import BarnHelp from 'c/barnHelp';

// Storybook-style: each case renders one variant a screen uses and checks what it shows.
function render(props) {
  const element = createElement('c-barn-help', { is: BarnHelp });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

const one = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-barn-help', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('story: popover and Learn More link', () => {
    const element = render({
      content: 'Counted with your own access.',
      alternativeText: 'Help for Data Quality',
      learnMoreUrl: 'https://example.org/guide/data-quality'
    });

    const helptext = one(element, 'helptext');
    expect(helptext.content).toBe('Counted with your own access.');
    expect(helptext.alternativeText).toBe('Help for Data Quality');

    const link = one(element, 'learn-more');
    expect(link.getAttribute('href')).toBe('https://example.org/guide/data-quality');
    expect(link.getAttribute('target')).toBe('_blank');
    expect(link.getAttribute('rel')).toBe('noopener noreferrer');
    expect(link.textContent).toContain('c.Core_Kit_LearnMore');
    expect(one(element, 'new-tab').textContent).toBe('c.Core_Kit_NewTab');
    expect(link.querySelector('lightning-icon').iconName).toBe('utility:new_window');
  });

  it('story: popover only', () => {
    const element = render({ content: 'Short help.' });
    expect(one(element, 'helptext')).not.toBeNull();
    expect(one(element, 'learn-more')).toBeNull();
  });

  it('story: link only, with the caller link text', () => {
    const element = render({
      learnMoreUrl: 'https://example.org/guide/import',
      learnMoreLabel: 'Read the Import Guide'
    });
    expect(one(element, 'helptext')).toBeNull();
    expect(one(element, 'learn-more').textContent).toContain('Read the Import Guide');
  });

  it('renders nothing visible when given nothing', () => {
    const element = render({});
    expect(one(element, 'helptext')).toBeNull();
    expect(one(element, 'learn-more')).toBeNull();
  });
});
