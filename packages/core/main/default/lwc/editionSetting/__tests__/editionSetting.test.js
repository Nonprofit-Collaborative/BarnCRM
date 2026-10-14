import { createElement } from 'lwc';
import EditionSetting from 'c/editionSetting';
import BarnConfirmModal from 'c/barnConfirmModal';
import getEdition from '@salesforce/apex/SetupAssistantController.getEdition';
import changeEdition from '@salesforce/apex/SetupAssistantController.changeEdition';

jest.mock('@salesforce/apex/SetupAssistantController.getEdition', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/SetupAssistantController.changeEdition',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

function flushPromises() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function build() {
  const element = createElement('c-edition-setting', { is: EditionSetting });
  document.body.appendChild(element);
  await flushPromises();
  return element;
}

function find(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

function switchButtons(element) {
  return Array.from(element.shadowRoot.querySelectorAll('lightning-button'));
}

describe('c-edition-setting', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows the edition read-only, with the change tucked into a closed disclosure', async () => {
    getEdition.mockResolvedValue({ currentSuite: 'Community', canEdit: true });
    const element = await build();

    expect(find(element, 'edition-name').textContent).toBe('c.Core_SuiteChoice_StandardName');
    const disclosure = find(element, 'change-edition');
    expect(disclosure).not.toBeNull();
    expect(disclosure.open).toBe(false);
    const buttons = switchButtons(element);
    expect(buttons.map((button) => button.dataset.value)).toEqual(['Impact']);
  });

  it('offers no change to someone who cannot manage settings', async () => {
    getEdition.mockResolvedValue({ currentSuite: 'Impact', canEdit: false });
    const element = await build();

    expect(find(element, 'edition-name').textContent).toBe('c.Core_SuiteChoice_NonprofitName');
    expect(find(element, 'change-edition')).toBeNull();
  });

  it('says when no edition is chosen and offers both', async () => {
    getEdition.mockResolvedValue({ currentSuite: null, canEdit: true });
    const element = await build();

    expect(find(element, 'edition-not-chosen')).not.toBeNull();
    expect(switchButtons(element).map((button) => button.dataset.value)).toEqual([
      'Community',
      'Impact'
    ]);
  });

  it('changes nothing when the confirmation is cancelled', async () => {
    getEdition.mockResolvedValue({ currentSuite: 'Community', canEdit: true });
    BarnConfirmModal.open.mockResolvedValue(false);
    const element = await build();

    switchButtons(element)[0].click();
    await flushPromises();

    expect(BarnConfirmModal.open).toHaveBeenCalledWith(
      expect.objectContaining({ message: 'c.Core_Edition_ConfirmToNonprofit' })
    );
    expect(changeEdition).not.toHaveBeenCalled();
  });

  it('saves the other edition after confirmation and shows it', async () => {
    getEdition.mockResolvedValue({ currentSuite: 'Impact', canEdit: true });
    BarnConfirmModal.open.mockResolvedValue(true);
    changeEdition.mockResolvedValue({ currentSuite: 'Community', canEdit: true });
    const element = await build();

    switchButtons(element)[0].click();
    await flushPromises();

    expect(BarnConfirmModal.open).toHaveBeenCalledWith(
      expect.objectContaining({ message: 'c.Core_Edition_ConfirmToStandard' })
    );
    expect(changeEdition).toHaveBeenCalledWith({ suite: 'Community' });
    expect(find(element, 'edition-name').textContent).toBe('c.Core_SuiteChoice_StandardName');
    expect(find(element, 'saved')).not.toBeNull();
  });

  it('shows the message when the save is refused', async () => {
    getEdition.mockResolvedValue({ currentSuite: 'Impact', canEdit: true });
    BarnConfirmModal.open.mockResolvedValue(true);
    changeEdition.mockRejectedValue({ body: { message: 'No permission' } });
    const element = await build();

    switchButtons(element)[0].click();
    await flushPromises();

    expect(find(element, 'error').textContent).toBe('No permission');
    expect(find(element, 'saved')).toBeNull();
  });
});
