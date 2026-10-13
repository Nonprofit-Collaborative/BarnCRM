import { createElement } from 'lwc';
import PersonErasure from 'c/personErasure';

jest.mock('@salesforce/customPermission/Erase_People', () => ({ default: false }), {
  virtual: true
});
jest.mock('@salesforce/apex/PersonErasureController.preview', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/PersonErasureController.erase', () => ({ default: jest.fn() }), {
  virtual: true
});

describe('c-person-erasure without Erase People', () => {
  it('says which permission is needed and offers no preview or erase', () => {
    const element = createElement('c-person-erasure', { is: PersonErasure });
    element.recordId = '003000000000001AAA';
    document.body.appendChild(element);

    const root = element.shadowRoot;
    expect(root.querySelector('[data-id="no-permission"]')).not.toBeNull();
    expect(root.querySelector('[data-id="preview"]')).toBeNull();
    expect(root.querySelector('[data-id="erase"]')).toBeNull();
  });
});
