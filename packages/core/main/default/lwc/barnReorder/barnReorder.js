/**
 * Reordering a list (v1.0 drag and drop rule): the list change itself, the keyboard moves and a
 * pointer drag from a handle, so a mouse, a finger and a pen all work. Framework free (plan 9.9):
 * it touches only standard DOM events and the elements the caller hands it.
 *
 * Drag and drop is always an extra. A list that uses this also shows Move Up and Move Down
 * buttons (labels Core_Shared_MoveUp, Core_Shared_MoveDown), and announces every move, from
 * either path, in its own aria-live region (help key Core_Kit_MovedToPosition).
 *
 * In a component:
 *   import { moveItem, startDrag } from 'c/barnReorder';
 *   handleDragStart(event) {
 *     startDrag(event, {
 *       from: Number(event.currentTarget.dataset.index),
 *       items: () => [...this.template.querySelectorAll('[data-reorder-item]')],
 *       onMove: (from, to) => { this.steps = moveItem(this.steps, from, to); }
 *     });
 *   }
 * with `onpointerdown={handleDragStart}` on a handle that has `touch-action: none` in its CSS.
 * While dragging, the dragged item carries `data-reorder-dragging` and the item under the
 * pointer `data-reorder-over`, for the caller's CSS.
 */

/** A copy of the list with the item at `from` moved to `to`; the list itself is not changed. */
export function moveItem(list, from, to) {
  const items = Array.isArray(list) ? list.slice() : [];
  if (!isIndex(from, items.length) || !isIndex(to, items.length) || from === to) {
    return items;
  }
  const [moved] = items.splice(from, 1);
  items.splice(to, 0, moved);
  return items;
}

/** The place an item at `index` moves to by `delta` (-1 up, 1 down), or -1 when it cannot. */
export function targetIndex(index, delta, length) {
  const to = index + delta;
  return isIndex(index, length) && isIndex(to, length) ? to : -1;
}

/**
 * The index of the item a pointer at `position` (clientY, or clientX for axis 'x') is over:
 * the first item whose middle is past the pointer, else the last. -1 for no items.
 */
export function indexAt(rects, position) {
  if (!rects || !rects.length) {
    return -1;
  }
  for (let index = 0; index < rects.length; index++) {
    const { start, end } = rects[index];
    if (position < (start + end) / 2) {
      return index;
    }
  }
  return rects.length - 1;
}

/**
 * Starts a pointer drag from a handle's pointerdown. Calls `onMove(from, to)` once on release
 * over another place, and nothing when released where it started or cancelled (Escape, or the
 * browser taking the pointer). Returns a function that cancels the drag.
 */
export function startDrag(event, { from, items, onMove, axis = 'y' }) {
  if (!event || (event.button !== undefined && event.button !== 0)) {
    return () => {};
  }
  const handle = event.currentTarget;
  const ownerDocument = (handle && handle.ownerDocument) || globalThis.document;
  let over = from;
  let done = false;

  const elements = () => (typeof items === 'function' ? items() : items) || [];
  const mark = () => {
    elements().forEach((element, index) => {
      toggle(element, 'data-reorder-dragging', index === from);
      toggle(element, 'data-reorder-over', index === over && index !== from);
    });
  };
  const finish = (move) => {
    if (done) {
      return;
    }
    done = true;
    handle.removeEventListener('pointermove', handleMove);
    handle.removeEventListener('pointerup', handleUp);
    handle.removeEventListener('pointercancel', handleCancel);
    if (ownerDocument) {
      ownerDocument.removeEventListener('keydown', handleKey, true);
    }
    elements().forEach((element) => {
      toggle(element, 'data-reorder-dragging', false);
      toggle(element, 'data-reorder-over', false);
    });
    if (move && over !== from && over >= 0) {
      onMove(from, over);
    }
  };
  function handleMove(moveEvent) {
    const rects = elements().map((element) => {
      const rect = element.getBoundingClientRect();
      return axis === 'x'
        ? { start: rect.left, end: rect.right }
        : { start: rect.top, end: rect.bottom };
    });
    const at = indexAt(rects, axis === 'x' ? moveEvent.clientX : moveEvent.clientY);
    if (at >= 0 && at !== over) {
      over = at;
      mark();
    }
    moveEvent.preventDefault();
  }
  function handleUp() {
    finish(true);
  }
  function handleCancel() {
    finish(false);
  }
  function handleKey(keyEvent) {
    if (keyEvent.key === 'Escape') {
      keyEvent.stopPropagation();
      finish(false);
    }
  }

  if (handle.setPointerCapture && event.pointerId !== undefined) {
    try {
      handle.setPointerCapture(event.pointerId);
    } catch {
      // A synthetic event has no active pointer; the listeners below still follow it.
    }
  }
  handle.addEventListener('pointermove', handleMove);
  handle.addEventListener('pointerup', handleUp);
  handle.addEventListener('pointercancel', handleCancel);
  if (ownerDocument) {
    ownerDocument.addEventListener('keydown', handleKey, true);
  }
  event.preventDefault();
  mark();
  return () => finish(false);
}

function isIndex(value, length) {
  return Number.isInteger(value) && value >= 0 && value < length;
}

function toggle(element, attribute, on) {
  if (!element || !element.setAttribute) {
    return;
  }
  if (on) {
    element.setAttribute(attribute, '');
  } else {
    element.removeAttribute(attribute);
  }
}
