import { createElement } from 'lwc';
import SetupStepCoexistence from 'c/setupStepCoexistence';

function build(coexistence, canEdit = true) {
  const element = createElement('c-setup-step-coexistence', { is: SetupStepCoexistence });
  element.coexistence = coexistence;
  element.canEdit = canEdit;
  document.body.appendChild(element);
  return element;
}

const NONPROFIT_CLOUD = {
  detectedShape: 'PersonAccounts',
  recommendedMode: 'NonprofitCloud',
  currentMode: null,
  modes: ['Standalone', 'NPSP', 'NonprofitCloud']
};

describe('c-setup-step-coexistence', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('leads with what Maria has, in her own org', () => {
    const element = build(NONPROFIT_CLOUD);

    const shape = element.shadowRoot.querySelector('[data-id="shape"]');
    expect(shape.textContent).toContain('Core_SetupAssistant_ShapePersonAccounts');
    const recommended = element.shadowRoot.querySelector('[data-id="recommended"]');
    expect(recommended.textContent).toContain('Core_SetupAssistant_ModeNonprofitCloud');
  });

  it('offers the recommendation already chosen, and the other two modes', () => {
    const element = build(NONPROFIT_CLOUD);

    const combobox = element.shadowRoot.querySelector('lightning-combobox');
    expect(combobox.value).toBe('NonprofitCloud');
    expect(combobox.options).toHaveLength(3);
  });

  it('keeps the mode already in force rather than the recommendation', () => {
    const element = build({ ...NONPROFIT_CLOUD, currentMode: 'Standalone' });

    expect(element.shadowRoot.querySelector('lightning-combobox').value).toBe('Standalone');
  });

  it('confirms the mode Maria chose', () => {
    const element = build(NONPROFIT_CLOUD);
    const confirmed = jest.fn();
    element.addEventListener('confirm', confirmed);

    const combobox = element.shadowRoot.querySelector('lightning-combobox');
    combobox.dispatchEvent(new CustomEvent('change', { detail: { value: 'NPSP' } }));
    element.shadowRoot.querySelector('lightning-button').click();

    expect(confirmed).toHaveBeenCalled();
    expect(confirmed.mock.calls[0][0].detail.mode).toBe('NPSP');
  });

  it('lets David read the recommendation without acting on it', () => {
    const element = build(NONPROFIT_CLOUD, false);

    expect(element.shadowRoot.querySelector('lightning-button')).toBeNull();
    expect(element.shadowRoot.querySelector('lightning-combobox').disabled).toBe(true);
  });
});
