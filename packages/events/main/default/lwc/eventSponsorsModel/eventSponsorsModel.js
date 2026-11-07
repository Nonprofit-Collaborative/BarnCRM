/**
 * Sponsorship's shared arithmetic, with no framework in it (EV-09, canonical model 29EV22 to
 * 29EV24, plan Section 9.9): the badge word for a sponsor's status, how far a sponsor's
 * checklist has got, and what the sponsors have committed.
 *
 * Plain JavaScript in and out, so a WordPress block or Node can use the same module.
 */

const SPONSOR_WORDS = Object.freeze({
  Prospect: 'pending',
  Committed: 'in-progress',
  Confirmed: 'approved',
  Declined: 'rejected'
});

/** The statuses whose amounts count as money the event can expect. */
export const COUNTED_STATUSES = Object.freeze(['Committed', 'Confirmed']);

/** The badge word for a sponsor's status. */
export function sponsorWord(status) {
  return SPONSOR_WORDS[status] || 'neutral';
}

/** A checklist's progress as "done/total", empty when the sponsor has no deliverables. */
export function progressText(deliverables) {
  const items = deliverables || [];
  if (!items.length) {
    return '';
  }
  const done = items.filter((item) => item.status === 'Done').length;
  return `${done}/${items.length}`;
}

/** The amounts of Committed and Confirmed sponsors added together; blank amounts count as zero. */
export function committedTotal(sponsors) {
  return (sponsors || [])
    .filter((sponsor) => COUNTED_STATUSES.includes(sponsor.status))
    .reduce((sum, sponsor) => sum + (Number(sponsor.amount) || 0), 0);
}

/** A sponsor's linked Giving or Funders record as text, or empty when it cannot be named. */
export function linkedText(sponsor) {
  if (!sponsor || !sponsor.linkedLabel) {
    return '';
  }
  return sponsor.linkedKind ? `${sponsor.linkedKind}: ${sponsor.linkedLabel}` : sponsor.linkedLabel;
}
