import { createElement } from 'lwc';
import DuplicateRulesStarter from 'c/duplicateRulesStarter';
import getView from '@salesforce/apex/DuplicateRulesStarter.getView';
import start from '@salesforce/apex/DuplicateRulesStarter.start';
import BarnConfirmModal from 'c/barnConfirmModal';

jest.mock('@salesforce/apex/DuplicateRulesStarter.getView', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/DuplicateRulesStarter.start', () => ({ default: jest.fn() }), {
  virtual: true
});

const VIEW = {
  canUse: true,
  connected: true,
  running: false,
  sets: [
    {
      key: 'People',
      heading: 'People',
      action: 'Create',
      summary: 'Same first and last name',
      steps: ['Create the matching rule', 'Create the duplicate rule'],
      orgRules: ['Standard Contact Duplicate Rule (active, left as it is)']
    },
    {
      key: 'Household',
      heading: 'Households',
      action: 'None',
      summary: 'Households only',
      steps: [],
      orgRules: []
    }
  ]
};

function flush() {
  return Promise.resolve().then(() => Promise.resolve());
}

function render() {
  const element = createElement('c-duplicate-rules-starter', { is: DuplicateRulesStarter });
  document.body.appendChild(element);
  return element;
}

describe('c-duplicate-rules-starter', () => {
  beforeEach(() => {
    BarnConfirmModal.open = jest.fn().mockResolvedValue(true);
    getView.mockResolvedValue(VIEW);
    start.mockResolvedValue({ ...VIEW, running: true });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows the org rules, the steps, and chooses the sets that need work', async () => {
    const element = render();
    await flush();
    const root = element.shadowRoot;
    expect(root.querySelectorAll('[data-id="set"]')).toHaveLength(2);
    expect(root.querySelectorAll('[data-id="step"]')).toHaveLength(2);
    expect(root.querySelector('[data-id="org-rule"]').textContent).toContain('Standard Contact');
    expect(root.querySelectorAll('[data-id="choose"]')).toHaveLength(1);
    expect(root.querySelector('[data-id="choose"]').checked).toBe(true);
    expect(root.querySelector('[data-id="set-up"]').disabled).toBe(false);
  });

  it('confirms with the steps, then starts the chosen sets', async () => {
    const element = render();
    await flush();
    element.shadowRoot.querySelector('[data-id="set-up"]').click();
    await flush();
    const dialog = BarnConfirmModal.open.mock.calls[0][0];
    expect(dialog.items).toEqual(['Create the matching rule', 'Create the duplicate rule']);
    expect(start).toHaveBeenCalledWith({ keys: ['People'] });
  });

  it('does nothing when the confirm is declined, and nothing once unchosen', async () => {
    BarnConfirmModal.open = jest.fn().mockResolvedValue(false);
    const element = render();
    await flush();
    element.shadowRoot.querySelector('[data-id="set-up"]').click();
    await flush();
    expect(start).not.toHaveBeenCalled();
    const box = element.shadowRoot.querySelector('[data-id="choose"]');
    box.checked = false;
    box.dispatchEvent(new CustomEvent('change'));
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="set-up"]').disabled).toBe(true);
  });

  it('explains a missing connection and shows its setup panel', async () => {
    getView.mockResolvedValue({ ...VIEW, connected: false });
    const element = render();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="connection-needed"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="connection"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="set-up"]').disabled).toBe(true);
  });

  it('says when the person lacks the connection permissions', async () => {
    getView.mockResolvedValue({ ...VIEW, canUse: false, connected: false });
    const element = render();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="no-permission"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="connection"]')).toBeNull();
  });

  it('shows the error when the view cannot load', async () => {
    getView.mockRejectedValue({ body: { message: 'No access' } });
    const element = render();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="error"]').message).toBe('No access');
  });
});
