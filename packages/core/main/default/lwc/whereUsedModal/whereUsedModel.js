/**
 * Where Used's browser-side logic (C-59), kept free of framework imports so any front end can
 * reuse it (plan Section 9.9): the Apex service finds the references and returns plain JSON; this
 * groups them for display and lays out the Retire a Field checklist.
 */

/**
 * The references grouped by their kind, in the order the server sorted them (kind, then name).
 * Each item carries its parts joined for display.
 */
export function groupReferences(references) {
  const groups = [];
  const byKind = new Map();
  (references || []).forEach((reference, index) => {
    const label = reference.kindLabel || reference.kind || '';
    let group = byKind.get(label);
    if (!group) {
      group = { key: `${reference.kind}|${label}`, label, items: [] };
      byKind.set(label, group);
      groups.push(group);
    }
    group.items.push({
      key: `${reference.kind}|${reference.recordId || reference.name}|${index}`,
      name: reference.name,
      url: reference.editUrl || null,
      parts: (reference.parts || []).join(', '),
      breaks: reference.breaks || ''
    });
  });
  return groups;
}

/**
 * The Retire a Field steps for one result, each with a key, the link it offers ("setup", "find"
 * or none) and whether it is a step to do or a note. Deleting is offered only for a field the
 * org can delete; otherwise the last step says to keep the field hidden.
 */
export function retireSteps(result) {
  const hasReferences = !!(result && result.references && result.references.length);
  return [
    { key: hasReferences ? 'references' : 'noReferences', link: null },
    { key: 'salesforce', link: 'setup' },
    { key: 'backup', link: 'find' },
    { key: 'hide', link: null },
    {
      key: result && result.deletable ? 'delete' : 'cannotDelete',
      link: result && result.deletable ? 'setup' : null
    }
  ];
}

/** How many of the steps are ticked. */
export function doneCount(steps, done) {
  const ticked = done || new Set();
  return (steps || []).filter((step) => ticked.has(step.key)).length;
}
