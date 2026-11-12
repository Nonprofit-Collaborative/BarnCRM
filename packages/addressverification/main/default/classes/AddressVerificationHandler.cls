/**
 * Address Verification on `Address__c` (registry row `Address_Verification`; ADR-0209
 * `0209-address-verification-module.md`, decision 5; canonical model R-AV2, R-AV3). A switch on
 * the Automation page that Pause All covers; the dispatcher skips it while the module is off.
 *
 * Before a change to the street, city, state, postal code or country is saved, the address goes
 * back to Unverified. After the save, with Verify On Save on and the keys entered, one queued job
 * looks up the new and changed Current addresses, up to `AddressVerifier.PER_TRANSACTION`; the
 * rest, and saves made inside a batch or a queued job, wait for the nightly step. Saves the
 * module makes itself are skipped. Never fails a save.
 */
@NamespaceAccessible
public with sharing class AddressVerificationHandler extends TriggerHandler {
	private static final String CONTEXT = 'AddressVerificationHandler';

	/** Built by name from Core's dispatcher, so it needs a public constructor. */
	@NamespaceAccessible
	public AddressVerificationHandler() {
		return;
	}

	public override void beforeUpdate() {
		if (AddressVerifier.writing) {
			return;
		}
		for (SObject record : newRecords()) {
			if (changed(record, oldRecordsById().get(record.Id))) {
				record.put(Address__c.Verification_Status__c, AddressVerifier.UNVERIFIED);
			}
		}
	}

	public override void afterInsert() {
		queue(newRecords());
	}

	public override void afterUpdate() {
		List<SObject> changed = new List<SObject>();
		for (SObject record : newRecords()) {
			if (changed(record, oldRecordsById().get(record.Id))) {
				changed.add(record);
			}
		}
		queue(changed);
	}

	@TestVisible
	private static Boolean changed(SObject record, SObject old) {
		if (old == null) {
			return false;
		}
		for (Schema.SObjectField field : AddressVerifier.WATCHED) {
			if (String.valueOf(record.get(field)) != String.valueOf(old.get(field))) {
				return true;
			}
		}
		return false;
	}

	private static void queue(List<SObject> records) {
		if (
			records.isEmpty() ||
			AddressVerifier.writing ||
			AddressVerifier.settings().Verify_On_Save__c != true ||
			!AddressVerifier.isReady() ||
			System.isBatch() ||
			System.isFuture() ||
			System.isQueueable() ||
			Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()
		) {
			return;
		}
		List<Id> ids = new List<Id>();
		for (SObject record : records) {
			String status = (String) record.get(Address__c.Status__c);
			if (
				(status == null || status == 'Current') &&
				ids.size() < AddressVerifier.PER_TRANSACTION
			) {
				ids.add(record.Id);
			}
		}
		if (ids.isEmpty()) {
			return;
		}
		try {
			System.enqueueJob(new AddressVerificationJob.OnSave(ids));
		} catch (Exception failed) {
			// Left Unverified: the nightly step looks them up.
			ErrorLogger.log(failed, CONTEXT + '.queue');
		}
	}
}
