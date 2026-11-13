import { LightningElement, api, wire } from 'lwc';
import Toast from 'lightning/toast';
import { NavigationMixin } from 'lightning/navigation';
import { EnclosingTabId } from 'lightning/platformWorkspaceApi';
import { gql, graphql } from 'lightning/graphql';
import { notifyRecordUpdateAvailable, updateRecord } from 'lightning/uiRecordApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import LOCALE from '@salesforce/i18n/locale';
import BarnConfirmModal from 'c/barnConfirmModal';
import { iconFor } from 'c/barnIcons';
import { localIsoDate } from 'c/findCsv';
import { opensElsewhere, recordHref } from 'c/recordRows';
import { followLinkInWorkspace } from 'c/workspaceTabs';

import isFeatureOn from '@salesforce/apex/AddressMoveController.isFeatureOn';
import getCardContext from '@salesforce/apex/AddressMoveController.getCardContext';
import getCardFields from '@salesforce/apex/AddressMoveController.getCardFields';
import getMovePreview from '@salesforce/apex/AddressMoveController.getMovePreview';
// Not named useForWholeHousehold: a name starting with "use" reads as a React hook to Code
// Analyzer's react-hooks rule (High), which fails the merge gate.
import applyToWholeHousehold from '@salesforce/apex/AddressMoveController.useForWholeHousehold';
import updateEveryonesAddress from '@salesforce/apex/AddressMoveController.updateEveryonesAddress';

import ADDRESS_SCHEMA from '@salesforce/schema/Address__c';
import ID_FIELD from '@salesforce/schema/Address__c.Id';
import IS_DEFAULT_FIELD from '@salesforce/schema/Address__c.Is_Default__c';
import STATUS_FIELD from '@salesforce/schema/Address__c.Status__c';
import END_DATE_FIELD from '@salesforce/schema/Address__c.End_Date__c';
import TYPE_FIELD from '@salesforce/schema/Address__c.Type__c';
import STREET_FIELD from '@salesforce/schema/Address__c.Street__c';
import CITY_FIELD from '@salesforce/schema/Address__c.City__c';
import STATE_FIELD from '@salesforce/schema/Address__c.State__c';
import POSTAL_CODE_FIELD from '@salesforce/schema/Address__c.Postal_Code__c';
import COUNTRY_FIELD from '@salesforce/schema/Address__c.Country__c';
import SEASONAL_START_MONTH_FIELD from '@salesforce/schema/Address__c.Seasonal_Start_Month__c';
import SEASONAL_START_DAY_FIELD from '@salesforce/schema/Address__c.Seasonal_Start_Day__c';
import SEASONAL_END_MONTH_FIELD from '@salesforce/schema/Address__c.Seasonal_End_Month__c';
import SEASONAL_END_DAY_FIELD from '@salesforce/schema/Address__c.Seasonal_End_Day__c';
import CONTACT_FIELD from '@salesforce/schema/Address__c.Contact__c';
import ACCOUNT_FIELD from '@salesforce/schema/Address__c.Account__c';

