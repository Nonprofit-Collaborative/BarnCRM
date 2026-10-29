import { createElement } from 'lwc';
import FirstRunModal from 'c/firstRunModal';
import finish from '@salesforce/apex/FirstRunController.finish';

jest.mock('@salesforce/apex/FirstRunController.finish', () => ({ default: jest.fn() }), {
  virtual: true
});

const FEATURES = [
  { key: 'DataManager', name: 'Data Manager', description: 'Bulk tools.', isOn: false },
  { key: 'Relationships', name: 'Relationships', description: 'Both sides.', isOn: false },
  { key: 'Addresses', name: 'Addresses', description: 'Seasonal.', isOn: false }
];

const ADMIN_STATE = {
  needsSetup: true,
  canFinish: true,
  recommendedSuite: 'Standard',
  features: FEATURES
};

function settle() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function build(state) {
  const element = createElement('c-first-run-modal', { is: FirstRunModal });
  element.state = state;
  document.body.appendChild(element);
  await settle();
  return element;
}

function byId(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

function all(element, id) {
  return Array.from(element.shadowRoot.querySelectorAll(`[data-id="${id}"]`));
}

function choose(element, id, value) {
  byId(element, id).dispatchEvent(new CustomEvent('change', { detail: { value } }));
}

describe('c-first-run-modal', () => {
  beforeEach(() => {
    finish.mockResolvedValue({ needsSetup: false, canFinish: true, features: [] });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('cannot be dismissed, and offers the editions as two picker cards', async () => {
    const element = await build(ADMIN_STATE);

    expect(element.disableClose).toBe(true);
    expect(element.shadowRoot.querySelector('lightning-modal-header').label).toBe(
      'c.Core_FirstRun_Title'
    );
    const picker = byId(element, 'edition');
    expect(picker.value).toBe('Standard');
    expect(picker.options.map((option) => option.label)).toEqual([
      'c.Core_SuiteChoice_StandardName',
      'c.Core_SuiteChoice_NonprofitName'
    ]);
    expect(picker.options.every((option) => option.iconName && option.description)).toBe(true);
    expect(byId(element, 'finish').label).toBe('c.Core_FirstRun_Finish');
  });

  it('tells someone who cannot finish that an administrator needs to', async () => {
    const element = await build({ needsSetup: true, canFinish: false, features: [] });

    expect(byId(element, 'admin-needed').textContent).toBe('c.Core_FirstRun_AdminNeeded');
    expect(byId(element, 'finish')).toBeNull();
    expect(byId(element, 'edition')).toBeNull();
  });

  it('lets someone who cannot finish close the window, so nobody is trapped', async () => {
    const element = await build({ needsSetup: true, canFinish: false, features: [] });
    const closed = jest.fn();
    element.addEventListener('close', closed);

    expect(element.disableClose).toBe(false);
    const close = byId(element, 'close');
    expect(close.label).toBe('c.Core_FirstRun_Close');
    close.click();
    expect(closed).toHaveBeenCalled();
  });

  it('offers an administrator no Close button', async () => {
    const element = await build(ADMIN_STATE);

    expect(byId(element, 'close')).toBeNull();
  });

  it('keeps Finish Setup disabled until an edition is chosen', async () => {
    const element = await build({ ...ADMIN_STATE, recommendedSuite: undefined });

    expect(byId(element, 'finish').disabled).toBe(true);
    choose(element, 'edition', 'Nonprofit');
    await settle();
    expect(byId(element, 'finish').disabled).toBe(false);
  });

  it('turns on every feature by default and closes as finished', async () => {
    const element = await build(ADMIN_STATE);
    const closed = jest.fn();
    element.addEventListener('close', closed);

    expect(all(element, 'feature')).toHaveLength(0);
    byId(element, 'finish').click();
    await settle();

    expect(finish).toHaveBeenCalledWith({
      suite: 'Standard',
      featureKeys: ['DataManager', 'Relationships', 'Addresses']
    });
    expect(closed.mock.calls[0][0].detail).toEqual({ finished: true });
    expect(element.disableClose).toBe(false);
  });

  it('lists every feature ticked when choosing, and leaves an unticked one off', async () => {
    const element = await build(ADMIN_STATE);

    choose(element, 'edition', 'Nonprofit');
    choose(element, 'mode', 'choose');
    await settle();
    const boxes = all(element, 'feature');
    expect(boxes.map((box) => box.checked)).toEqual([true, true, true]);

    boxes[1].checked = false;
    boxes[1].dispatchEvent(new CustomEvent('change'));
    await settle();
    byId(element, 'finish').click();
    await settle();

    expect(finish).toHaveBeenCalledWith({
      suite: 'Nonprofit',
      featureKeys: ['DataManager', 'Addresses']
    });
  });

  it('stays open and shows the message when finishing fails', async () => {
    finish.mockRejectedValue({ body: { message: 'Setup could not be finished.' } });
    const element = await build(ADMIN_STATE);
    const closed = jest.fn();
    element.addEventListener('close', closed);

    byId(element, 'finish').click();
    await settle();

    expect(closed).not.toHaveBeenCalled();
    expect(element.disableClose).toBe(true);
    expect(byId(element, 'error').textContent.trim()).toBe('Setup could not be finished.');
  });
});
