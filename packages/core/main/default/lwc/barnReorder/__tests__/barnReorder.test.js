import { moveItem, targetIndex, indexAt, startDrag } from 'c/barnReorder';

function itemsAt(tops) {
  return tops.map((top) => {
    const element = document.createElement('div');
    element.getBoundingClientRect = () => ({ top, bottom: top + 40, left: top, right: top + 40 });
    document.body.appendChild(element);
    return element;
  });
}

function pointer(type, at) {
  const event = new CustomEvent(type, { bubbles: true, cancelable: true });
  event.clientY = at;
  event.clientX = at;
  event.button = 0;
  return event;
}

function down(handle) {
  const event = pointer('pointerdown', 0);
  Object.defineProperty(event, 'currentTarget', { value: handle });
  return event;
}

describe('c/barnReorder', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

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

  it('finds the item under the pointer by its middle', () => {
    const rects = [
      { start: 0, end: 40 },
      { start: 40, end: 80 },
      { start: 80, end: 120 }
    ];
    expect(indexAt(rects, 5)).toBe(0);
    expect(indexAt(rects, 50)).toBe(1);
    expect(indexAt(rects, 500)).toBe(2);
    expect(indexAt([], 5)).toBe(-1);
  });

  it('moves on release over another item and marks the items while dragging', () => {
    const items = itemsAt([0, 40, 80]);
    const handle = document.createElement('span');
    items[0].appendChild(handle);
    const onMove = jest.fn();

    startDrag(down(handle), { from: 0, items: () => items, onMove });
    expect(items[0].hasAttribute('data-reorder-dragging')).toBe(true);

    handle.dispatchEvent(pointer('pointermove', 100));
    expect(items[2].hasAttribute('data-reorder-over')).toBe(true);

    handle.dispatchEvent(pointer('pointerup', 100));
    expect(onMove).toHaveBeenCalledWith(0, 2);
    expect(items[0].hasAttribute('data-reorder-dragging')).toBe(false);
    expect(items[2].hasAttribute('data-reorder-over')).toBe(false);
  });

  it('works along a row of columns', () => {
    const items = itemsAt([0, 40, 80]);
    const handle = document.createElement('span');
    const onMove = jest.fn();
    startDrag(down(handle), { from: 2, items, onMove, axis: 'x' });
    handle.dispatchEvent(pointer('pointermove', 10));
    handle.dispatchEvent(pointer('pointerup', 10));
    expect(onMove).toHaveBeenCalledWith(2, 0);
  });

  it('does nothing when released where it started, cancelled or stopped with Escape', () => {
    const items = itemsAt([0, 40, 80]);
    const handle = document.createElement('span');
    const onMove = jest.fn();

    startDrag(down(handle), { from: 1, items, onMove });
    handle.dispatchEvent(pointer('pointerup', 50));

    startDrag(down(handle), { from: 1, items, onMove });
    handle.dispatchEvent(pointer('pointermove', 100));
    handle.dispatchEvent(pointer('pointercancel', 100));

    startDrag(down(handle), { from: 1, items, onMove });
    handle.dispatchEvent(pointer('pointermove', 100));
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    handle.dispatchEvent(pointer('pointerup', 100));

    expect(onMove).not.toHaveBeenCalled();
    expect(items[2].hasAttribute('data-reorder-over')).toBe(false);
  });

  it('ignores a right click', () => {
    const handle = document.createElement('span');
    const event = down(handle);
    event.button = 2;
    const onMove = jest.fn();
    startDrag(event, { from: 0, items: itemsAt([0, 40]), onMove });
    handle.dispatchEvent(pointer('pointermove', 60));
    handle.dispatchEvent(pointer('pointerup', 60));
    expect(onMove).not.toHaveBeenCalled();
  });
});