import PANEL_TITLE from '@salesforce/label/c.Core_Feature_Addresses_Name';
import ADD_BUTTON from '@salesforce/label/c.Core_Address_AddButton';
import ADD_FORM_TITLE from '@salesforce/label/c.Core_Address_AddFormTitle';
import CANCEL_BUTTON from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import DEFAULT_BADGE from '@salesforce/label/c.Core_HouseholdMembersPanel_Primary';
import EMPTY_HEADING from '@salesforce/label/c.Core_Address_EmptyHeading';
import LOADING from '@salesforce/label/c.Core_Address_Loading';
import SEASONAL_RANGE from '@salesforce/label/c.Core_Address_SeasonalRange';
import SEASONAL_RANGE_TO from '@salesforce/label/c.Core_Address_SeasonalRangeTo';
import SET_DEFAULT_BUTTON from '@salesforce/label/c.Core_Address_SetDefaultButton';
import UPDATE_EVERYONE_BUTTON from '@salesforce/label/c.Core_Address_UpdateEveryoneButton';
import UPDATE_EVERYONE_MOVING from '@salesforce/label/c.Core_Address_UpdateEveryoneMoving';
import UPDATE_EVERYONE_TITLE from '@salesforce/label/c.Core_Address_UpdateEveryoneTitle';
import USE_FOR_HOUSEHOLD_BUTTON from '@salesforce/label/c.Core_Address_UseForHouseholdButton';
import USE_FOR_HOUSEHOLD_PICK from '@salesforce/label/c.Core_Address_UseForHouseholdPick';
import USE_FOR_HOUSEHOLD_TITLE from '@salesforce/label/c.Core_Address_UseForHouseholdTitle';
import FORMER_HEADING from '@salesforce/label/c.Core_Address_FormerHeading';
import DATE_RANGE from '@salesforce/label/c.Core_Address_DateRange';
import DATE_SINCE from '@salesforce/label/c.Core_Address_DateSince';
import DATE_UNTIL from '@salesforce/label/c.Core_Address_DateUntil';
import UNDELIVERABLE_BADGE from '@salesforce/label/c.Core_Address_UndeliverableBadge';
import MORE_MENU from '@salesforce/label/c.Core_Settings_NavGroup_More';
import EDIT_ACTION from '@salesforce/label/c.Core_CmdtManager_EditAction';
import MARK_CURRENT from '@salesforce/label/c.Core_Address_MarkCurrent';
import MARK_FORMER from '@salesforce/label/c.Core_Address_MarkFormer';
import MARK_UNDELIVERABLE from '@salesforce/label/c.Core_Address_MarkUndeliverable';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const ADDRESS_OBJECT = ADDRESS_SCHEMA.objectApiName;
const FORM_FIELDS = [
  TYPE_FIELD,
  STREET_FIELD,
  CITY_FIELD,
  STATE_FIELD,
  POSTAL_CODE_FIELD,
  COUNTRY_FIELD,
  SEASONAL_START_MONTH_FIELD,
  SEASONAL_START_DAY_FIELD,
  SEASONAL_END_MONTH_FIELD,
  SEASONAL_END_DAY_FIELD
].map((field) => field.fieldApiName);
const SEASONAL_TYPE = 'Seasonal';
const STATUS_CURRENT = 'Current';
const STATUS_FORMER = 'Former';
const STATUS_UNDELIVERABLE = 'Undeliverable';
const MOVE_FOR_HOUSEHOLD = 'household';
const MOVE_FOR_EVERYONE = 'everyone';
const EDIT = 'edit';

/**
 * The record's addresses, read as the user through the platform, so field security and
 * sharing apply and the card picks up edits made elsewhere on the page. The record is a
 * household or organization (Account__c), a person stored as a contact (Contact__c) or a
 * person stored as an account (Person_Account__c); all three lookups exist in every org.
 * At most 2,000, the most a query returns at once. Status, start date and end date are
 * @optional: a user without read on one still gets the card, with that value null or absent
 * (a missing status counts as Current, a missing date as blank).
 */
const ADDRESSES_QUERY = gql`
  query addressPanel($ownerId: ID) {
    uiapi {
      query {
        Address__c(
          where: {
            or: [
              { Account__c: { eq: $ownerId } }
              { Contact__c: { eq: $ownerId } }
              { Person_Account__c: { eq: $ownerId } }
            ]
          }
          orderBy: { CreatedDate: { order: DESC } }
          first: 2000
        ) {
          edges {
            node {
              Id
              Account__c {
                value
              }
              Type__c {
                value
                displayValue
              }
              Street__c {
                value
              }
              City__c {
                value
              }
              State__c {
                value
              }
              Postal_Code__c {
                value
              }
              Country__c {
                value
              }
              Is_Default__c {
                value
              }
              Seasonal_Start_Month__c {
                value
              }
              Seasonal_Start_Day__c {
                value
              }
              Seasonal_End_Month__c {
                value
              }
              Seasonal_End_Day__c {
                value
              }
              Status__c @optional {
                value
              }
              Start_Date__c @optional {
                value
              }
              End_Date__c @optional {
                value
              }
            }
          }
        }
      }
    }
  }
`;

