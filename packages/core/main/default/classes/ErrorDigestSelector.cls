/**
 * The reads behind the error digest (C-23, R-E5): the new Error Log entries in a window, and
 * the users it may go to.
 *
 * Every read runs in user mode. The digest runs as the administrator who scheduled it, so it
 * counts what that person can see, which for a BarnCRM Admin is every entry; it never widens
 * what anybody can read, and the links it sends open only for someone allowed to open them.
 */
public with sharing class ErrorDigestSelector {
	/** What arrived in one window, counted rather than copied. */
	public class Window {
		/**
		 * How many errors were counted: each entry's Occurrences, since repeats of one failure
		 * are folded onto one entry (R-E7). Read from at most the cap of entries.
		 */
		public Integer total = 0;
		/** How many entries were read, never more than the cap. */
		public Integer rows = 0;
		/** True when there were more entries than the cap: `total` is then "at least". */
		public Boolean capped = false;
		public Map<String, Integer> bySource = new Map<String, Integer>();
		public Map<String, Integer> bySeverity = new Map<String, Integer>();
		public List<Error_Log__c> newest = new List<Error_Log__c>();
	}

	/**
	 * The entries created after `after` and up to `upTo` that are still New: how many, by source
	 * and by severity, and the newest `listed` by record name. Only the fields the digest may
	 * carry are read: never the message, the technical detail or the record reference.
	 *
	 * At most `cap` entries are read, newest first, and everything is counted from those rows.
	 * A grouped count over the whole window would spend a query row per entry, three times
	 * over, and an Error Log flooded past the transaction's allowance would stop every digest
	 * for good. Reading `cap + 1` says whether there were more.
	 *
	 * Repeats of one failure are folded onto its open entry (R-E7), so an entry created before
	 * the window can gain repeats inside it: an entry last changed in the window counts too,
	 * and every count is the sum of Occurrences, not the number of rows. Without a field for
	 * when each repeat arrived, such an entry counts all its Occurrences, earlier ones included.
	 */
	public static Window newEntries(Datetime after, Datetime upTo, Integer listed, Integer cap) {
		Window window = new Window();
		String statusNew = ErrorLogger.STATUS_NEW;
		Integer readUpTo = cap + 1;
		List<Error_Log__c> rows = [
			SELECT Id, Name, Context__c, Severity__c, Occurrences__c, CreatedDate
			FROM Error_Log__c
			WHERE
				Status__c = :statusNew
				AND ((CreatedDate > :after
				AND CreatedDate <= :upTo)
				OR (LastModifiedDate > :after
				AND LastModifiedDate <= :upTo))
			WITH USER_MODE
			ORDER BY LastModifiedDate DESC, Name DESC
			LIMIT :readUpTo
		];
		window.capped = rows.size() > cap;
		for (Integer i = 0; i < rows.size() && i < cap; i++) {
			Error_Log__c entry = rows[i];
			Integer times = occurrences(entry);
			window.rows++;
			window.total += times;
			increment(window.bySource, entry.Context__c, times);
			increment(window.bySeverity, String.valueOf(entry.Severity__c), times);
			if (i < listed) {
				window.newest.add(entry);
			}
		}
		return window;
	}

	/** An entry's Occurrences, at least 1: an entry written before R-E7 holds none. */
	private static Integer occurrences(Error_Log__c entry) {
		return entry.Occurrences__c == null ||
			entry.Occurrences__c < 1
			? 1
			: entry.Occurrences__c.intValue();
	}

	private static void increment(Map<String, Integer> counts, String key, Integer times) {
		counts.put(key, counts.containsKey(key) ? counts.get(key) + times : times);
	}

	/** The active internal users among the given Ids, in the order given. */
	public static List<User> activeUsers(List<Id> userIds, Integer maximum) {
		if (userIds == null || userIds.isEmpty()) {
			return new List<User>();
		}
		Map<Id, User> found = new Map<Id, User>(
			[
				SELECT Id, Name, Email
				FROM User
				WHERE Id IN :userIds AND IsActive = TRUE AND UserType = 'Standard'
				WITH USER_MODE
			]
		);
		List<User> ordered = new List<User>();
		for (Id userId : userIds) {
			if (found.containsKey(userId) && ordered.size() < maximum) {
				ordered.add(found.get(userId));
			}
		}
		return ordered;
	}

	/**
	 * The active internal users with the given email addresses, one per address (the first by
	 * name when two users share one), keyed by the address in lower case.
	 */
	public static Map<String, User> activeUsersByEmail(Set<String> addresses) {
		Map<String, User> byAddress = new Map<String, User>();
		if (addresses == null || addresses.isEmpty()) {
			return byAddress;
		}
		for (User person : [
			SELECT Id, Name, Email
			FROM User
			WHERE Email IN :addresses AND IsActive = TRUE AND UserType = 'Standard'
			WITH USER_MODE
			ORDER BY Name
			LIMIT 1000
		]) {
			String key = person.Email.toLowerCase();
			if (!byAddress.containsKey(key)) {
				byAddress.put(key, person);
			}
		}
		return byAddress;
	}
}
