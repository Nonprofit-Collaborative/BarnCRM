import {
  DRAG_TEXT,
  arrowDragMessages,
  backwardMessage,
  messageFrom,
  stageLabel,
  starterLabel
} from 'c/logicModelText';
import { clearHelpTextForTest, setHelpTextForTest } from 'c/barnHelpText';

describe('c/logicModelText', () => {
  afterEach(() => clearHelpTextForTest());

  it('names a stage and a starter by key, and gives an unknown key back', () => {
    expect(stageLabel('Input')).toBe('c.LogicModels_Stage_Input');
    expect(stageLabel('Somewhere')).toBe('Somewhere');
    expect(starterLabel('peopleServed')).toBe('c.LogicModels_Starter_PeopleServed');
    expect(starterLabel('other')).toBe('other');
  });

  it('lists every arrow a column change would turn backward', () => {
    setHelpTextForTest({ LogicModels_Builder_BackwardArrows: 'Backward: {0}' });
    const message = backwardMessage([
      { fromName: 'Tutoring', toName: 'Grades' },
      { fromName: 'Meals', toName: 'Health' }
    ]);
    expect(message.startsWith('Backward: ')).toBe(true);
    expect(message.split('; ')).toHaveLength(2);
  });

  it('words the drag handles and the arrow announcements with their values', () => {
    setHelpTextForTest({
      LogicModels_Drag_MoveHandle: 'Move {0}',
      LogicModels_Drag_ArrowDropped: 'Arrow from {0} to {1}'
    });
    expect(DRAG_TEXT.moveHandle('Tutoring')).toBe('Move Tutoring');
    expect(DRAG_TEXT.hint()).toBe('c.LogicModels_Drag_Hint');
    const messages = arrowDragMessages();
    expect(messages.dropped('Tutoring', 'Grades')).toBe('Arrow from Tutoring to Grades');
    expect(messages.pickedUp('Tutoring')).toBe('c.LogicModels_Drag_ArrowPickedUp');
    expect(messages.position('Grades')).toBe('c.LogicModels_Drag_ArrowPosition');
    expect(messages.cancelled('Tutoring')).toBe('c.LogicModels_Drag_ArrowCancelled');
  });

  it('gives a failed call its own message, or the general one', () => {
    expect(messageFrom({ body: { message: 'Locked.' } })).toBe('Locked.');
    expect(messageFrom(undefined)).toBe('c.LogicModels_Builder_ActionFailed');
  });
});
