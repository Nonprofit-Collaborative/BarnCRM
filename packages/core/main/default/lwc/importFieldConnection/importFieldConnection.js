import { LightningElement, api } from 'lwc';
import getConnection from '@salesforce/apex/ImportNewFieldController.getConnection';
import setUpConnection from '@salesforce/apex/ImportNewFieldController.setUpConnection';

import INTRO from '@salesforce/label/c.Core_ImportNewField_PanelIntro';
import STATUS from '@salesforce/label/c.Core_ImportNewField_PanelStatus';
import CONNECTED from '@salesforce/label/c.Core_ImportNewField_PanelConnected';
import NOT_CONNECTED from '@salesforce/label/c.Core_ImportNewField_PanelNotConnected';
import SET_UP from '@salesforce/label/c.Core_ImportNewField_SetUpButton';
import NEEDS_PERMISSION from '@salesforce/label/c.Core_ImportNewField_PanelNeedsPermission';
import CALLOUTS_OFF from '@salesforce/label/c.Core_ImportNewField_PanelCalloutsOff';
import ENABLE_STEPS from '@salesforce/label/c.Core_ImportNewField_PanelEnableSteps';
import CHECK_AGAIN from '@salesforce/label/c.Core_ImportNewField_CheckAgainButton';
import UNEXPECTED from '@salesforce/label/c.Core_UnexpectedError';

/**
 * The org connection that lets an import create a field (C-49d), on BarnCRM Settings, Import
 * page: its status and Set Up Connection. Only someone who may create fields can set it up.
 * Salesforce creates the Named Credential with callouts off, so until the admin turns on
 * Enabled for Callouts in Setup the panel shows the steps and Check Again (ADR-0148 A1).
 */
export default class ImportFieldConnection extends LightningElement {
  labels = {
    intro: INTRO,
    status: STATUS,
    setUp: SET_UP,
    needsPermission: NEEDS_PERMISSION,
    enableSteps: ENABLE_STEPS,
    checkAgain: CHECK_AGAIN
  };
  connection;
  busy = false;
  errorMessage;

  connectedCallback() {
    this.refresh();
  }

  /** Called by the settings console after a save or a reload. */
  @api
  async refresh() {
    this.errorMessage = undefined;
    try {
      this.connection = await getConnection();
    } catch (error) {
      this.errorMessage = this.errorText(error);
    }
  }

  get statusText() {
    if (this.connection && this.connection.connected) {
      return CONNECTED;
    }
    return this.calloutsOff ? CALLOUTS_OFF : NOT_CONNECTED;
  }

  get calloutsOff() {
    return Boolean(this.connection && this.connection.canCreate && this.connection.calloutsOff);
  }

  get canSetUp() {
    return Boolean(
      this.connection &&
      this.connection.canCreate &&
      !this.connection.connected &&
      !this.connection.calloutsOff
    );
  }

  async handleCheckAgain() {
    this.busy = true;
    await this.refresh();
    this.busy = false;
  }

  get needsPermission() {
    return Boolean(this.connection && !this.connection.canCreate);
  }

  async handleSetUp() {
    this.busy = true;
    this.errorMessage = undefined;
    try {
      this.connection = await setUpConnection();
    } catch (error) {
      this.errorMessage = this.errorText(error);
    } finally {
      this.busy = false;
    }
  }

  errorText(error) {
    return (error && error.body && error.body.message) || UNEXPECTED;
  }
}
