import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import isFeatureOn from '@salesforce/apex/EngagementScoreController.isFeatureOn';
import CONTACT from '@salesforce/schema/Contact';
import SCORE from '@salesforce/schema/Contact.Engagement_Score__c';
import SCORED_ON from '@salesforce/schema/Contact.Engagement_Scored_On__c';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

/**
 * A person's engagement score as a meter, with the day it was set (C-64, canonical model
 * R-ES1). The score is worked out nightly in Apex (`EngagementScoreJob`); this only reads the
 * two fields, as optional fields so a person without access to them still gets the card. It
 * draws nothing while scoring is off, and says "Not scored yet" (help catalog text) while the
 * person has no score. The title and caption are the fields' own labels, so it adds no custom
 * label.
 */
export default class EngagementMeter extends LightningElement {
  @api recordId;

  helpReady = isHelpLoaded('Core');

  @wire(isFeatureOn) featureOn;

  @wire(getRecord, { recordId: '$recordId', optionalFields: [SCORE, SCORED_ON] }) person;

  @wire(getObjectInfo, { objectApiName: CONTACT }) contactInfo;

  get score() {
    return this.person && this.person.data ? getFieldValue(this.person.data, SCORE) : null;
  }

  get scoredOn() {
    return this.person && this.person.data ? getFieldValue(this.person.data, SCORED_ON) : null;
  }

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
  }

  get shown() {
    return Boolean(
      this.featureOn && this.featureOn.data === true && this.person && this.person.data
    );
  }

  get scored() {
    return this.score !== null && this.score !== undefined;
  }

  get notScoredText() {
    return helpText('Core', 'Core_EngagementMeter_NotScored');
  }

  get scoreText() {
    return String(this.score);
  }

  get title() {
    return this.labelOf(SCORE);
  }

  get scoredOnLabel() {
    return this.labelOf(SCORED_ON);
  }

  labelOf(field) {
    const fields = this.contactInfo && this.contactInfo.data && this.contactInfo.data.fields;
    const info = fields && fields[field.fieldApiName];
    return info ? info.label : '';
  }
}
