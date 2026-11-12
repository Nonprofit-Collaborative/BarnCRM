import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import isFeatureOn from '@salesforce/apex/EngagementScoreController.isFeatureOn';
import CONTACT from '@salesforce/schema/Contact';
import SCORE from '@salesforce/schema/Contact.Engagement_Score__c';
import SCORED_ON from '@salesforce/schema/Contact.Engagement_Scored_On__c';

/**
 * A person's engagement score as a meter, with the day it was set (C-64, canonical model
 * R-ES1). The score is worked out nightly in Apex (`EngagementScoreJob`); this only reads the
 * two fields. It draws nothing while scoring is off or the person has no score. The title and
 * caption are the fields' own labels and the explanation is help catalog text, so it adds no
 * custom label.
 */
export default class EngagementMeter extends LightningElement {
  @api recordId;

  @wire(isFeatureOn) featureOn;

  @wire(getRecord, { recordId: '$recordId', fields: [SCORE, SCORED_ON] }) person;

  @wire(getObjectInfo, { objectApiName: CONTACT }) contactInfo;

  get score() {
    return this.person && this.person.data ? getFieldValue(this.person.data, SCORE) : null;
  }

  get scoredOn() {
    return this.person && this.person.data ? getFieldValue(this.person.data, SCORED_ON) : null;
  }

  get shown() {
    return (
      Boolean(this.featureOn && this.featureOn.data === true) &&
      this.score !== null &&
      this.score !== undefined
    );
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
