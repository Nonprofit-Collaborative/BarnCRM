/**
 * The Answer Library's logic, with no framework in it (F-14, canonical model 29ZN, plan Section
 * 9.9): topics split from free text (R-GA2), the topic list, word counts, and the search that
 * narrows the library. Plain JavaScript in and out, so a WordPress block or Node can use it.
 */

/** The topics in a Topics value: split at commas and semicolons, trimmed, blanks dropped. */
export function splitTopics(topics) {
  return String(topics || '')
    .split(/[,;]/)
    .map((topic) => topic.trim())
    .filter((topic) => topic.length > 0);
}

/**
 * Every topic used, once each regardless of case (the first spelling seen wins), sorted.
 *
 * @param {{topics: string}[]} answers
 * @returns {string[]}
 */
export function topicList(answers) {
  const byKey = new Map();
  (answers || []).forEach((answer) => {
    splitTopics(answer.topics).forEach((topic) => {
      const key = topic.toLowerCase();
      if (!byKey.has(key)) {
        byKey.set(key, topic);
      }
    });
  });
  return [...byKey.values()].sort((a, b) => a.localeCompare(b));
}

/** How many words the text has. */
export function wordCount(text) {
  const words = String(text || '')
    .trim()
    .split(/\s+/)
    .filter((word) => word.length > 0);
  return words.length;
}

/**
 * The answers matching a topic and a search, in the order given.
 *
 * @param {object[]} answers `{id, title, topics, text, lastUsed}`
 * @param {string} topic a topic from `topicList`, or blank for every topic
 * @param {string} search words that must all appear in the title, topics or text (any case)
 * @returns {object[]} each answer with `topicList` and `words` added
 */
export function filterAnswers(answers, topic, search) {
  const wanted = String(topic || '')
    .trim()
    .toLowerCase();
  const terms = String(search || '')
    .toLowerCase()
    .split(/\s+/)
    .filter((term) => term.length > 0);
  return (answers || [])
    .map((answer) => ({
      ...answer,
      topicList: splitTopics(answer.topics),
      words: wordCount(answer.text)
    }))
    .filter((answer) => {
      if (wanted && !answer.topicList.some((each) => each.toLowerCase() === wanted)) {
        return false;
      }
      const haystack = [answer.title, answer.topics, answer.text].join(' ').toLowerCase();
      return terms.every((term) => haystack.includes(term));
    });
}

/** The first `length` characters of the text, cut at a word, with an ellipsis when cut. */
export function preview(text, length = 240) {
  const value = String(text || '').trim();
  if (value.length <= length) {
    return value;
  }
  const cut = value.slice(0, length);
  const lastSpace = cut.lastIndexOf(' ');
  return `${(lastSpace > length / 2 ? cut.slice(0, lastSpace) : cut).trimEnd()}...`;
}