function read(field) {
  return field ? field.value : null;
}

/** "January 1", in the reader's own language, from the two numbers we store. */
function monthAndDay(month, day) {
  if (!(month >= 1 && month <= 12 && day >= 1 && day <= 31)) {
    return null;
  }
  const name = new Intl.DateTimeFormat(LOCALE, { month: 'long', timeZone: 'UTC' }).format(
    new Date(Date.UTC(2001, Math.trunc(month) - 1, 1))
  );
  return `${name} ${Math.trunc(day)}`;
}

/** One address as the card draws it. */
function toView(node) {
  const type = node.Type__c || {};
  return {
    id: node.Id,
    addressType: type.displayValue || type.value || null,
    street: read(node.Street__c),
    city: read(node.City__c),
    state: read(node.State__c),
    postalCode: read(node.Postal_Code__c),
    country: read(node.Country__c),
    isDefault: read(node.Is_Default__c) === true,
    isSeasonal: type.value === SEASONAL_TYPE,
    // An address with no household or organization is a person's own (R-AD1).
    isPersonal: !read(node.Account__c),
    seasonalStart: monthAndDay(
      read(node.Seasonal_Start_Month__c),
      read(node.Seasonal_Start_Day__c)
    ),
    seasonalEnd: monthAndDay(read(node.Seasonal_End_Month__c), read(node.Seasonal_End_Day__c)),
    // A blank status, on an address saved before statuses existed, is Current (R-AD10).
    status: read(node.Status__c) || STATUS_CURRENT,
    startDate: read(node.Start_Date__c),
    endDate: read(node.End_Date__c)
  };
}

/** Today as YYYY-MM-DD in the reader's own time zone, to compare with a stored date. */
function todayText() {
  return localIsoDate(new Date());
}

/** "October 26, 2026", in the reader's own language, from a stored YYYY-MM-DD. */
function longDate(value) {
  if (!value) {
    return null;
  }
  return new Intl.DateTimeFormat(LOCALE, {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    timeZone: 'UTC'
  }).format(new Date(`${value}T00:00:00Z`));
}

/** "Since ...", "Until ..." or "... to ...", or nothing when neither date is known. */
function dateText(startDate, endDate) {
  const start = longDate(startDate);
  const end = longDate(endDate);
  if (start && end) {
    return DATE_RANGE.replace('{0}', start).replace('{1}', end);
  }
  if (end) {
    return DATE_UNTIL.replace('{0}', end);
  }
  return start ? DATE_SINCE.replace('{0}', start) : null;
}

/**
 * The statuses a person may give an address from the card (R-AD10): any but the one it has,
 * Current again for an address whose end date has passed, and never Former on the primary.
 */
function statusActions(address, isFormer) {
  const actions = [];
  if (address.status !== STATUS_CURRENT || isFormer) {
    actions.push({ value: STATUS_CURRENT, label: MARK_CURRENT });
  }
  if (address.status !== STATUS_FORMER && !address.isDefault) {
    actions.push({ value: STATUS_FORMER, label: MARK_FORMER });
  }
  if (address.status !== STATUS_UNDELIVERABLE) {
    actions.push({ value: STATUS_UNDELIVERABLE, label: MARK_UNDELIVERABLE });
  }
  return actions;
}

/** The message an Apex refusal carries, or the card's own when it carries none. */
function messageOf(error) {
  return (error && error.body && error.body.message) || helpText('Core', 'Core_Address_MoveFailed');
}

