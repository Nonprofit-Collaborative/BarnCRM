import { createElement } from 'lwc';
import FeatureSettings from 'c/featureSettings';
import BarnConfirmModal from 'c/barnConfirmModal';
import getFeatures from '@salesforce/apex/FeatureController.getFeatures';
import turnOn from '@salesforce/apex/FeatureController.turnOn';

jest.mock('@salesforce/apex/FeatureController.getFeatures', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FeatureController.turnOn', () => ({ default: jest.fn() }), {
  virtual: true
});

const MODEL = {
  canEdit: true,
  features: [
    { key: 'DataManager', name: 'Data Manager', description: 'Bulk tools.', isOn: true },
    { key: 'Relationships', name: 'Relationships', description: 'Both sides.', isOn: false }
  ]
};

function flushPromises() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function build() {
  const element = createElement('c-feature-settings', { is: FeatureSettings });
  document.body.appendChild(element);
  await flushPromises();
  return element;
}

function all(element, id) {
  return Array.from(element.shadowRoot.querySelectorAll(`[data-id="${id}"]`));
}

describe('c-feature-settings', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('warns that turning a feature on is one-way, and offers Turn on only for those off', async () => {
    getFeatures.mockResolvedValue(MODEL);
    const element = await build();

    expect(all(element, 'one-way-warning')).toHaveLength(1);
    expect(all(element, 'feature-row')).toHaveLength(2);
    const buttons = all(element, 'turn-on');
    expect(buttons.map((button) => button.dataset.key)).toEqual(['Relationships']);
    expect(all(element, 'state').map((state) => state.textContent)).toEqual(['c.Core_Feature_On']);
  });

  it('offers no Turn on to someone who cannot manage settings', async () => {
    getFeatures.mockResolvedValue({ ...MODEL, canEdit: false });
    const element = await build();

    expect(all(element, 'turn-on')).toHaveLength(0);
    expect(all(element, 'state')).toHaveLength(2);
  });

  it('turns nothing on when the confirmation is cancelled', async () => {
    getFeatures.mockResolvedValue(MODEL);
    BarnConfirmModal.open.mockResolvedValue(false);
    const element = await build();

    all(element, 'turn-on')[0].click();
    await flushPromises();

    expect(BarnConfirmModal.open).toHaveBeenCalledTimes(1);
    expect(turnOn).not.toHaveBeenCalled();
  });

  it('turns the feature on after the confirmation and shows it as on', async () => {
    getFeatures.mockResolvedValue(MODEL);
    BarnConfirmModal.open.mockResolvedValue(true);
    turnOn.mockResolvedValue({
      canEdit: true,
      features: MODEL.features.map((feature) => ({ ...feature, isOn: true }))
    });
    const element = await build();

    all(element, 'turn-on')[0].click();
    await flushPromises();

    expect(turnOn).toHaveBeenCalledWith({ key: 'Relationships' });
    expect(all(element, 'turn-on')).toHaveLength(0);
    expect(all(element, 'saved')).toHaveLength(1);
  });

  it('shows the message when turning on fails', async () => {
    getFeatures.mockResolvedValue(MODEL);
    BarnConfirmModal.open.mockResolvedValue(true);
    turnOn.mockRejectedValue({ body: { message: 'Could not turn it on.' } });
    const element = await build();

    all(element, 'turn-on')[0].click();
    await flushPromises();

    expect(all(element, 'error')[0].textContent).toBe('Could not turn it on.');
  });
});
