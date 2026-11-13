import { findA11yProblems } from 'barn/a11y';

function add(parent, tag, props = {}, attributes = {}) {
  const element = document.createElement(tag);
  Object.assign(element, props);
  Object.entries(attributes).forEach(([name, value]) => element.setAttribute(name, value));
  parent.appendChild(element);
  return element;
}

describe('barn/a11y findA11yProblems', () => {
  afterEach(() => document.body.replaceChildren());

  it('finds nothing wrong with named controls', () => {
    const root = add(document.body, 'div');
    add(root, 'lightning-input', { label: 'Email' });
    add(root, 'lightning-button-icon', { alternativeText: 'Delete' });
    add(root, 'lightning-button', { label: 'Save' });
    add(root, 'lightning-button-menu', { alternativeText: 'More' });
    add(root, 'img', {}, { alt: '' });
    add(root, 'button', { textContent: 'Close' });
    add(root, 'a', {}, { href: '#', 'aria-label': 'Open' });
    add(root, 'span', {}, { tabindex: '0' });
    expect(findA11yProblems(root)).toEqual([]);
  });

  it('names each control a screen reader cannot read, and a positive tabindex', () => {
    const root = add(document.body, 'div');
    add(root, 'lightning-combobox', {}, { 'data-id': 'stage' });
    add(root, 'lightning-button-icon');
    add(root, 'lightning-button');
    add(root, 'lightning-button-menu');
    add(root, 'img');
    add(root, 'button');
    add(root, 'a', {}, { href: '#' });
    add(root, 'div', {}, { tabindex: '2' });
    const problems = findA11yProblems(root);
    expect(problems).toHaveLength(8);
    expect(problems[0]).toContain('lightning-combobox[stage] has no label');
    expect(problems[7]).toContain('tabindex 2');
  });
});
