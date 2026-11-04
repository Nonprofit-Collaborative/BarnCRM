import { createDragController, formatDragMessage, moveItem, targetIndex } from 'c/barnDrag';
import { dragMessages, dragInstructions } from 'c/barnDragText';

// A board of two columns, each 100px wide; items are 20px tall, stacked from the top.
function buildBoard() {
  const root = document.createElement('div');
  const columns = [
    { id: 'applied', label: 'Applied', items: ['a', 'b'] },
    { id: 'awarded', label: 'Awarded', items: ['c'] }
  ];
  columns.forEach((column, c) => {
    const zone = document.createElement('div');
    zone.dataset.dropZone = column.id;
    zone.dataset.dropLabel = column.label;
    zone.getBoundingClientRect = () => ({
      left: c * 100,
      right: c * 100 + 99,
      top: 0,
      bottom: 200,
      width: 99,
      height: 200
    });
    column.items.forEach((id, i) => {
      const item = document.createElement('div');
      item.dataset.dragId = id;
      item.dataset.dragLabel = 'Grant ' + id.toUpperCase();
      item.tabIndex = 0;
      item.getBoundingClientRect = () => ({
        left: c * 100,
        right: c * 100 + 99,
        top: i * 20,
        bottom: i * 20 + 20,
        width: 99,
        height: 20
      });
      zone.appendChild(item);
    });
    root.appendChild(zone);
  });
  document.body.appendChild(root);
  return root;
}

const MESSAGES = {
  pickedUp: 'Picked up {0}.',
  position: '{0}, position {1} of {2}.',
  dropped: 'Moved {0} to {1}.',
  cancelled: 'Move cancelled. {0} is back.'
};

function itemOf(root, id) {
  return root.querySelector(`[data-drag-id="${id}"]`);
}

function key(target, keyName) {
  return {
    key: keyName,
    target,
    currentTarget: target,
    preventDefault: jest.fn(),
    stopPropagation: jest.fn()
  };
}

function pointer(type, x, y, extra = {}) {
  const event = new CustomEvent(type, { bubbles: true, cancelable: true });
  Object.assign(event, { clientX: x, clientY: y, pointerType: 'mouse', button: 0 }, extra);
  return event;
}

