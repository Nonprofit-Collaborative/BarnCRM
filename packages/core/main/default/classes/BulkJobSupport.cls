/**
 * What the bulk jobs (Super Transformer, Bulk Delete, inline edit in Find, import undo) share:
 * comparing a stored value with a wanted one, and turning a refusal into text for the journal.
 */
public with sharing class BulkJobSupport {
	/**
	 * Whether two values are the same for a bulk update: numbers as numbers, text exactly, so a
	 * value that differs only in capitals is still written. The preview marks a value it would
	 * leave alone by the same test (C-50), so the preview says what the run does.
	 */
	public static Boolean same(Object stored, Object wanted) {
		if (stored == null || wanted == null) {
			return stored == null && wanted == null;
		}
		if (stored instanceof Decimal || stored instanceof Integer || stored instanceof Double) {
			try {
				return Decimal.valueOf(String.valueOf(stored)) ==
					Decimal.valueOf(String.valueOf(wanted));
			} catch (Exception notANumber) {
				return false;
			}
		}
		if (stored instanceof String || wanted instanceof String) {
			return String.valueOf(stored).equals(String.valueOf(wanted));
		}
		return stored == wanted;
	}

	/** The platform's refusal reasons for one record, as one sentence run. */
	public static String message(List<Database.Error> errors) {
		List<String> parts = new List<String>();
		for (Database.Error error : errors) {
			parts.add(error.getMessage());
		}
		return String.join(parts, ' ');
	}

	/** Adds the journal entry for a record the platform refused, with the reason it gave. */
	public static void journalFailure(
		List<Map<String, Object>> journal,
		String objectName,
		Id recordId,
		List<Database.Error> errors
	) {
		journal.add(ImportJournalService.failed(objectName, recordId, message(errors)));
	}
}
