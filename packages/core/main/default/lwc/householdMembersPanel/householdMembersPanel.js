import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { EnclosingTabId } from 'lightning/platformWorkspaceApi';
import HouseholdAddMemberModal from 'c/householdAddMemberModal';
import { iconFor } from 'c/barnIcons';
import { initialsOf, opensElsewhere, recordHref } from 'c/recordRows';
import { followLinkInWorkspace } from 'c/workspaceTabs';
import { refreshApex } from '@salesforce/apex';
import { getFieldValue, getRecord, updateRecord } from 'lightning/uiRecordApi';
import PRIMARY_CONTACT_FIELD from '@salesforce/schema/Account.Primary_Contact__c';
import { getObjectInfo, getObjectInfos } from 'lightning/uiObjectInfoApi';
import Toast from 'lightning/toast';
import CONTACT_SCHEMA from '@salesforce/schema/Contact';
import HOUSEHOLD_MEMBER_SCHEMA from '@salesforce/schema/Household_Member__c';
import getMembers from '@salesforce/apex/HouseholdController.getMembers';
import getMembershipMode from '@salesforce/apex/HouseholdController.getMembershipMode';
import moveContact from '@salesforce/apex/HouseholdController.moveContact';
import makePrimaryMembership from '@salesforce/apex/HouseholdOfPersonController.makePrimary';

import TITLE from '@salesforce/label/c.Core_HouseholdMembersPanel_Title';
import EMPTY_HEADING from '@salesforce/label/c.Core_HouseholdMembersPanel_EmptyHeading';
import ACTIONS_FOR from '@salesforce/label/c.Core_HouseholdMembersPanel_ActionsFor';
import PRIMARY from '@salesforce/label/c.Core_HouseholdMembersPanel_Primary';
import DECEASED from '@salesforce/label/c.Core_HouseholdMembersPanel_Deceased';
import ADD_MEMBER from '@salesforce/label/c.Core_HouseholdMembersPanel_AddMember';
import MOVE_MEMBER from '@salesforce/label/c.Core_HouseholdMembersPanel_MoveMember';
import SAVE from '@salesforce/label/c.Core_Kit_Save';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import MAKE_PRIMARY from '@salesforce/label/c.Core_HouseholdPanel_MakePrimary';
import LOADING from '@salesforce/label/c.Core_HouseholdPanel_Loading';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const RECORD_TYPE_FIELD = 'Account.RecordType.DeveloperName';
const HOUSEHOLD = 'Household';
const JUNCTION = 'Junction';
const SOURCE_ACCOUNT = 'Account';
const MAKE_PRIMARY_ACTION = 'makePrimary';

/** The move picker shows each household's city, so two households of one name differ. */
const HOUSEHOLD_DISPLAY_INFO = Object.freeze({
  primaryField: 'Name',
  additionalFields: ['BillingCity']
});

