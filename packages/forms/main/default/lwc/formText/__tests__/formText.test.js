import {
  LABELS,
  actionText,
  answerText,
  messageFrom,
  nestedKept,
  onMatchOptions,
  problemText,
  publicResultText,
  resultText,
  ruleOptions
} from 'c/formText';
import { clearHelpTextForTest, setHelpTextForTest } from 'c/barnHelpText';

describe('c/formText', () => {
  afterEach(() => clearHelpTextForTest());

  it('offers person matching by email first, and organization matching by name', () => {
    expect(ruleOptions('person').map((option) => option.value)).toEqual([
      'emailThenNamePostal',
      'email'
    ]);
    expect(ruleOptions('organization')).toEqual([
      { value: 'name', label: 'c.Forms_Builder_RuleName' }
    ]);
    expect(onMatchOptions().map((option) => option.value)).toEqual(['fillBlanks', 'overwrite']);
  });

  it('words a definition problem with its values, and an unknown one as the general failure', () => {
    setHelpTextForTest({ Forms_Problem_duplicateKey: 'Two questions use the key {0}.' });
    expect(problemText({ code: 'duplicateKey', args: ['email'] })).toBe(
      'Two questions use the key email.'
    );
    expect(problemText({ code: 'noSuchCode' })).toBe(LABELS.actionFailed);
    expect(problemText(null)).toBe(LABELS.actionFailed);
    expect(answerText(undefined)).toBe(LABELS.actionFailed);
    expect(nestedKept(3)).toBe('c.Forms_Builder_NestedKept');
  });

  it('shows the form confirmation when received, else the words for the status', () => {
    expect(publicResultText('Received', 'Thank you, Pat.')).toBe('Thank you, Pat.');
    expect(publicResultText('Received', '')).toBe('c.Forms_Public_Received');
    expect(publicResultText('Busy')).toBe('c.Forms_Public_Busy');
    expect(publicResultText('Unknown')).toBe('c.Forms_Public_Failed');
  });

  it('words what became of sent answers and of each record', () => {
    expect(resultText({ status: 'Processed' })).toBe('c.Forms_Runner_Processed');
    expect(resultText({ status: 'Held', message: 'Waiting for review.' })).toBe(
      'Waiting for review.'
    );
    expect(resultText(undefined)).toBe('c.Forms_Runner_Held');
    expect(actionText('created')).toBe('c.Forms_Written_created');
    expect(actionText('updated')).toBe('c.Forms_Written_updated');
    expect(actionText('matched')).toBe('c.Forms_Written_matched');
  });

  it('gives a failed call its own message, or the general one', () => {
    expect(messageFrom({ body: { message: 'Locked.' } })).toBe('Locked.');
    expect(messageFrom(new Error('x'))).toBe('c.Forms_Builder_ActionFailed');
  });
});
