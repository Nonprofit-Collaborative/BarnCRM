/**
 * The Service Plan panel's logic, framework free (plan Section 9.9): it orders and labels the
 * plain plan the server returns, works out which goals are due for review, offers the next review
 * date, and builds what to save. No Lightning or Salesforce import, so it runs and is tested
 * anywhere (a WordPress block, Node).
 */
import { format } from 'c/barnFormat';

/** How far ahead Mark Reviewed offers the next review (R-GL3); the user changes it each time. */
export const REVIEW_MONTHS = 3;
const DONE = 'Done';
const NOT_STARTED = 'Not Started';

/**
 * The status word (the suite's status vocabulary, c/barnStatus) for a goal's stored status:
 * Achieved is done, In Progress is under way, and Not Started and Not Achieved stay neutral.
 */
export function goalStatusWord(status) {
  if (status === 'Achieved') {
    return 'achieved';
  }
  if (status === 'In Progress') {
    return 'in-progress';
  }
  return 'neutral';
}

/** Replaces {0}, {1} and so on in a label with the values given (shared, UTIL-01). */
export { format };

/** Today as YYYY-MM-DD in the given time zone (the user's, not the browser's). */
export function todayIn(timeZone, now = new Date()) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: timeZone || 'UTC',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit'
  }).formatToParts(now);
  const part = (type) => parts.find((p) => p.type === type).value;
  return `${part('year')}-${part('month')}-${part('day')}`;
}

/** The date `months` after an ISO date, kept within the month (31 Jan plus 1 is 28 or 29 Feb). */
export function addMonths(isoDate, months) {
  const [year, month, day] = isoDate.split('-').map(Number);
  const target = new Date(Date.UTC(year, month - 1 + months, 1));
  const lastDay = new Date(
    Date.UTC(target.getUTCFullYear(), target.getUTCMonth() + 1, 0)
  ).getUTCDate();
  target.setUTCDate(Math.min(day, lastDay));
  return target.toISOString().slice(0, 10);
}

/** An ISO date shown in the user's locale, or '' for none. */
export function formatDate(isoDate, locale) {
  if (!isoDate) {
    return '';
  }
  const [year, month, day] = String(isoDate).slice(0, 10).split('-').map(Number);
  return new Intl.DateTimeFormat(locale || 'en-US', {
    timeZone: 'UTC',
    year: 'numeric',
    month: 'short',
    day: 'numeric'
  }).format(new Date(Date.UTC(year, month - 1, day)));
}

/** Whether an open goal's next review is before today (R-GL3). ISO dates compare as text. */
export function isReviewDue(goal, today) {
  return !!(goal && !goal.closed && goal.nextReviewDate && goal.nextReviewDate < today);
}

/** Open goals first; then by target date, undated last; then by name. */
export function sortGoals(goals) {
  return [...(goals || [])].sort((a, b) => {
    if (!!a.closed !== !!b.closed) {
      return a.closed ? 1 : -1;
    }
    if ((a.targetDate || '') !== (b.targetDate || '')) {
      if (!a.targetDate) {
        return 1;
      }
      if (!b.targetDate) {
        return -1;
      }
      return a.targetDate < b.targetDate ? -1 : 1;
    }
    return (a.name || '').localeCompare(b.name || '');
  });
}

/** The label of a picklist value, or the value itself. */
function labelOf(options, value) {
  const found = (options || []).find((option) => option.value === value);
  return found ? found.label : value;
}

/**
 * The goals as the panel shows them: ordered, with their dates, review flag, progress and steps
 * written out in the labels given.
 */