export default class HouseholdMembersPanel extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded('Core');

  @wire(EnclosingTabId) enclosingTabId;

  icons = { household: iconFor('Households') };

  householdDisplayInfo = HOUSEHOLD_DISPLAY_INFO;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
  }

  @api recordId;

  label = {
    title: TITLE,
    get empty() {
      return helpText('Core', 'Core_HouseholdMembersPanel_Empty');
    },
    emptyHeading: EMPTY_HEADING,
    get notAHousehold() {
      return helpText('Core', 'Core_HouseholdMembersPanel_NotAHousehold');
    },
    primary: PRIMARY,
    deceased: DECEASED,
    addMember: ADD_MEMBER,
    moveMember: MOVE_MEMBER,
    get moveHelp() {
      return helpText('Core', 'Core_HouseholdMembersPanel_MoveHelp');
    },
    save: SAVE,
    cancel: CANCEL,
    makePrimary: MAKE_PRIMARY,
    loading: LOADING
  };

  @track members = [];
  membershipMode;
  recordTypeName;
  householdRecordTypeId;
  primaryContactId;
  errorMessage;
  movingPersonId;
  targetHouseholdId;
  busy = false;
  membersLoaded = false;

  membersResult;

  @wire(getRecord, { recordId: '$recordId', fields: [RECORD_TYPE_FIELD, PRIMARY_CONTACT_FIELD] })
  wiredAccount({ data, error }) {
    if (data) {
      const recordType = data.fields.RecordType;
      this.recordTypeName =
        recordType && recordType.value ? recordType.value.fields.DeveloperName.value : undefined;
      // In the simple way of belonging the primary contact is the household's own field, which
      // the server does not put on a member, so the badge is worked out here.
      this.primaryContactId = getFieldValue(data, PRIMARY_CONTACT_FIELD) || undefined;
    } else if (error) {
      this.errorMessage = this.readError(error);
    }
  }

  @wire(getObjectInfo, { objectApiName: 'Account' })
  wiredAccountInfo({ data, error }) {
    if (data) {
      // Which record type is the household one, so that the move offers households and
      // never an organization.
      const infos = data.recordTypeInfos || {};
      this.householdRecordTypeId = Object.keys(infos).find(
        (id) => infos[id].developerName === HOUSEHOLD || infos[id].name === HOUSEHOLD
      );
      this.accountUpdateable = data.updateable === true;
    } else if (error) {
      this.errorMessage = this.readError(error);
    }
  }

  // What the user may do with people and memberships; nothing is offered until it is known,
  // so a Read Only user never sees Add member, Move or Make primary (they could only fail).
  accountUpdateable = false;
  contactAccess = {};
  membershipAccess = {};

  @wire(getObjectInfos, { objectApiNames: [CONTACT_SCHEMA, HOUSEHOLD_MEMBER_SCHEMA] })
  wiredAccessInfos({ data }) {
    if (data && data.results) {
      const [contact, membership] = data.results.map((entry) => {
        return entry && entry.statusCode === 200 && entry.result ? entry.result : {};
      });
      this.contactAccess = contact || {};
      this.membershipAccess = membership || {};
    }
  }

  /**
   * In the flexible membership mode every member action writes a membership record; in the
   * simple mode adding creates a contact, moving edits the contact and making primary edits
   * the household.
   */
  get canCreateMember() {
    return this.isJunctionMode
      ? this.membershipAccess.createable === true
      : this.contactAccess.createable === true;
  }

  get canMoveMembers() {
    if (this.isJunctionMode) {
      return this.membershipAccess.updateable === true;
    }
    // Moving a person in the simple mode changes their Account Name (AccountId), so the user
    // needs edit access to that field as well as to contacts.
    const accountField = this.contactAccess.fields && this.contactAccess.fields.AccountId;
    return this.contactAccess.updateable === true && accountField?.updateable === true;
  }

  get canChangePrimary() {
    return this.isJunctionMode ? this.membershipAccess.updateable === true : this.accountUpdateable;
  }

  @wire(getMembershipMode)
  wiredMode({ data, error }) {
    if (data) {
      this.membershipMode = data;
    } else if (error) {
      this.errorMessage = this.readError(error);
    }
  }

  @wire(getMembers, { householdId: '$recordId' })
  wiredMembers(result) {
    this.membersResult = result;
    if (result.data) {
      this.members = result.data;
      this.errorMessage = undefined;
      this.membersLoaded = true;
    } else if (result.error) {
      this.members = [];
      this.errorMessage = this.readError(result.error);
      this.membersLoaded = true;
    }
  }

  get isHousehold() {
    return this.recordTypeName === HOUSEHOLD;
  }

  get isJunctionMode() {
    return this.membershipMode === JUNCTION;
  }

  get canAddMember() {
    return this.isHousehold && this.canCreateMember;
  }

  get hasMembers() {
    return this.members.length > 0;
  }

  get isLoading() {
    return this.busy || !this.membersLoaded;
  }

  /**
   * The members as the tiles draw them: initials, who is primary, which actions each tile's
   * menu offers, and what a screen reader hears for the menu. Worked out on the way to the
   * screen because the primary contact and the way of belonging arrive from wires of their own.
   */
  get rows() {
    return this.members.map((member) => {
      const isPrimary = this.isPrimary(member);
      const storedAsAccount = member.source === SOURCE_ACCOUNT;
      // A person stored as an account can only be moved, or named primary, where their
      // membership is a record of its own. Offering the action elsewhere only lets the
      // user choose it and be refused.
      const canMove = this.canMoveMembers && (this.isJunctionMode || !storedAsAccount);
      const canMakePrimary =
        this.canChangePrimary && !isPrimary && (this.isJunctionMode || !storedAsAccount);
      return {
        ...member,
        isPrimary,
        initials: initialsOf(member.name),
        href: recordHref(member.personId),
        badges: this.badgesFor(member, isPrimary),
        canMove,
        canMakePrimary,
        hasActions: canMove || canMakePrimary,
        actionsLabel: ACTIONS_FOR.replace('{0}', member.name)
      };
    });
  }

  isPrimary(member) {
    if (this.isJunctionMode) {
      return member.isPrimary === true;
    }
    return !!this.primaryContactId && member.personId === this.primaryContactId;
  }

  get isMoving() {
    return !!this.movingPersonId;
  }

  /**
   * The move offers households only. Until the record type is known nothing is offered,
   * which is better than offering every account in the org.
   */
  get householdFilter() {
    return {
      criteria: [
        {
          fieldPath: 'RecordTypeId',
          operator: 'eq',
          value: this.householdRecordTypeId || ''
        }
      ]
    };
  }

  badgesFor(member, isPrimary) {
    const badges = [];
    if (isPrimary) {
      badges.push({
        key: `${member.personId}-primary`,
        text: PRIMARY,
        status: 'success',
        iconName: 'utility:favorite'
      });
    }
    if (member.isDeceased) {
      badges.push({ key: `${member.personId}-deceased`, text: DECEASED, status: 'neutral' });
    }
    return badges;
  }

  /** A member's name opens their record; in a console, as a subtab beside the household. */
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

  /** Add Member opens its own dialog; the list refreshes once someone was added. */
  async handleAddClick() {
    const added = await HouseholdAddMemberModal.open({
      label: ADD_MEMBER,
      size: 'small',
      householdId: this.recordId,
      junctionMode: this.isJunctionMode
    });
    if (!added) {
      return undefined;
    }
    this.errorMessage = undefined;
    this.toast(helpText('Core', 'Core_HouseholdMembersPanel_AddSuccess'), 'success');
    return this.refresh();
  }

  /** A choice from a member's menu: Make Primary, or Move to Another Household. */
  handleMemberAction(event) {
    const personId = event.target.dataset.personId;
    if (event.detail.value === MAKE_PRIMARY_ACTION) {
      return this.makePrimary(personId);
    }
    this.movingPersonId = personId;
    this.targetHouseholdId = undefined;
    return undefined;
  }

  handleMoveCancel() {
    this.movingPersonId = undefined;
    this.targetHouseholdId = undefined;
  }

  handleTargetChange(event) {
    const detail = event.detail || {};
    const value = detail.recordId === undefined ? detail.value : detail.recordId;
    this.targetHouseholdId = Array.isArray(value) ? value[0] : value;
  }

  handleMoveSave() {
    const personId = this.movingPersonId;
    const targetId = this.targetHouseholdId;
    this.busy = true;
    return moveContact({
      contactId: personId,
      targetHouseholdId: targetId,
      sourceHouseholdId: this.recordId
    })
      .then(() => {
        this.movingPersonId = undefined;
        this.targetHouseholdId = undefined;
        this.errorMessage = undefined;
        this.toast(helpText('Core', 'Core_HouseholdMembersPanel_MoveSuccess'), 'success');
        return this.refresh();
      })
      .catch((error) => {
        this.errorMessage = this.readError(error);
      })
      .finally(() => {
        this.busy = false;
      });
  }

  /**
   * In the simple way of belonging the primary contact is a field on the household, written
   * through the platform so that the user's own access decides whether it is allowed. In the
   * flexible way it is a mark on the membership record, which the server moves.
   */
  makePrimary(personId) {
    const member = this.members.find((row) => row.personId === personId);
    const name = member ? member.name : '';
    this.busy = true;
    const write = this.isJunctionMode
      ? makePrimaryMembership({ householdId: this.recordId, personId })
      : updateRecord({ fields: { Id: this.recordId, Primary_Contact__c: personId } });
    return write
      .then(() => {
        this.errorMessage = undefined;
        this.toast(
          helpText('Core', 'Core_HouseholdPanel_MakePrimarySuccess').replace('{0}', name),
          'success'
        );
        return this.refresh();
      })
      .catch((error) => {
        this.errorMessage = this.isJunctionMode
          ? this.readError(error)
          : helpText('Core', 'Core_HouseholdPanel_MakePrimaryFailed');
      })
      .finally(() => {
        this.busy = false;
      });
  }

  refresh() {
    return refreshApex(this.membersResult);
  }

  toast(message, variant) {
    Toast.show({ label: message, variant }, this);
  }

  readError(error) {
    if (!error) {
      return undefined;
    }
    if (error.body && error.body.message) {
      return error.body.message;
    }
    return error.message;
  }
}
