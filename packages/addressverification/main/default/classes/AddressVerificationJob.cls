/**
 * The module's background work (ADR-NEXT `NEXT-address-verification-module.md`, decision 5;
 * canonical model R-AV3):
 * - queued with addresses just saved (`AddressVerificationHandler`), it looks them up;
 * - as the nightly step (`AddressVerificationNightlyJobProvider`) or Verify Waiting Addresses,
 *   it starts a batch over Current addresses that are Unverified, or Verified longer ago than
 *   Re-Check After, oldest first, at most Nightly Limit, `AddressVerifier.PER_TRANSACTION` per
 *   transaction.
 * It runs as whoever queued, scheduled or started it, in user mode.
 */
public with sharing class AddressVerificationJob implements Queueable, Database.Batchable<SObject>, Database.AllowsCallouts, Schedulable {
	private final List<Id> addressIds;

	/** The nightly or on-demand batch. */
	public AddressVerificationJob() {
		this.addressIds = null;
	}

	/** The on-save job for the given addresses. */
	public AddressVerificationJob(List<Id> addressIds) {
		this.addressIds = addressIds;
	}

	/** Starts the batch now, unless the module is off, the keys are missing or the limit is 0. */
	public static Id startBatch() {
		if (!AddressVerifier.isOn() || !AddressVerifier.isReady() || limitTonight() <= 0) {
			return null;
		}
		return Database.executeBatch(new AddressVerificationJob(), AddressVerifier.PER_TRANSACTION);
	}

	public void execute(SchedulableContext context) {
		startBatch();
	}

	public void execute(QueueableContext context) {
		AddressVerifier.verify(addressIds);
	}

	public Database.QueryLocator start(Database.BatchableContext context) {
		Integer most = limitTonight();
		Integer months = AddressVerifier.settings().Recheck_Months__c.intValue();
		// Months 0 never re-checks: a cutoff before any possible date.
		Date cutoff = months > 0 ? Date.today().addMonths(-months) : Date.newInstance(1700, 1, 1);
		String unverified = AddressVerifier.UNVERIFIED;
		String verified = AddressVerifier.VERIFIED;
		Set<String> usNames = AddressVerifier.US_NAMES;
		Boolean usOnly = AddressVerifier.provider() == AddressVerifier.SMARTY;
		String query =
			'SELECT Id FROM Address__c WHERE (Status__c = \'Current\' OR Status__c = NULL)' +
			' AND Street__c != NULL AND (Verification_Status__c = :unverified' +
			' OR Verification_Status__c = NULL' +
			' OR (Verification_Status__c = :verified AND Latest_Verified_Date__c < :cutoff))' +
			(usOnly ? ' AND (Country__c = NULL OR Country__c IN :usNames)' : '') +
			' ORDER BY LastModifiedDate ASC LIMIT :most';
		return Database.getQueryLocatorWithBinds(
			query,
			new Map<String, Object>{
				'unverified' => unverified,
				'verified' => verified,
				'cutoff' => cutoff,
				'usNames' => usNames,
				'most' => most
			},
			AccessLevel.USER_MODE
		);
	}

	public void execute(Database.BatchableContext context, List<SObject> scope) {
		AddressVerifier.verify(new List<Id>(new Map<Id, SObject>(scope).keySet()));
	}

	public void finish(Database.BatchableContext context) {
		return;
	}

	private static Integer limitTonight() {
		return AddressVerifier.settings().Nightly_Limit__c.intValue();
	}
}
