import { LightningElement, api } from 'lwc';
import getReview from '@salesforce/apex/ScholarshipsController.getReview';
import saveReview from '@salesforce/apex/ScholarshipsController.saveReview';
import { messageFrom } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { weightedTotal } from 'c/scholarshipsModel';

const PKG = 'Scholarships';

// What each action says when it has worked.
function notices() {
  return {
    Scholarships_Review_Saved: helpText('Scholarships', 'Scholarships_Review_Saved'),
    Scholarships_Review_Submitted: helpText('Scholarships', 'Scholarships_Review_Submitted'),
    Scholarships_Review_Recused: helpText('Scholarships', 'Scholarships_Review_Recused')
  };
}

/**
 * The review panel on an application (SG-03): the cycle's rubric with a score for each
 * criterion and the weighted total as the reviewer types, comments, Save, Submit Review and
 * Recuse with a reason. Apex recomputes the score on save (R-SG6).
 */
export default class ApplicationReview extends LightningElement {
  @api recordId;
  helpReady = isHelpLoaded([PKG]);
  review;
  scores = {};
  comments;
  reason;
  recusing = false;
  isWorking = false;
  errorMessage;
  notice;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp([PKG]).then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  get labels() {
    return {
      title: helpText('Scholarships', 'Scholarships_Review_Title'),
      comments: helpText('Scholarships', 'Scholarships_Review_Comments'),
      save: helpText('Scholarships', 'Scholarships_Save'),
      submit: helpText('Scholarships', 'Scholarships_Review_Submit'),
      recuse: helpText('Scholarships', 'Scholarships_Review_Recuse'),
      reason: helpText('Scholarships', 'Scholarships_Review_Reason'),
      cancel: helpText('Scholarships', 'Scholarships_Cancel'),
      total: helpText('Scholarships', 'Scholarships_Review_Total'),
      closed: helpText('Scholarships', 'Scholarships_Review_Closed'),
      blind: helpText('Scholarships', 'Scholarships_Review_BlindNote')
    };
  }

  get criteria() {
    return (this.review?.criteria || []).map((c) => ({
      ...c,
      value: this.scores[c.key],
      fieldLabel: helpText(
        'Scholarships',
        'Scholarships_Review_Criterion',
        c.label,
        c.max,
        c.weight
      )
    }));
  }

  get total() {
    return weightedTotal(this.review?.criteria, this.scores);
  }

  get status() {
    return this.review?.mine?.status;
  }

  get isOpen() {
    return this.review?.open === true && this.status !== 'Recused';
  }

  get isBlind() {
    return this.review?.blind === true;
  }

  async load() {
    try {
      this.review = await getReview({ applicationId: this.recordId });
      const mine = this.review.mine;
      this.scores = mine?.scores ? JSON.parse(mine.scores) : {};
      this.comments = mine?.comments;
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  handleScore(event) {
    this.scores = { ...this.scores, [event.target.dataset.key]: event.target.value };
  }

  handleComments(event) {
    this.comments = event.target.value;
  }

  handleReason(event) {
    this.reason = event.target.value;
  }

  handleStartRecuse() {
    this.recusing = true;
  }

  handleCancelRecuse() {
    this.recusing = false;
  }

  handleSave() {
    this.send('save', 'Scholarships_Review_Saved');
  }

  handleSubmit() {
    this.send('submit', 'Scholarships_Review_Submitted');
  }

  handleRecuse() {
    this.send('recuse', 'Scholarships_Review_Recused');
  }

  async send(action, noticeKey) {
    this.isWorking = true;
    try {
      await saveReview({
        applicationId: this.recordId,
        scoresJson: JSON.stringify(this.scores),
        comments: this.comments,
        action,
        reason: this.reason
      });
      this.notice = notices()[noticeKey];
      this.errorMessage = undefined;
      this.recusing = false;
      await this.load();
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.isWorking = false;
    }
  }
}
