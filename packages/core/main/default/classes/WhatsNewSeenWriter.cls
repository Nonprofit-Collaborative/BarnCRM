/**
 * Stores and reads, for the running user, the release whose What's new notes they dismissed
 * (C-27): one `Nightly_Job__c` row with `Kind__c` Seen, Name `WhatsNew:<UserId>`, the version in
 * `Value__c` (ADR-0238 settings as custom metadata, decision 7).
 *
 * DOCUMENTED EXCEPTION to the user-mode DML rule (plan Section 7.2), under ADR-0021 and
 * ADR-0087 (`0087-whats-new-from-packaged-release-notes.md`). The row lives on an object only
 * BarnCRM Admin can read, and every BarnCRM user, Read Only included, must be able to dismiss
 * the card.
 *
 * The conditions of ADR-0021 are met here:
 *
 * - The write is the running user's own row, reached only from their own Dismiss
 *   (`WhatsNewController.dismiss`); no row of any other user is read or written.
 * - The value is the current version `WhatsNewController` computed from the shipped Release
 *   Note records. No user-typed text reaches it, and the query binds only the user's own key.
 * - Only `Value__c` on that row is written. Nothing else is elevated.
 *
 * A person with no row is read from the legacy `Whats_New_Seen__c` record until phase 2
 * removes it, so nobody sees notes they already dismissed again.
 */
public without sharing class WhatsNewSeenWriter {
	private static final String PREFIX = 'WhatsNew:';

	public static void markSeen(String version) {
		Nightly_Job__c row = ownRow();
		if (row == null) {
			row = new Nightly_Job__c(Name = PREFIX + UserInfo.getUserId(), Kind__c = SettingsState.KIND_SEEN);
		}
		row.Value__c = SettingStore.toJson(version);
		Database.upsert(row, AccessLevel.SYSTEM_MODE);
	}

	/** The version the running user last dismissed, or null when they never have. */
	public static String lastSeen() {
		Nightly_Job__c row = ownRow();
		if (row != null) {
			Object version = SettingStore.parse(row.Value__c);
			return version == null ? null : String.valueOf(version);
		}
		Whats_New_Seen__c legacy = Whats_New_Seen__c.getValues(UserInfo.getUserId());
		return legacy == null ? null : legacy.Last_Seen_Version__c;
	}

	private static Nightly_Job__c ownRow() {
		String name = PREFIX + UserInfo.getUserId();
		List<Nightly_Job__c> rows = [
			SELECT Id, Value__c
			FROM Nightly_Job__c
			WHERE Kind__c = :SettingsState.KIND_SEEN AND Name = :name
			WITH SYSTEM_MODE
			LIMIT 1
		];
		return rows.isEmpty() ? null : rows[0];
	}
}