export function goalCards(plan, today, labels, locale) {
  if (!plan) {
    return [];
  }
  return sortGoals(plan.goals).map((goal) => {
    const steps = goal.steps || [];
    const done = steps.filter((step) => step.status === DONE).length;
    const facts = [];
    if (goal.targetDate) {
      facts.push(format(labels.target, formatDate(goal.targetDate, locale)));
    }
    if (goal.assignedToName) {
      facts.push(format(labels.assigned, goal.assignedToName));
    }
    if (goal.closed && goal.closedDate) {
      facts.push(format(labels.closedOn, formatDate(goal.closedDate, locale)));
    }
    const reviews = [];
    if (goal.lastReviewDate) {
      reviews.push(format(labels.lastReviewedOn, formatDate(goal.lastReviewDate, locale)));
    }
    if (!goal.closed && goal.nextReviewDate) {
      reviews.push(format(labels.nextReviewOn, formatDate(goal.nextReviewDate, locale)));
    }
    return {
      id: goal.id,
      name: goal.name,
      description: goal.description,
      status: labelOf(plan.goalStatuses, goal.status),
      closed: !!goal.closed,
      statusWord: goalStatusWord(goal.status),
      facts: facts.join(' · '),
      reviews: reviews.join(' · '),
      reviewDue: isReviewDue(goal, today),
      outcome:
        plan.outcomesAvailable && goal.outcomeName
          ? format(labels.worksToward, goal.outcomeName)
          : '',
      outcomeMissing: !!(plan.outcomesAvailable && goal.outcomeMissing),
      progress: steps.length ? format(labels.stepsDone, done, steps.length) : '',
      progressPercent: steps.length ? Math.round((done * 100) / steps.length) : 0,
      steps: steps.map((step) => ({
        id: step.id,
        name: step.name,
        done: step.status === DONE,
        status: labelOf(plan.stepStatuses, step.status),
        facts: [
          step.targetDate ? format(labels.target, formatDate(step.targetDate, locale)) : '',
          step.assignedToName ? format(labels.assigned, step.assignedToName) : ''
        ]
          .filter(Boolean)
          .join(' · ')
      })),
      notes: (goal.notes || []).map((note) => ({
        id: note.id,
        line: [formatDate(note.noteDate, locale), note.type, note.subject]
          .filter(Boolean)
          .join(' · ')
      })),
      hasNotes: (goal.notes || []).length > 0,
      moreNotes:
        (goal.noteCount || 0) > (goal.notes || []).length
          ? format(labels.moreNotes, goal.noteCount)
          : '',
      newStepFor: format(labels.newStepFor, goal.name)
    };
  });
}

/** The form's starting values: the goal's own, or a new goal's. */
export function goalDraft(plan, goalId) {
  const goal = ((plan && plan.goals) || []).find((candidate) => candidate.id === goalId);
  if (!goal) {
    return {
      id: null,
      name: '',
      description: '',
      status: NOT_STARTED,
      targetDate: null,
      assignedToId: null,
      nextReviewDate: null,
      outcomeId: ''
    };
  }
  return {
    id: goal.id,
    name: goal.name || '',
    description: goal.description || '',
    status: goal.status,
    targetDate: goal.targetDate || null,
    assignedToId: goal.assignedToId || null,
    nextReviewDate: goal.nextReviewDate || null,
    outcomeId: goal.outcomeId || ''
  };
}

/** What `saveGoal` takes: the draft, with the enrollment, and the outcome only where offered. */
export function goalPayload(draft, enrollmentId, outcomesAvailable) {
  const payload = {
    id: draft.id || null,
    enrollmentId,
    name: (draft.name || '').trim(),
    description: draft.description || null,
    status: draft.status || NOT_STARTED,
    targetDate: draft.targetDate || null,
    assignedToId: draft.assignedToId || null,
    nextReviewDate: draft.nextReviewDate || null
  };
  if (outcomesAvailable) {
    payload.outcomeId = draft.outcomeId || null;
  }
  return payload;
}

/** What `saveStep` takes to tick or untick a step: Done, or back to Not Started. */
export function stepToggle(stepId, done) {
  return { id: stepId, status: done ? DONE : NOT_STARTED };
}

/** What `saveStep` takes to add a step under a goal, or null when the name is blank. */
export function newStep(goalId, name) {
  const trimmed = (name || '').trim();
  return trimmed ? { goalId, name: trimmed } : null;
}

/** The outcome choices with "No outcome" first. */
export function outcomeOptions(outcomes, noneLabel) {
  return [{ label: noneLabel, value: '' }].concat(
    (outcomes || []).map(({ label, value }) => ({ label, value }))
  );
}
