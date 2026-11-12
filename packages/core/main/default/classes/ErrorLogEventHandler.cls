/**
 * Writes the Error Log row from the event `ErrorLogWriter` published.
 *
 * ADR-0021 (system mode writes for package owned data) is the authority for this class and
 * names it as one of its writers. This is the write that must happen whoever was working when
 * the failure happened, including a user with no create access on the Error Log. Running in
 * system mode ensures the entry is written even when the running user would otherwise lack
 * permission to create it. It runs in the platform's own subscriber transaction and returns
 * nothing.
 *
 * Repeats are counted, not written (R-E7): an event with the same Context, Message and Severity
 * as a New entry first written within the last hour adds one to that entry's Occurrences and
 * names its record among the entry's first few, so a bulk load failing the same way on 10,000
 * rows leaves one row to read, not 10,000. The match is on `Occurrence_Key__c`, a hash of the
 * three, because a long text Message cannot be filtered on.
 *
 * The entry names the person who published the event, `CreatedById`, which the platform sets.
 * The payload's `User_Id__c` is never trusted for that: anyone with Create on the event could
 * publish one through the API naming somebody else.
 *
 * It does not go through `TriggerDispatcher`. Recording a failure is not an automation an
 * administrator can switch off or pause: rule R-A3 says turning an automation off never suppresses
 * error logging, and a pause during a bulk load is exactly when the entries matter most.
 *
 * It never throws. A failure here would retry the event and could loop.
 */
public without sharing class ErrorLogEventHandler {
	private static final String DEFAULT_SEVERITY = 'Error';
	private static final Set<String> SEVERITIES = new Set<String>{
		'Info',
		'Warning',
		'Error',
		'Critical'
	};

	/** How long after an entry's first occurrence a repeat is counted on it. */
	@TestVisible
	private static final Integer WINDOW_MINUTES = 60;

	/** Records named on an entry besides its Record Reference. */
	@TestVisible
	private static final Integer MORE_RECORDS = 10;

	private static final String SEPARATOR = ',';

	public static void handle(List<Error_Log_Event__e> events) {
		if (events == null || events.isEmpty()) {
			return;
		}
		try {
			// Repeats within this delivery fold into the first of their kind.
			Map<String, Error_Log__c> firstByKey = new Map<String, Error_Log__c>();
			List<Error_Log__c> entries = new List<Error_Log__c>();
			for (Error_Log_Event__e event : events) {
				Error_Log__c entry = entryFor(event);
				Error_Log__c first = firstByKey.get(entry.Occurrence_Key__c);
				if (first == null) {
					firstByKey.put(entry.Occurrence_Key__c, entry);
					entries.add(entry);
				} else {
					first.Occurrences__c++;
					addRecord(first, entry.Record_Reference__c, entry.Object_Name__c);
				}
			}
			Map<String, Error_Log__c> openByKey = openEntries(firstByKey.keySet());
			List<Error_Log__c> toInsert = new List<Error_Log__c>();
			List<Error_Log__c> toUpdate = new List<Error_Log__c>();
			for (Error_Log__c entry : entries) {
				Error_Log__c open = openByKey.get(entry.Occurrence_Key__c);
				if (open == null) {
					toInsert.add(entry);
					continue;
				}
				open.Occurrences__c =
					(open.Occurrences__c == null ? 1 : open.Occurrences__c) + entry.Occurrences__c;
				addRecord(open, entry.Record_Reference__c, entry.Object_Name__c);
				for (String recordId : idsIn(entry.Other_Record_Ids__c)) {
					addRecord(open, recordId, entry.Object_Name__c);
				}
				toUpdate.add(open);
			}
			Database.insert(toInsert, false, AccessLevel.SYSTEM_MODE);
			Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
		} catch (Exception failedToLog) {
			// Deliberate last resort: this is the write that turns an Error Log event into the
			// Error_Log__c row, so when it itself fails there is nowhere left to record the
			// failure but the debug log. Kept intentionally (PMD AvoidDebugStatements finding
			// accepted, not suppressed).
			System.debug(
				LoggingLevel.ERROR,
				'BarnCRM could not write an Error Log record from an event: ' +
				failedToLog.getMessage()
			);
		}
	}

	private static Error_Log__c entryFor(Error_Log_Event__e event) {
		Error_Log__c entry = new Error_Log__c(
			Timestamp__c = event.CreatedDate == null ? System.now() : event.CreatedDate,
			User__c = event.CreatedById,
			Context__c = event.Context__c,
			Message__c = event.Message__c,
			Technical_Detail__c = event.Technical_Detail__c,
			Record_Reference__c = event.Record_Reference__c,
			Object_Name__c = event.Object_Name__c,
			Severity__c = SEVERITIES.contains(event.Severity__c)
				? event.Severity__c
				: DEFAULT_SEVERITY,
			Status__c = 'New',
			Occurrences__c = 1
		);
		entry.Occurrence_Key__c = keyOf(entry);
		return entry;
	}

	/** The hash two entries share when they report the same failure (R-E7). */
	@TestVisible
	private static String keyOf(Error_Log__c entry) {
		String text = String.join(
			new List<String>{
				entry.Context__c == null ? '' : entry.Context__c,
				entry.Severity__c,
				entry.Message__c == null ? '' : entry.Message__c
			},
			'\n'
		);
		return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(text)));
	}

	/** The newest New entry of each key first written within the window. */
	private static Map<String, Error_Log__c> openEntries(Set<String> keys) {
		Map<String, Error_Log__c> byKey = new Map<String, Error_Log__c>();
		Datetime since = System.now().addMinutes(-WINDOW_MINUTES);
		for (Error_Log__c open : [
			SELECT
				Id,
				Occurrence_Key__c,
				Occurrences__c,
				Record_Reference__c,
				Object_Name__c,
				Other_Record_Ids__c
			FROM Error_Log__c
			WHERE Occurrence_Key__c IN :keys AND Timestamp__c >= :since AND Status__c = 'New'
			WITH SYSTEM_MODE
			ORDER BY Timestamp__c DESC
			LIMIT 2000
		]) {
			if (!byKey.containsKey(open.Occurrence_Key__c)) {
				byKey.put(open.Occurrence_Key__c, open);
			}
		}
		return byKey;
	}

	/** Names one more record on the entry, while it names fewer than its share. */
	private static void addRecord(Error_Log__c entry, String recordId, String objectName) {
		if (String.isBlank(recordId) || recordId == entry.Record_Reference__c) {
			return;
		}
		if (String.isBlank(entry.Record_Reference__c)) {
			entry.Record_Reference__c = recordId;
			entry.Object_Name__c = objectName;
			return;
		}
		List<String> more = idsIn(entry.Other_Record_Ids__c);
		if (more.size() < MORE_RECORDS && !more.contains(recordId)) {
			more.add(recordId);
			entry.Other_Record_Ids__c = String.join(more, SEPARATOR);
		}
	}

	private static List<String> idsIn(String joined) {
		return String.isBlank(joined) ? new List<String>() : joined.split(SEPARATOR);
	}
}
