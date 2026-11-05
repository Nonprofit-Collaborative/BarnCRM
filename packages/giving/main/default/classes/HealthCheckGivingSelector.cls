/**
 * The read behind the Health Check finding for unposted gifts in a closed period (G-20
 * follow-up, ADR-0053, ADR-0021 as amended by ADR-0057). Gifts the lock already treats as in
 * the books (ADR-0022, `GiftPostingLock.BOOK_STATUSES` and `TYPE_IN_KIND`, or a blank status,
 * which `GiftPostingLock.isInBooks` also reads as Received), dated on or before the close date,
 * that nothing has ever marked posted.
 *
 * `Status__c` carries `<required>true</required>`, enforced at the DML layer for a custom
 * field, so no gift inserted through ordinary Apex DML can ever have a blank status; the
 * `Status__c = NULL` half of the match below is for parity with `isInBooks` and for any gift
 * that predates the field becoming required, not for a case this package's own tests can
 * produce (`HealthCheckGivingSelectorTest`).
 *
 * `without sharing` and `WITH SYSTEM_MODE`, the same pair `GiftImportIntegritySelector` uses and
 * for the same reason: this is a fact about the org, not about what the viewer may see. Gift__c
 * ships Private (R-G14), and a Health Check finding that silently under-counts for an
 * administrator who does not happen to own or share every gift is a wrong answer, not a
 * narrower one. `WITH SYSTEM_MODE` alone would not have reached every gift here: it lifts field
 * and object security, but sharing is decided by the class keyword, not the query clause, so the
 * class itself has to give up sharing.
 *
 * ADR-0021 keeps reads that reach a user in user mode; this one reaches a user (the
 * administrator reading Health Check) and still runs without sharing, which ADR-0057 records as
 * an explicit exception to that rule, with what it exposes (a capped count, and for at most
 * five gifts, Id, Name and Gift_Date__c: never a donor, an amount or any other financial field)
 * and its gate. That gate, `HealthCheckService.canManageSettings()`, is asserted here as well as
 * by the caller, so a future caller cannot reach this org-wide read by skipping the check.
 */
public without sharing class HealthCheckGivingSelector {
	/** How many gifts are in the books, dated in a closed period, and not yet posted. Capped. */
	public static Integer countUnpostedInClosedPeriod(Date closed, Integer cap) {
		if (closed == null || !HealthCheckService.canManageSettings()) {
			return 0;
		}
		return [
			SELECT COUNT()
			FROM Gift__c
			WHERE
				(Status__c IN :GiftPostingLock.BOOK_STATUSES
				OR Status__c = NULL)
				AND Type__c != :GiftPostingLock.TYPE_IN_KIND
				AND Gift_Date__c <= :closed
				AND Accounting_Posted_At__c = NULL
			WITH SYSTEM_MODE
			LIMIT :cap
		];
	}

	/** The earliest-dated of those gifts, to link a few examples. */
	public static List<Gift__c> unpostedInClosedPeriod(Date closed, Integer howMany) {
		if (closed == null || !HealthCheckService.canManageSettings()) {
			return new List<Gift__c>();
		}
		return [
			SELECT Id, Name, Gift_Date__c
			FROM Gift__c
			WHERE
				(Status__c IN :GiftPostingLock.BOOK_STATUSES
				OR Status__c = NULL)
				AND Type__c != :GiftPostingLock.TYPE_IN_KIND
				AND Gift_Date__c <= :closed
				AND Accounting_Posted_At__c = NULL
			WITH SYSTEM_MODE
			ORDER BY Gift_Date__c ASC, Id ASC
			LIMIT :howMany
		];
	}
}