/**
 * Every address a household, an organization, or a person has on file, with the one in use
 * badged, a way to move that badge, a form to add another, and the two household moves
 * (R-AD9) in each row's More menu: Move the Household Here on a person's own address, and
 * Give This Address to Members on a household's primary address.
 */
export default class AddressPanel extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded('Core');

  @wire(EnclosingTabId) enclosingTabId;

  // The card shows nothing while the Addresses feature is off (D-185).
  @wire(isFeatureOn) featureOn;

  get isShown() {
    return this.helpReady && Boolean(this.featureOn && this.featureOn.data);
  }

  icons = { address: iconFor('Address__c') };

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
  }

  @api recordId;
  @api objectApiName;

  labels = {
    panelTitle: PANEL_TITLE,
    addButton: ADD_BUTTON,
    addFormTitle: ADD_FORM_TITLE,
    cancelButton: CANCEL_BUTTON,
    defaultBadge: DEFAULT_BADGE,
    get emptyMessage() {
      return helpText('Core', 'Core_Address_Empty');
    },
    emptyHeading: EMPTY_HEADING,
    loading: LOADING,
    setDefaultButton: SET_DEFAULT_BUTTON,
    undeliverableBadge: UNDELIVERABLE_BADGE,
    get undeliverablePrimary() {
      return helpText('Core', 'Core_Address_UndeliverablePrimary');
    },
    moreMenu: MORE_MENU
  };

  addressObject = ADDRESS_OBJECT;
  formFields = FORM_FIELDS;
  isDefaultField = IS_DEFAULT_FIELD.fieldApiName;
  showForm = false;
  errorMessage;

  addresses = [];
  loaded = false;
  refreshAddresses;

  get queryVariables() {
    return this.recordId ? { ownerId: this.recordId } : undefined;
  }

  @wire(graphql, { query: ADDRESSES_QUERY, variables: '$queryVariables' })
  receiveAddresses(result) {
    this.refreshAddresses = result.refresh;
    if (result.errors && result.errors.length) {
      this.addresses = [];
      this.errorMessage = helpText('Core', 'Core_Address_LoadFailed');
      this.loaded = true;
    } else if (result.data) {
      const views = result.data.uiapi.query.Address__c.edges.map((edge) => toView(edge.node));
      // The address in use first, then newest first (a stable sort keeps the query's order).
      views.sort((a, b) => Number(b.isDefault) - Number(a.isDefault));
      this.addresses = views.map((address) => this.decorate(address));
      this.errorMessage = undefined;
      this.loaded = true;
    }
  }

  /** What the user may do with addresses; nothing is offered until it is known. */
  addressInfo;

  @wire(getObjectInfo, { objectApiName: ADDRESS_SCHEMA })
  receiveAddressInfo({ data }) {
    if (data) {
      this.addressInfo = data;
    }
  }

  /**
   * Whether this record is a household, and on a person the households they belong to, their
   * own first. No move is offered until it is known.
   */
  cardContext;

  @wire(getCardContext, { recordId: '$recordId' })
  receiveCardContext({ data }) {
    if (data) {
      this.cardContext = data;
    }
  }

  /** Add address, only for someone who can create addresses (Read Only cannot). */
  get canAdd() {
    return Boolean(this.addressInfo && this.addressInfo.createable);
  }

  /** Set as Primary writes Is Default (labelled Primary), so it needs edit on addresses and on that field. */
  get canSetDefault() {
    const info = this.addressInfo;
    const field = info && info.fields && info.fields[IS_DEFAULT_FIELD.fieldApiName];
    return Boolean(info && info.updateable && field && field.updateable);
  }

  get isLoading() {
    return !this.loaded;
  }

  get hasAddresses() {
    return this.addresses.length > 0;
  }

  get isEmpty() {
    return this.loaded && !this.hasAddresses && !this.errorMessage;
  }

  /**
   * The first address the record gets is the one in use (PEOPLE-49), so the form saves it as
   * the default. Only when the list was read and is empty: a failed read proves nothing.
   */
  get isFirstAddress() {
    return this.loaded && !this.errorMessage && !this.hasAddresses;
  }

  /** The lookup that ties a new address to the record the panel is sitting on. */
  get ownerFieldName() {
    return (this.objectApiName === 'Contact' ? CONTACT_FIELD : ACCOUNT_FIELD).fieldApiName;
  }

  /**
   * The addresses as the template draws them, with the moves this user may make on each.
   * The moves are added here rather than in decorate, because what the record is arrives on
   * its own wire, after or before the addresses.
   */
  get cards() {
    const context = this.cardContext;
    const canMove = this.canSetDefault && Boolean(context);
    const households = context && context.households ? context.households : [];
    const canSetStatus = this.canSetStatus;
    const canEdit = Boolean(this.addressInfo && this.addressInfo.updateable);
    const cardFields = this.cardFields;
    return this.addresses.map((address) => {
      const showUseForHousehold =
        canMove && address.isPersonal && !address.isSeasonal && households.length > 0;
      const showUpdateEveryone =
        canMove && context.isHousehold && !address.isPersonal && address.isDefault;
      // The row's More menu: Edit, the statuses, then the household move this row allows.
      const menuActions = [];
      if (canEdit) {
        menuActions.push({ value: EDIT, label: EDIT_ACTION });
      }
      if (canSetStatus) {
        menuActions.push(...address.statusActions);
      }
      if (showUseForHousehold) {
        menuActions.push({ value: MOVE_FOR_HOUSEHOLD, label: USE_FOR_HOUSEHOLD_BUTTON });
      }
      if (showUpdateEveryone) {
        menuActions.push({ value: MOVE_FOR_EVERYONE, label: UPDATE_EVERYONE_BUTTON });
      }
      return {
        ...address,
        showUseForHousehold,
        showUpdateEveryone,
        menuActions,
        showMoreMenu: menuActions.length > 0,
        cardFields,
        hasCardFields: cardFields.length > 0
      };
    });
  }

  /**
   * The card in two groups (R-AD10): the addresses in use now, primary first, then the Former
   * Addresses, collapsed until opened.
   */
  get groups() {
    const cards = this.cards;
    const former = cards.filter((card) => card.isFormer);
    const groups = [
      { key: 'current', dataId: 'current-addresses', cards: cards.filter((card) => !card.isFormer) }
    ];
    if (former.length) {
      groups.push({
        key: 'former',
        dataId: 'former-addresses',
        isFormer: true,
        heading: FORMER_HEADING.replace('{0}', former.length),
        expanded: String(this.formerOpen),
        icon: this.formerOpen ? 'utility:chevrondown' : 'utility:chevronright',
        cards: this.formerOpen ? former : []
      });
    }
    return groups;
  }

  formerOpen = false;

  handleToggleFormer() {
    this.formerOpen = !this.formerOpen;
  }

  /** The extra fields an administrator chose (Address Card Fields), those this user can read. */
  cardFields = [];

  @wire(getCardFields)
  receiveCardFields({ data }) {
    if (data) {
      this.cardFields = data;
    }
  }

  /** The status menu writes Status and End Date, so it needs edit on both. */
  get canSetStatus() {
    const info = this.addressInfo;
    const fields = (info && info.fields) || {};
    const status = fields[STATUS_FIELD.fieldApiName];
    const endDate = fields[END_DATE_FIELD.fieldApiName];
    return Boolean(
      info && info.updateable && status && status.updateable && endDate && endDate.updateable
    );
  }

  decorate(address) {
    const lines = [address.city, address.state, address.postalCode]
      .filter((part) => part)
      .join(' ');
    let seasonalText;
    if (address.isSeasonal && address.seasonalStart && address.seasonalEnd) {
      seasonalText = `${SEASONAL_RANGE} ${address.seasonalStart} ${SEASONAL_RANGE_TO} ${address.seasonalEnd}`;
    }
    // The primary is never in the Former group, whatever it says (R-AD10).
    const isFormer =
      !address.isDefault &&
      (address.status === STATUS_FORMER ||
        Boolean(address.endDate && address.endDate <= todayText()));
    const isUndeliverable = address.status === STATUS_UNDELIVERABLE;
    return {
      ...address,
      cityLine: lines,
      seasonalText,
      dateText: dateText(address.startDate, address.endDate),
      isFormer,
      isUndeliverable,
      flagUndeliverable: isUndeliverable && address.isDefault,
      statusActions: statusActions(address, isFormer),
      showSetDefault: !address.isDefault,
      headline: address.addressType || address.street || PANEL_TITLE,
      href: recordHref(address.id),
      rowClass: isFormer ? 'slds-item slds-theme_shade' : 'slds-item'
    };
  }

  /** A row's type opens the address; in a console, as a subtab beside the record. */
  handleOpenRecord(event) {
    const recordId = event.currentTarget.dataset.recordId;
    const pageReference = {
      type: 'standard__recordPage',
      attributes: { recordId, actionName: 'view' }
    };
    const navigate = () => this[NavigationMixin.Navigate](pageReference);
    if (followLinkInWorkspace(this, event, { recordId }, navigate) || opensElsewhere(event)) {
      return;
    }
    event.preventDefault();
    navigate();
  }

  /** A choice from a row's More menu: Edit, a status, or a household move. */
  handleMoreSelect(event) {
    const addressId = event.target.dataset.id;
    const value = event.detail.value;
    if (value === EDIT) {
      this[NavigationMixin.Navigate]({
        type: 'standard__recordPage',
        attributes: { recordId: addressId, objectApiName: ADDRESS_OBJECT, actionName: 'edit' }
      });
      return undefined;
    }
    if (value === MOVE_FOR_HOUSEHOLD) {
      return this.handleUseForHousehold(addressId);
    }
    if (value === MOVE_FOR_EVERYONE) {
      return this.handleUpdateEveryone();
    }
    return this.setStatus(addressId, value);
  }

  handleAdd() {
    this.showForm = true;
  }

  handleCancel() {
    this.showForm = false;
  }

  handleFormSuccess() {
    this.showForm = false;
    this.notify(helpText('Core', 'Core_Address_SaveSuccess'), 'success');
    this.refresh();
  }

  handleFormError() {
    this.errorMessage = helpText('Core', 'Core_Address_SaveFailed');
  }

  async handleSetDefault(event) {
    const addressId = event.target.dataset.id;
    try {
      // Clearing the old default and copying this one into the record's own address fields
      // is the trigger's work.
      await updateRecord({
        fields: { [ID_FIELD.fieldApiName]: addressId, [IS_DEFAULT_FIELD.fieldApiName]: true }
      });
      this.errorMessage = undefined;
      this.notify(helpText('Core', 'Core_Address_SetDefaultSuccess'), 'success');
      this.refresh();
    } catch {
      this.errorMessage = helpText('Core', 'Core_Address_SetDefaultFailed');
      this.notify(helpText('Core', 'Core_Address_SetDefaultFailed'), 'error');
    }
  }

  /**
   * A person's status choice (R-AD10). Former keeps the end date given, else today's; Current
   * clears it, so the address is back with the ones in use. Undeliverable changes nothing else.
   */
  async setStatus(addressId, status) {
    const address = this.addresses.find((candidate) => candidate.id === addressId);
    const fields = { [ID_FIELD.fieldApiName]: addressId, [STATUS_FIELD.fieldApiName]: status };
    if (status === STATUS_FORMER && !(address && address.endDate)) {
      fields[END_DATE_FIELD.fieldApiName] = todayText();
    } else if (status === STATUS_CURRENT) {
      fields[END_DATE_FIELD.fieldApiName] = null;
    }
    try {
      await updateRecord({ fields });
      this.errorMessage = undefined;
      this.notify(helpText('Core', 'Core_Address_StatusSaved'), 'success');
      this.refresh();
    } catch {
      this.errorMessage = helpText('Core', 'Core_Address_StatusFailed');
      this.notify(helpText('Core', 'Core_Address_StatusFailed'), 'error');
    }
  }

  // ------------------------------------------------------------ household moves (R-AD9)

  /** True while a move is being saved, so its buttons cannot start a second one. */
  moveBusy = false;

  /** The households a person belongs to, their own first, as choices for the confirmation. */
  get householdOptions() {
    const households = this.cardContext ? this.cardContext.households || [] : [];
    return households.map((household) => ({ label: household.name, value: household.id }));
  }

  /** Asks in the kit's confirm dialog, offering a choice only when there is more than one. */
  async handleUseForHousehold(addressId) {
    const options = this.householdOptions;
    const several = options.length > 1;
    const answer = await BarnConfirmModal.open({
      size: 'small',
      label: USE_FOR_HOUSEHOLD_TITLE,
      message: helpText('Core', 'Core_Address_UseForHouseholdHelp'),
      details: [helpText('Core', 'Core_Address_UseForHouseholdDetail')],
      choices: several ? options : undefined,
      choicesLabel: USE_FOR_HOUSEHOLD_PICK,
      choice: options.length ? options[0].value : undefined,
      confirmLabel: USE_FOR_HOUSEHOLD_BUTTON,
      cancelLabel: CANCEL_BUTTON
    });
    if (!answer || !options.length) {
      return;
    }
    const householdId = several ? answer.choice : options[0].value;
    await this.runMove(MOVE_FOR_HOUSEHOLD, { addressId, householdId });
  }

  /** Reads who would move, then lists them and offers a tick for each person with their own. */
  async handleUpdateEveryone() {
    let preview;
    try {
      preview = await getMovePreview({ householdId: this.recordId });
    } catch (error) {
      this.failMove(error);
      return;
    }
    const moving = preview.moving || [];
    const withTheirOwn = preview.withTheirOwn || [];
    const answer = await BarnConfirmModal.open({
      size: 'small',
      label: UPDATE_EVERYONE_TITLE,
      message: moving.length
        ? UPDATE_EVERYONE_MOVING
        : helpText('Core', 'Core_Address_UpdateEveryoneNobody'),
      items: moving.map((person) => person.name),
      checks: withTheirOwn.map((person) => ({ label: person.name, value: person.id })),
      checksLabel: helpText('Core', 'Core_Address_UpdateEveryoneOwn'),
      confirmLabel: UPDATE_EVERYONE_BUTTON,
      cancelLabel: CANCEL_BUTTON
    });
    if (!answer) {
      return;
    }
    const alsoMove = answer.checked || [];
    await this.runMove(MOVE_FOR_EVERYONE, { householdId: this.recordId, alsoMove });
  }

  async runMove(kind, params) {
    this.moveBusy = true;
    try {
      if (kind === MOVE_FOR_HOUSEHOLD) {
        await applyToWholeHousehold(params);
        this.notify(helpText('Core', 'Core_Address_UseForHouseholdSuccess'), 'success');
      } else {
        await updateEveryonesAddress(params);
        this.notify(helpText('Core', 'Core_Address_UpdateEveryoneSuccess'), 'success');
      }
      this.errorMessage = undefined;
      this.refresh();
    } catch (error) {
      this.failMove(error);
    }
    this.moveBusy = false;
  }

  failMove(error) {
    this.errorMessage = messageOf(error);
    this.notify(this.errorMessage, 'error');
  }

  /**
   * Reads the card again, and tells the record page its own address fields may have changed,
   * since a new or moved default is copied into them by the trigger.
   */
  refresh() {
    const reads = [notifyRecordUpdateAvailable([{ recordId: this.recordId }])];
    if (this.refreshAddresses) {
      reads.push(this.refreshAddresses());
    }
    return Promise.all(reads);
  }

  notify(message, variant) {
    Toast.show({ label: message, variant }, this);
  }
}
