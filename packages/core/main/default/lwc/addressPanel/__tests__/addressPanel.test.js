// The object info test wire adapter is emitted to on purpose, which is how a wired component
// is driven from a test.
/* eslint-disable @lwc/lwc/no-unexpected-wire-adapter-usages */
import { createElement } from 'lwc';
import AddressPanel from 'c/addressPanel';
import { graphql } from 'lightning/graphql';
import { notifyRecordUpdateAvailable, updateRecord } from 'lightning/uiRecordApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import getCardContext from '@salesforce/apex/AddressMoveController.getCardContext';
import getMovePreview from '@salesforce/apex/AddressMoveController.getMovePreview';
import useForWholeHousehold from '@salesforce/apex/AddressMoveController.useForWholeHousehold';
import updateEveryonesAddress from '@salesforce/apex/AddressMoveController.updateEveryonesAddress';

jest.mock(
  '@salesforce/apex/AddressMoveController.getCardContext',
  () => {
    const { createApexTestWireAdapter } = jest.requireActual('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock('@salesforce/apex/AddressMoveController.getMovePreview', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/AddressMoveController.useForWholeHousehold',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/AddressMoveController.updateEveryonesAddress',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const RECORD_ID = '0011000000000001AA';

/** One address as the GraphQL query returns it; a household's unless `personal`. */
function node({ id, type, street, city, state, postalCode, isDefault, season, personal }) {
  return {
    Id: id,
    Account__c: { value: personal ? null : RECORD_ID },
    Type__c: { value: type, displayValue: type },
    Street__c: { value: street },
    City__c: { value: city },
    State__c: { value: state },
    Postal_Code__c: { value: postalCode },
    Country__c: { value: 'United States' },
    Is_Default__c: { value: isDefault },
    Seasonal_Start_Month__c: { value: season ? season[0] : null },
    Seasonal_Start_Day__c: { value: season ? season[1] : null },
    Seasonal_End_Month__c: { value: season ? season[2] : null },
    Seasonal_End_Day__c: { value: season ? season[3] : null }
  };
}

function response(nodes) {
  return { uiapi: { query: { Address__c: { edges: nodes.map((n) => ({ node: n })) } } } };
}

const HOME = node({
  id: 'a0100000000000AAAA',
  type: 'Home',
  street: '812 Willow Lane',
  city: 'Springfield',
  state: 'IL',
  postalCode: '62704',
  isDefault: true
});

const WINTER = node({
  id: 'a0100000000000BBBB',
  type: 'Seasonal',
  street: '4120 East Camelback Road',
  city: 'Phoenix',
  state: 'AZ',
  postalCode: '85018',
  isDefault: false,
  season: [1, 1, 3, 31]
});

/** What the platform says a user may do with addresses: Staff can, Read Only only reads. */
const STAFF_ACCESS = {
  createable: true,
  updateable: true,
  deletable: true,
  fields: { Is_Default__c: { updateable: true } }
};
const READ_ONLY_ACCESS = {
  createable: false,
  updateable: false,
  deletable: false,
  fields: { Is_Default__c: { updateable: false } }
};

function build(objectApiName = 'Account', access = STAFF_ACCESS) {
  const element = createElement('c-address-panel', { is: AddressPanel });
  element.recordId = RECORD_ID;
  element.objectApiName = objectApiName;
  document.body.appendChild(element);
  getObjectInfo.emit(access);
  return element;
}

function flush() {
  return Promise.resolve().then(() => Promise.resolve());
}

describe('c-address-panel', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('asks for the addresses of the record it sits on', async () => {
    build();
    await flush();
    expect(graphql.getLastConfig().variables).toEqual({ ownerId: RECORD_ID });
  });

  it('shows a loading state, not "no addresses", until the addresses arrive', async () => {
    const element = build();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="loading"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="empty"]')).toBeNull();

    graphql.emit(response([HOME]));
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="loading"]')).toBeNull();
  });

  it('shows a card for every address on file, the one in use first', async () => {
    const element = build();
    graphql.emit(response([WINTER, HOME]));
    await flush();

    const cards = element.shadowRoot.querySelectorAll('[data-id="address-card"]');
    expect(cards.length).toBe(2);
    const streets = Array.from(
      element.shadowRoot.querySelectorAll('[data-id="address-street"]')
    ).map((n) => n.textContent);
    expect(streets).toEqual(['812 Willow Lane', '4120 East Camelback Road']);
    expect(element.shadowRoot.querySelector('[data-id="address-city"]').textContent).toBe(
      'Springfield IL 62704'
    );
  });

  it('shows the type in the reader language', async () => {
    const element = build();
    graphql.emit(response([{ ...HOME, Type__c: { value: 'Home', displayValue: 'Domicilio' } }]));
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="address-type"]').textContent).toBe(
      'Domicilio'
    );
  });

  it('badges the address in use and offers to move the badge to the others', async () => {
    const element = build();
    graphql.emit(response([HOME, WINTER]));
    await flush();

    expect(element.shadowRoot.querySelectorAll('[data-id="default-badge"]').length).toBe(1);
    const buttons = element.shadowRoot.querySelectorAll('.set-default');
    expect(buttons.length).toBe(1);
    expect(buttons[0].dataset.id).toBe(WINTER.Id);
  });

  it('offers neither Add address nor Set as Primary to someone who can only read addresses', async () => {
    const element = build('Account', READ_ONLY_ACCESS);
    graphql.emit(response([HOME, WINTER]));
    await flush();

    expect(element.shadowRoot.querySelectorAll('[data-id="address-card"]').length).toBe(2);
    expect(element.shadowRoot.querySelector('[data-id="add-address"]')).toBeNull();
    expect(element.shadowRoot.querySelectorAll('.set-default').length).toBe(0);
  });

  it('offers no action until it knows what the user may do', async () => {
    const element = createElement('c-address-panel', { is: AddressPanel });
    element.recordId = RECORD_ID;
    element.objectApiName = 'Account';
    document.body.appendChild(element);
    graphql.emit(response([HOME, WINTER]));
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="add-address"]')).toBeNull();
    expect(element.shadowRoot.querySelectorAll('.set-default').length).toBe(0);
  });

  it('hides Set as Primary when the primary field cannot be edited', async () => {
    const element = build('Account', { ...STAFF_ACCESS, fields: {} });
    graphql.emit(response([HOME, WINTER]));
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="add-address"]')).not.toBeNull();
    expect(element.shadowRoot.querySelectorAll('.set-default').length).toBe(0);
  });

  it('reads the seasonal range as dates rather than numbers', async () => {
    const element = build();
    graphql.emit(response([WINTER]));
    await flush();

    const seasonal = element.shadowRoot.querySelector('[data-id="address-seasonal"]');
    expect(seasonal.textContent).toContain('January 1');
    expect(seasonal.textContent).toContain('March 31');
  });

  it('shows no range when the stored month is not a month', async () => {
    const element = build();
    graphql.emit(response([{ ...WINTER, Seasonal_Start_Month__c: { value: 13 } }]));
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="address-seasonal"]')).toBeNull();
  });

  it('says so when the household has no addresses yet', async () => {
    const element = build();
    graphql.emit(response([]));
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="empty"]')).not.toBeNull();
    expect(element.shadowRoot.querySelectorAll('[data-id="address-card"]').length).toBe(0);
  });

  it('shows a message when the addresses cannot be read', async () => {
    const element = build();
    graphql.emitErrors([{ message: 'no access' }]);
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="empty"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="loading"]')).toBeNull();
  });

  it('sets the default as the user, then reads the card and the record again', async () => {
    const refresh = jest.fn().mockResolvedValue();
    const element = build();
    graphql.emit(response([HOME, WINTER]), undefined, refresh);
    await flush();

    element.shadowRoot.querySelector('.set-default').click();
    await flush();

    expect(updateRecord).toHaveBeenCalledWith({
      fields: { Id: WINTER.Id, Is_Default__c: true }
    });
    expect(refresh).toHaveBeenCalledTimes(1);
    expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([{ recordId: RECORD_ID }]);

    graphql.emit(
      response([
        { ...WINTER, Is_Default__c: { value: true } },
        { ...HOME, Is_Default__c: { value: false } }
      ]),
      undefined,
      refresh
    );
    await flush();
    const buttons = element.shadowRoot.querySelectorAll('.set-default');
    expect(buttons[0].dataset.id).toBe(HOME.Id);
  });

  it('shows a message when the default could not be changed', async () => {
    updateRecord.mockRejectedValueOnce(new Error('no'));
    const element = build();
    graphql.emit(response([HOME, WINTER]));
    await flush();

    element.shadowRoot.querySelector('.set-default').click();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error"]')).not.toBeNull();
    expect(notifyRecordUpdateAvailable).not.toHaveBeenCalled();
  });

  it('opens and closes the new address form', async () => {
    const element = build();
    graphql.emit(response([HOME]));
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="add-form"]')).toBeNull();
    element.shadowRoot.querySelector('[data-id="add-address"]').click();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="add-form"]')).not.toBeNull();

    element.shadowRoot.querySelector('[data-id="cancel"]').click();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="add-form"]')).toBeNull();
  });

  it('ties a new address to the household when it sits on an account', async () => {
    const element = build('Account');
    graphql.emit(response([HOME]));
    await flush();
    element.shadowRoot.querySelector('[data-id="add-address"]').click();
    await flush();

    const owner = element.shadowRoot.querySelector('lightning-input-field');
    expect(owner.fieldName).toBe('Account__c');
    expect(owner.value).toBe(RECORD_ID);
  });

  it('ties a new address to the person when it sits on a contact', async () => {
    const element = build('Contact');
    graphql.emit(response([HOME]));
    await flush();
    element.shadowRoot.querySelector('[data-id="add-address"]').click();
    await flush();

    const owner = element.shadowRoot.querySelector('lightning-input-field');
    expect(owner.fieldName).toBe('Contact__c');
  });

  it('saves the first address as the one in use', async () => {
    const element = build('Account');
    graphql.emit(response([]));
    await flush();
    element.shadowRoot.querySelector('[data-id="add-address"]').click();
    await flush();

    const flag = element.shadowRoot.querySelector('[data-id="first-address-default"]');
    expect(flag.fieldName).toBe('Is_Default__c');
    expect(flag.value).toBe(true);
  });

  it('leaves the default alone when the record already has addresses', async () => {
    const element = build('Account');
    graphql.emit(response([HOME]));
    await flush();
    element.shadowRoot.querySelector('[data-id="add-address"]').click();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="first-address-default"]')).toBeNull();
  });

  it('does not guess the first address when the list could not be read', async () => {
    const element = build('Account');
    graphql.emitErrors([{ message: 'boom' }]);
    await flush();
    const add = element.shadowRoot.querySelector('[data-id="add-address"]');
    if (add) {
      add.click();
      await flush();
    }

    expect(element.shadowRoot.querySelector('[data-id="first-address-default"]')).toBeNull();
  });

  it('closes the form and reads the card and the record again after a new address is saved', async () => {
    const refresh = jest.fn().mockResolvedValue();
    const element = build();
    graphql.emit(response([HOME]), undefined, refresh);
    await flush();
    element.shadowRoot.querySelector('[data-id="add-address"]').click();
    await flush();

    const form = element.shadowRoot.querySelector('lightning-record-edit-form');
    form.dispatchEvent(new CustomEvent('success'));
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="add-form"]')).toBeNull();
    expect(refresh).toHaveBeenCalledTimes(1);
    expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([{ recordId: RECORD_ID }]);
  });

  describe('household moves', () => {
    const GARCIA = { id: '0011000000000002AA', name: 'The Garcia Family' };
    const NOWAK = { id: '0011000000000003AA', name: 'The Nowak Family' };
    const OWN = node({
      id: 'a0100000000000CCCC',
      type: 'Home',
      street: '9 Dorm Hall',
      city: 'Urbana',
      isDefault: true,
      personal: true
    });
    const OWN_SEASONAL = node({
      id: 'a0100000000000DDDD',
      type: 'Seasonal',
      street: '1 Beach Road',
      isDefault: false,
      season: [6, 1, 8, 31],
      personal: true
    });

    function personWith(households) {
      const element = build('Contact');
      graphql.emit(response([OWN, OWN_SEASONAL]));
      getCardContext.emit({ isHousehold: false, households });
      return element;
    }

    function household() {
      const element = build('Account');
      graphql.emit(response([HOME, WINTER]));
      getCardContext.emit({ isHousehold: true, households: [] });
      return element;
    }

    function click(element, selector) {
      element.shadowRoot.querySelector(selector).click();
    }

    it('offers Use for Whole Household on an address of the person, not a seasonal one', async () => {
      const element = personWith([GARCIA]);
      await flush();

      const buttons = element.shadowRoot.querySelectorAll('.use-for-household');
      expect(buttons.length).toBe(1);
      expect(buttons[0].dataset.id).toBe(OWN.Id);
      expect(element.shadowRoot.querySelector('.update-everyone')).toBeNull();
    });

    it('offers no move to a person with no household, or to someone who only reads', async () => {
      const lonely = personWith([]);
      await flush();
      expect(lonely.shadowRoot.querySelector('.use-for-household')).toBeNull();

      const reader = build('Account', READ_ONLY_ACCESS);
      graphql.emit(response([HOME]));
      getCardContext.emit({ isHousehold: true, households: [] });
      await flush();
      expect(reader.shadowRoot.querySelector('.update-everyone')).toBeNull();
    });

    it('moves the household to the address, without asking which, when there is one', async () => {
      const refresh = jest.fn().mockResolvedValue();
      const element = build('Contact');
      graphql.emit(response([OWN]), undefined, refresh);
      getCardContext.emit({ isHousehold: false, households: [GARCIA] });
      useForWholeHousehold.mockResolvedValue();
      await flush();

      click(element, '.use-for-household');
      await flush();
      expect(element.shadowRoot.querySelector('[data-id="household-picker"]')).toBeNull();
      click(element, '[data-id="confirm-move"]');
      await flush();

      expect(useForWholeHousehold).toHaveBeenCalledWith({
        addressId: OWN.Id,
        householdId: GARCIA.id
      });
      expect(refresh).toHaveBeenCalledTimes(1);
      expect(element.shadowRoot.querySelector('[data-id="use-for-household-confirm"]')).toBeNull();
    });

    it('asks which household when the person belongs to several, their own first', async () => {
      const element = personWith([NOWAK, GARCIA]);
      useForWholeHousehold.mockResolvedValue();
      await flush();

      click(element, '.use-for-household');
      await flush();
      const picker = element.shadowRoot.querySelector('[data-id="household-picker"]');
      expect(picker.options.map((option) => option.label)).toEqual([
        'The Nowak Family',
        'The Garcia Family'
      ]);
      expect(picker.value).toBe(NOWAK.id);

      picker.dispatchEvent(new CustomEvent('change', { detail: { value: GARCIA.id } }));
      click(element, '[data-id="confirm-move"]');
      await flush();

      expect(useForWholeHousehold).toHaveBeenCalledWith({
        addressId: OWN.Id,
        householdId: GARCIA.id
      });
    });

    it('offers Update Everyone on the primary address of the household only', async () => {
      const element = household();
      await flush();

      const buttons = element.shadowRoot.querySelectorAll('.update-everyone');
      expect(buttons.length).toBe(1);
      expect(buttons[0].dataset.id).toBe(HOME.Id);
      expect(element.shadowRoot.querySelector('.use-for-household')).toBeNull();
    });

    it('lists who moves and who has their own, and moves only those ticked', async () => {
      getMovePreview.mockResolvedValue({
        hasPrimary: true,
        moving: [{ id: '0031000000000001AA', name: 'Luis Garcia' }],
        withTheirOwn: [
          { id: '0031000000000002AA', name: 'Ana Garcia' },
          { id: '0031000000000003AA', name: 'Sofia Garcia' }
        ]
      });
      updateEveryonesAddress.mockResolvedValue();
      const element = household();
      await flush();

      click(element, '.update-everyone');
      await flush();
      expect(getMovePreview).toHaveBeenCalledWith({ householdId: RECORD_ID });
      const moving = element.shadowRoot.querySelectorAll('[data-id="moving-person"]');
      expect(Array.from(moving).map((item) => item.textContent)).toEqual(['Luis Garcia']);
      const owners = element.shadowRoot.querySelectorAll('.own-address-person');
      expect(owners.length).toBe(2);

      owners[0].checked = true;
      owners[0].dispatchEvent(new CustomEvent('change'));
      click(element, '[data-id="confirm-move"]');
      await flush();

      expect(updateEveryonesAddress).toHaveBeenCalledWith({
        householdId: RECORD_ID,
        alsoMove: ['0031000000000002AA']
      });
      expect(element.shadowRoot.querySelector('[data-id="update-everyone-confirm"]')).toBeNull();
    });

    it('says so when everyone has an address of their own, and cancels', async () => {
      getMovePreview.mockResolvedValue({ hasPrimary: true, moving: [], withTheirOwn: [] });
      const element = household();
      await flush();

      click(element, '.update-everyone');
      await flush();
      expect(element.shadowRoot.querySelector('[data-id="nobody-moving"]')).not.toBeNull();

      click(element, '[data-id="cancel-move"]');
      await flush();
      expect(element.shadowRoot.querySelector('[data-id="update-everyone-confirm"]')).toBeNull();
      expect(updateEveryonesAddress).not.toHaveBeenCalled();
    });

    it('shows the reason when a move is refused', async () => {
      getMovePreview.mockResolvedValue({ hasPrimary: true, moving: [], withTheirOwn: [] });
      updateEveryonesAddress.mockRejectedValue({ body: { message: 'Not allowed.' } });
      const element = household();
      await flush();

      click(element, '.update-everyone');
      await flush();
      click(element, '[data-id="confirm-move"]');
      await flush();

      expect(element.shadowRoot.querySelector('[data-id="error"]').textContent).toContain(
        'Not allowed.'
      );
      expect(notifyRecordUpdateAvailable).not.toHaveBeenCalled();
    });

    it('shows its own message when the preview fails without one', async () => {
      getMovePreview.mockRejectedValue(new Error('offline'));
      const element = household();
      await flush();

      click(element, '.update-everyone');
      await flush();

      expect(element.shadowRoot.querySelector('[data-id="error"]').textContent).toContain(
        'c.Core_Address_MoveFailed'
      );
    });
  });
});
