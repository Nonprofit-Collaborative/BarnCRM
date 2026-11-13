import { dragInstructions, dragMessages } from 'c/barnDragText';
import { clearHelpTextForTest, setHelpTextForTest } from 'c/barnHelpText';

describe('c/barnDragText', () => {
  afterEach(() => clearHelpTextForTest());

  it('words each drag announcement from the Core help catalog, with its values', () => {
    setHelpTextForTest({
      Core_Drag_PickedUp: 'Picked up {0}.',
      Core_Drag_Position: '{0}: position {1} of {2}.',
      Core_Drag_Dropped: '{0} dropped in {1}.',
      Core_Drag_Cancelled: '{0} put back.'
    });
    const messages = dragMessages();
    expect(messages.pickedUp('Gift')).toBe('Picked up Gift.');
    expect(messages.position('To Do', 2, 5)).toBe('To Do: position 2 of 5.');
    expect(messages.dropped('Gift', 'Done')).toBe('Gift dropped in Done.');
    expect(messages.cancelled('Gift')).toBe('Gift put back.');
  });

  it('gives the keyboard instructions line', () => {
    expect(dragInstructions()).toBe('c.Core_Drag_Instructions');
  });
});