describe('c/barnDrag', () => {
  let root;
  let announced;
  let drops;
  let controller;

  function make(extra = {}) {
    announced = [];
    drops = [];
    controller = createDragController({
      root,
      messages: MESSAGES,
      announce: (text) => announced.push(text),
      onDrop: (drop) => {
        drops.push(drop);
        return extra.result;
      },
      canDrop: extra.canDrop
    });
  }

  beforeEach(() => {
    root = buildBoard();
  });

  afterEach(() => {
    if (controller) {
      controller.destroy();
      controller = undefined;
    }
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.useRealTimers();
  });

  it('formats {0} placeholders and leaves missing ones empty', () => {
    expect(formatDragMessage('Moved {0} to {1}.', ['A'])).toBe('Moved A to .');
  });

  it('moves an item to another column by keyboard and announces each step', async () => {
    make();
    const a = itemOf(root, 'a');
    controller.keyDown(key(a, ' '));
    expect(announced[0]).toBe('Picked up Grant A.');
    expect(controller.state.active).toBe(true);
    controller.keyDown(key(a, 'ArrowRight'));
    expect(announced[1]).toBe('Awarded, position 1 of 2.');
    controller.keyDown(key(a, 'ArrowDown'));
    expect(announced[2]).toBe('Awarded, position 2 of 2.');
    controller.keyDown(key(a, ' '));
    await Promise.resolve();
    await Promise.resolve();
    expect(drops).toEqual([
      { itemId: 'a', fromZone: 'applied', fromIndex: 0, toZone: 'awarded', toIndex: 1 }
    ]);
    expect(announced[3]).toBe('Moved Grant A to Awarded.');
    expect(controller.state.active).toBe(false);
  });

  it('reorders within a column and stops at the ends', () => {
    make();
    const a = itemOf(root, 'a');
    controller.keyDown(key(a, ' '));
    controller.keyDown(key(a, 'ArrowUp'));
    expect(controller.state.overIndex).toBe(0);
    controller.keyDown(key(a, 'ArrowDown'));
    controller.keyDown(key(a, 'ArrowDown'));
    expect(controller.state.overIndex).toBe(1);
  });

  it('cancels with Escape and reports nothing moved', () => {
    make();
    const a = itemOf(root, 'a');
    controller.keyDown(key(a, ' '));
    controller.keyDown(key(a, 'ArrowRight'));
    controller.keyDown(key(a, 'Escape'));
    expect(drops).toEqual([]);
    expect(announced[announced.length - 1]).toBe('Move cancelled. Grant A is back.');
  });

  it('dropping where it started is not a move', async () => {
    make();
    const a = itemOf(root, 'a');
    controller.keyDown(key(a, ' '));
    controller.keyDown(key(a, 'Enter'));
    await Promise.resolve();
    expect(drops).toEqual([]);
  });

  it('skips a zone the caller refuses, and snaps back when the drop is refused', async () => {
    make({ canDrop: (id, from, to) => to !== 'awarded' });
    const a = itemOf(root, 'a');
    controller.keyDown(key(a, ' '));
    controller.keyDown(key(a, 'ArrowRight'));
    expect(controller.state.overZone).toBe('applied');
    controller.destroy();

    make({ result: false });
    controller.keyDown(key(a, ' '));
    controller.keyDown(key(a, 'ArrowRight'));
    controller.keyDown(key(a, ' '));
    await Promise.resolve();
    await Promise.resolve();
    expect(drops.length).toBe(1);
    expect(announced[announced.length - 1]).toBe('Move cancelled. Grant A is back.');
  });

  it('leaves Space alone on a button inside the item', () => {
    make();
    const a = itemOf(root, 'a');
    const button = document.createElement('button');
    a.appendChild(button);
    controller.keyDown({ key: ' ', target: button, currentTarget: a, preventDefault: jest.fn() });
    expect(controller.state.active).toBe(false);
  });

  it('drags with a mouse into the other column, under its first card', async () => {
    make();
    const a = itemOf(root, 'a');
    controller.pointerDown({
      currentTarget: a,
      clientX: 10,
      clientY: 5,
      pointerType: 'mouse',
      button: 0
    });
    window.dispatchEvent(pointer('pointermove', 12, 6));
    expect(controller.state.active).toBe(false); // under the slop
    window.dispatchEvent(pointer('pointermove', 150, 25));
    expect(controller.state.overZone).toBe('awarded');
    expect(controller.state.overIndex).toBe(1);
    window.dispatchEvent(pointer('pointerup', 150, 25));
    await Promise.resolve();
    await Promise.resolve();
    expect(drops[0]).toEqual({
      itemId: 'a',
      fromZone: 'applied',
      fromIndex: 0,
      toZone: 'awarded',
      toIndex: 1
    });
  });

  it('a mouse click without movement is not a drag', () => {
    make();
    const a = itemOf(root, 'a');
    controller.pointerDown({
      currentTarget: a,
      clientX: 10,
      clientY: 5,
      pointerType: 'mouse',
      button: 0
    });
    window.dispatchEvent(pointer('pointerup', 10, 5));
    expect(controller.state.active).toBe(false);
    expect(drops).toEqual([]);
  });

  it('starts a touch drag only after a press and hold; a swipe scrolls instead', () => {
    jest.useFakeTimers();
    make();
    const a = itemOf(root, 'a');
    controller.pointerDown({ currentTarget: a, clientX: 10, clientY: 5, pointerType: 'touch' });
    window.dispatchEvent(pointer('pointermove', 10, 40, { pointerType: 'touch' }));
    jest.advanceTimersByTime(300);
    expect(controller.state.active).toBe(false);

    controller.pointerDown({ currentTarget: a, clientX: 10, clientY: 5, pointerType: 'touch' });
    jest.advanceTimersByTime(300);
    expect(controller.state.active).toBe(true);
    expect(controller.state.mode).toBe('pointer');
    window.dispatchEvent(pointer('pointercancel', 10, 5));
    expect(controller.state.active).toBe(false);
  });

  it('reads its words from the Core help catalog', () => {
    expect(dragInstructions()).toBe('c.Core_Drag_Instructions');
    const words = dragMessages();
    expect(words.dropped('Grant A', 'Awarded')).toBe('c.Core_Drag_Dropped');
    expect(typeof words.pickedUp).toBe('function');
    expect(typeof words.position).toBe('function');
    expect(typeof words.cancelled).toBe('function');
  });
});

describe('c/barnDrag list helpers', () => {
  it('moves an item to a new place without changing the list given', () => {
    const list = ['a', 'b', 'c', 'd'];
    expect(moveItem(list, 0, 2)).toEqual(['b', 'c', 'a', 'd']);
    expect(moveItem(list, 3, 0)).toEqual(['d', 'a', 'b', 'c']);
    expect(list).toEqual(['a', 'b', 'c', 'd']);
  });

  it('leaves the list as it is for a place outside it', () => {
    expect(moveItem(['a', 'b'], 0, 5)).toEqual(['a', 'b']);
    expect(moveItem(['a', 'b'], -1, 0)).toEqual(['a', 'b']);
    expect(moveItem(null, 0, 1)).toEqual([]);
  });

  it('knows when Move Up or Move Down has nowhere to go', () => {
    expect(targetIndex(0, -1, 3)).toBe(-1);
    expect(targetIndex(2, 1, 3)).toBe(-1);
    expect(targetIndex(1, 1, 3)).toBe(2);
  });
});
