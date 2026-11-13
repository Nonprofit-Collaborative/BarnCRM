/**
 * Gives every address saved before `Address__c.Match_Key__c` existed its key (D-200 P6), then
 * marks the keys filled so matching reads addresses by them. Started by Health Check's Match
 * Keys Not Filled finding. `without sharing` (register: Org job): an address the person who
 * started it cannot see would otherwise keep no key, and matching on keys would miss it.
 *
 * Each address is saved with only its new key; AddressMatchKeyHandler, which always runs,
 * sets the same key on the save. The other address automations see no other field change.
 */
public without sharing class AddressMatchKeyBatch implements Database.Batchable<SObject> {
	/** Each address save runs every Address trigger handler, so chunks stay at the usual 200. */
	private static final Integer CHUNK_SIZE = 200;
	private static final String CONTEXT = 'AddressMatchKeyBatch';

	/** Test seam: answers whether any address is unfilled, without one the trigger leaves so. */
	@TestVisible
	private static Boolean unfilledForTest;

	/**
	 * Starts filling the keys, or refuses when the org is busy (AsyncStarter). With nothing to
	 * fill, as in a new org where every address got its key on save, the keys are marked filled
	 * at once and no job starts: returns null.
	 */
	public static Id run() {
		if (markFilledIfNoneUnfilled()) {
			return null;
		}
		return AsyncStarter.batch(new AddressMatchKeyBatch(), CHUNK_SIZE, CONTEXT);
	}

	/**
	 * Marks the keys filled when no address is left without one, so matching reads addresses
	 * by their keys. Returns whether there was nothing left to fill. Addresses whose save keeps
	 * failing stay unfilled, and the keys stay unmarked, as before.
	 */
	public static Boolean markFilledIfNoneUnfilled() {
		if (anyUnfilled()) {
			return false;
		}
		SettingsService.saveBookkeeping(new Map<String, Object>{ 'Match_Keys_Filled__c' => true });
		return true;
	}

	/** Whether any address with a street and postal code still has no key. */
	public static Boolean anyUnfilled() {
		if (unfilledForTest != null) {
			return unfilledForTest;
		}
		return [
				SELECT COUNT()
				FROM Address__c
				WHERE Match_Key__c = NULL AND Postal_Code__c != NULL AND Street__c != NULL
				WITH SYSTEM_MODE
				LIMIT 1
			] > 0;
	}

	public Database.QueryLocator start(Database.BatchableContext context) {
		return Database.getQueryLocator(
			[
				SELECT Id, Street__c, Postal_Code__c
				FROM Address__c
				WHERE Match_Key__c = NULL AND Postal_Code__c != NULL AND Street__c != NULL
				WITH SYSTEM_MODE
			]
		);
	}

	public void execute(Database.BatchableContext batchContext, List<Address__c> scope) {
		List<Address__c> keyed = new List<Address__c>();
		List<Id> ids = new List<Id>();
		for (Address__c address : scope) {
			keyed.add(
				new Address__c(
					Id = address.Id,
					Match_Key__c = AddressMatchKeyHandler.keyFor(
						address.Street__c,
						address.Postal_Code__c
					)
				)
			);
			ids.add(address.Id);
		}
		ErrorLogger.logFailures(
			Database.update(keyed, false, AccessLevel.SYSTEM_MODE),
			ids,
			CONTEXT,
			ErrorLogger.SEVERITY_WARNING
		);
	}

	public void finish(Database.BatchableContext context) {
		markFilledIfNoneUnfilled();
	}
}
