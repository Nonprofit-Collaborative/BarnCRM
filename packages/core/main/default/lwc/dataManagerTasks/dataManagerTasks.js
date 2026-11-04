/**
 * The task search on Data Manager (admin-23): a person types a task in their own words ("fix
 * capital letters in names", "delete test records") and is shown the tool that does it.
 *
 * The table is data, not a setting: each task names the Data Manager tile it opens (`tool`, the
 * tile's name in dataManager.js), the phrase shown in the results, and extra words people use
 * for the same thing. Framework free (no lightning or @salesforce imports), so the same table
 * and matcher serve BarnCRM for WordPress (plan 9.9). English only, like the help catalog.
 */
export const TASKS = Object.freeze([
  // Super Importer
  {
    tool: 'import',
    text: 'Import donors and their gifts',
    words: 'load upload spreadsheet csv excel file gift donation'
  },
  {
    tool: 'import',
    text: 'Import people from a spreadsheet',
    words: 'contacts load upload csv excel file add new list'
  },
  {
    tool: 'import',
    text: 'Import organizations',
    words: 'accounts companies businesses load upload spreadsheet csv file'
  },
  {
    tool: 'import',
    text: 'Update records from a spreadsheet',
    words: 'change edit file csv excel'
  },
  {
    tool: 'import',
    text: 'Delete the records a file lists',
    words: 'remove erase spreadsheet csv ids'
  },
  // Find
  {
    tool: 'find',
    text: 'Find people without email',
    words: 'missing blank empty no search list contacts address'
  },
  {
    tool: 'find',
    text: 'Export records to a spreadsheet',
    words: 'download csv excel file list'
  },
  {
    tool: 'find',
    text: 'Find records and save the search',
    words: 'query list search report filter'
  },
  {
    tool: 'find',
    text: 'Find households in a city',
    words: 'search address location state zip postal'
  },
  // Super Transformer
  {
    tool: 'update',
    text: 'Fix capital letters in names',
    words: 'capitals uppercase lowercase case proper tidy clean'
  },
  {
    tool: 'update',
    text: 'Change a field on many records',
    words: 'update set bulk mass edit value'
  },
  {
    tool: 'update',
    text: 'Clear a field on many records',
    words: 'blank empty remove erase value bulk mass'
  },
  {
    tool: 'update',
    text: 'Tidy phone numbers',
    words: 'format clean phones fix'
  },
  {
    tool: 'update',
    text: 'Copy one field to another',
    words: 'move fill value'
  },
  // Org Optimizer
  {
    tool: 'optimizer',
    text: 'Check data quality',
    words: 'health problems clean tidy audit review fix'
  },
  {
    tool: 'optimizer',
    text: 'See which fields are used',
    words: 'empty unused utilization full use'
  },
  {
    tool: 'optimizer',
    text: 'Check storage and limits',
    words: 'space usage full'
  },
  // Duplicate Matching
  {
    tool: 'duplicates',
    text: 'Merge two households',
    words: 'combine join duplicate same'
  },
  {
    tool: 'duplicates',
    text: 'Merge duplicate people',
    words: 'combine contacts same twice double'
  },
  {
    tool: 'duplicates',
    text: 'Find duplicate records',
    words: 'dupes same twice double check scan dedupe'
  },
  // Delete Many Records
  {
    tool: 'delete',
    text: 'Delete test records',
    words: 'remove erase trash clean junk sample'
  },
  {
    tool: 'delete',
    text: 'Delete many records at once',
    words: 'remove erase bulk mass'
  }
]);

/** Words that say nothing about the task. */
const STOP_WORDS = new Set(
  'a an and are at by can do for from how i in into is it me my of on or our some that the them this to want we with you your'.split(
    ' '
  )
);

/** Lower case words without punctuation or a plural "s" ("Donors," becomes "donor"). */
export function wordsOf(text) {
  return String(text || '')
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter((word) => word && !STOP_WORDS.has(word))
    .map((word) => {
      const plural = word.length > 3 && word.endsWith('s') && !word.endsWith('ss');
      return plural ? word.slice(0, -1) : word;
    });
}

const MOST_SHOWN = 5;

/**
 * The tasks that match what was typed, best first: each word typed counts when a task word
 * starts with it (so a half-typed word already matches), and a task is shown when at least half
 * of the words typed match. Only tasks whose tool is in `allowedTools` are returned.
 *
 * @param {string} query what the person typed
 * @param {string[]} allowedTools the tile names the person may open
 * @returns {{ key: string, text: string, tool: string }[]}
 */
export function matchTasks(query, allowedTools) {
  const typed = wordsOf(query);
  if (!typed.length) {
    return [];
  }
  const allowed = new Set(allowedTools || []);
  const scored = [];
  TASKS.forEach((task, index) => {
    if (!allowed.has(task.tool)) {
      return;
    }
    const own = wordsOf(`${task.text} ${task.words}`);
    const matched = typed.filter((word) =>
      own.some((taskWord) => taskWord.startsWith(word))
    ).length;
    if (matched > 0 && matched * 2 >= typed.length) {
      scored.push({ index, score: matched / typed.length, task });
    }
  });
  scored.sort((a, b) => b.score - a.score || a.index - b.index);
  return scored.slice(0, MOST_SHOWN).map(({ index, task }) => ({
    key: `task-${index}`,
    text: task.text,
    tool: task.tool
  }));
}
