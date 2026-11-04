import { createElement } from 'lwc';
import BarnStatusBadge from 'c/barnStatusBadge';

// Storybook-style: one story per tone, the recorded words, and the icon options.
function render(props) {
  const element = createElement('c-barn-status-badge', { is: BarnStatusBadge });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

const badge = (element) => element.shadowRoot.querySelector('[data-id="badge"]');

describe('c-barn-status-badge', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it.each([
    ['success', 'slds-theme_success', 'utility:success'],
    ['warning', 'slds-theme_warning', 'utility:warning'],
    ['error', 'slds-theme_error', 'utility:error'],
    ['running', 'slds-theme_warning', 'utility:clock'],
    ['info', '', 'utility:info'],
    ['neutral', '', undefined]
  ])('story: tone %s', (status, themeClass, icon) => {
    const element = render({ status, label: 'Status' });
    expect(badge(element).label).toBe('Status');
    expect(badge(element).className).toBe(themeClass);
    expect(badge(element).iconName).toBe(icon);
  });

  it.each([
    ['Active', 'success'],
    ['due soon', 'warning'],
    ['OVERDUE', 'error'],
    ['in_progress', 'running'],
    ['new', 'info'],
    ['off', 'neutral'],
    ['inverse', 'neutral'],
    ['something else', 'neutral'],
    [undefined, 'neutral']
  ])('story: the word %s draws the %s tone', (status, tone) => {
    const element = render({ status, label: 'Status' });
    expect(badge(element).dataset.tone).toBe(tone);
  });

  it('story: an icon override and a badge with no icon', () => {
    const primary = render({ status: 'success', label: 'Primary', iconName: 'utility:favorite' });
    expect(badge(primary).iconName).toBe('utility:favorite');
    const plain = render({ status: 'error', label: 'Failed', hideIcon: true });
    expect(badge(plain).iconName).toBeUndefined();
    expect(badge(plain).className).toBe('slds-theme_error');
  });
});
