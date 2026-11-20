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
	 * by their keys. Returns whether there was nothing left to fill. Before a fill has run,
	 * addresses without a key keep the keys unmarked; after one, `finish` marks them anyway.
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
					Match_Key__c = AddressMatchKeyHandler.keyFor(address.Street__c, address.Postal_Code__c)
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

	/**
	 * Marks the keys filled once the run is over, even when some addresses are still without a
	 * key (plan D-208, N-06). Those are addresses whose save failed in this run (a validation
	 * rule, another automation), each already logged with its reason; left unmarked, every
	 * later Fill Match Keys would try them again, and matching would never read addresses by
	 * key. One Warning entry says how many and where to look. The mark is reversible per
	 * address: any edit to one that saves gives it its key (AddressMatchKeyHandler always runs).
	 */
	public void finish(Database.BatchableContext batchContext) {
		if (markFilledIfNoneUnfilled()) {
			return;
		}
		Integer left = countUnfilled();
		SettingsService.saveBookkeeping(new Map<String, Object>{ 'Match_Keys_Filled__c' => true });
		ErrorLogger.logMessage(
			left == 1
				? BarnHelp.text('Core', 'Core_HealthCheck_MatchKeysLeftOne')
				: BarnHelp.text('Core', 'Core_HealthCheck_MatchKeysLeft', new List<Object>{ left }),
			CONTEXT,
			ErrorLogger.SEVERITY_WARNING
		);
	}

	/** How many addresses with a street and postal code still have no key, up to 50,000. */
	@TestVisible
	private static Integer countUnfilled() {
		if (unfilledForTest == true) {
			return 1;
		}
		return [
			SELECT COUNT()
			FROM Address__c
			WHERE Match_Key__c = NULL AND Postal_Code__c != NULL AND Street__c != NULL
			WITH SYSTEM_MODE
			LIMIT 50000
		];
	}
}
