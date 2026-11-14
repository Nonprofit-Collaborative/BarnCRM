/**
 * Name search through the platform search index (SOSL), for typeahead and Find fields
 * (D-200 P5). A LIKE '%term%' on Name reads every row of the object, so it slows as the
 * org grows and times out on large ones; the index answers from its own word list.
 *
 * Each word of the term is matched as the start of a word in the name ("garc" finds
 * Garcia), so callers that need the exact text still check it in Apex. Reserved search
 * characters are escaped, so what a user types is only ever searched for, never parsed.
 * Terms under two characters are not searched: the index needs at least two.
 */
public inherited sharing class NameSearch {
	private static final String RESERVED = '\\?&|!{}[]()^~*:"\'+-';

	/**
	 * The search text for one term: each word escaped, and each word of two or more
	 * characters matched as a prefix.
	 * @param text what the user typed
	 * @return the text to search for, or null when under two characters
	 */
	public static String prefixTerm(String text) {
		String trimmed = text == null ? '' : text.trim();
		if (trimmed.length() < 2) {
			return null;
		}
		List<String> words = new List<String>();
		for (String word : trimmed.split('\\s+')) {
			words.add(escape(word) + (word.length() > 1 ? '*' : ''));
		}
		return String.join(words, ' ');
	}

	/**
	 * Runs one search in user mode, so only records the running user can see come back.
	 * @param searchText text from prefixTerm, or several joined with OR
	 * @param returning the RETURNING clause, for example Contact(Id, Name LIMIT 10)
	 * @return one list per object in the RETURNING clause
	 */
	public static List<List<SObject>> find(String searchText, String returning) {
		return Search.query(
			'FIND {' + searchText + '} IN NAME FIELDS RETURNING ' + returning,
			AccessLevel.USER_MODE
		);
	}

	private static String escape(String word) {
		String result = '';
		for (String character : word.split('')) {
			result += RESERVED.contains(character) ? '\\' + character : character;
		}
		return result;
	}
}
