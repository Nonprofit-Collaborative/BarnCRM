import { helpText } from 'c/barnHelpText';

/**
 * The words c/barnDrag announces, from the Core help catalog (messages never go in labels).
 * Call after loadHelp([...your package..., 'Core']) has resolved:
 *
 *   createDragController({ messages: dragMessages(), ... })
 *   get dragInstructions() { return dragInstructions(); }   // aria-describedby text on items
 */
export function dragMessages() {
  return {
    pickedUp: (name) => helpText('Core', 'Core_Drag_PickedUp', name),
    position: (zone, position, count) =>
      helpText('Core', 'Core_Drag_Position', zone, position, count),
    dropped: (name, zone) => helpText('Core', 'Core_Drag_Dropped', name, zone),
    cancelled: (name) => helpText('Core', 'Core_Drag_Cancelled', name)
  };
}

/** One line for each draggable item's aria-describedby: how to move it by keyboard. */
export function dragInstructions() {
  return helpText('Core', 'Core_Drag_Instructions');
}
