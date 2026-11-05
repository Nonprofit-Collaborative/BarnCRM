import { createElement } from 'lwc';
import BarnNotice from 'c/barnNotice';

// Storybook-style: one story per variant, the action as a link and as a button.
function render(props) {
  const element = createElement('c-barn-notice', { is: BarnNotice });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

const one = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-barn-notice', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it.each([
    ['info', 'slds-scoped-notification_light', 'utility:info', 'status'],
    ['success', 'slds-scoped-notification_light', 'utility:success', 'status'],
    ['warning', 'slds-theme_warning', 'utility:warning', 'status'],
    ['error', 'slds-theme_error', 'utility:error', 'alert'],
    [undefined, 'slds-scoped-notification_light', 'utility:info', 'status']
  ])('story: variant %s', (variant, containerClass, icon, role) => {
    const element = render({ variant, message: 'Something happened.' });
    const notice = one(element, 'notice');
    expect(notice.classList).toContain('slds-scoped-notification');
    expect(notice.classList).toContain(containerClass);
    expect(notice.getAttribute('role')).toBe(role);
    expect(one(element, 'icon').iconName).toBe(icon);
    expect(one(element, 'message').textContent).toBe('Something happened.');
    expect(one(element, 'title')).toBeNull();
    expect(one(element, 'action')).toBeNull();
  });

  it('story: a title and an action link', () => {
    const element = render({
      variant: 'success',
      title: 'Gift Saved',
      message: 'The gift is recorded.',
      actionLabel: 'Open Gift',
      actionHref: '/lightning/r/Gift__c/a01/view'
    });
    expect(one(element, 'title').textContent).toBe('Gift Saved');
    const action = one(element, 'action');
    expect(action.tagName).toBe('A');
    expect(action.getAttribute('href')).toBe('/lightning/r/Gift__c/a01/view');
    expect(action.textContent).toBe('Open Gift');
  });

  it('story: an action button fires action', () => {
    const element = render({
      variant: 'warning',
      message: 'Check the file.',
      actionLabel: 'Try Again'
    });
    const handler = jest.fn();
    element.addEventListener('action', handler);
    const action = one(element, 'action');
    expect(action.tagName).toBe('BUTTON');
    action.click();
    expect(handler).toHaveBeenCalledTimes(1);
  });
});
