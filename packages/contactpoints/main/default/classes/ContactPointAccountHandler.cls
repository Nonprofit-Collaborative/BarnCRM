/**
 * Contact Point Sync on `Account`, for people stored as person accounts (registry row
 * `Contact_Point_Sync_Account`; ADR-0176 contact point sync module, decisions 4, 6, 7 and 14).
 * A switch on the Automation page that Pause All covers.
 *
 * Saving a person account does not fire the Contact triggers, so this does what the Contact
 * handler does for the contact the platform keeps behind it: syncs the person after an insert,
 * an undelete, a change of email or phone, or of their Individual; removes their copies before
 * they are deleted; syncs a merge's survivor. Households and organizations are never touched.
 *
 * Person accounts stay optional: no compile-time reference to a person field. Fields are read
 * by name, only those Account has in this org, and an org without person accounts returns
 * before anything else runs. Never fails a save.
 */
@NamespaceAccessible
public with sharing class ContactPointAccountHandler extends TriggerHandler {
	private static final Set<String> VALUE_KINDS = new Set<String>{
		ContactPointPlan.EMAIL,
		ContactPointPlan.PHONE
	};
	private static final String INDIVIDUAL_LINK = 'PersonIndividualId';
	/** Built once, not for every record of a save. */
	private static final List<String> ACCOUNT_FIELDS = ContactPointPlan.accountFields();
	/** The watched fields this org's Account has, found once a transaction. */
	private static List<String> watchedHere;
	private static Boolean individualLinkHere;

	/** Built by name from Core's dispatcher, so it needs a public constructor. */
	@NamespaceAccessible
	public ContactPointAccountHandler() {
		return;
	}

	public override void afterInsert() {
		ContactPointSyncService.syncOrQueue(idsOf(newRecords()), null);
	}

	public override void afterUpdate() {
		if (ContactPointSyncService.running || !HouseholdService.isPersonAccountOrg()) {
			return;
		}
		Set<Id> valuesOnly = new Set<Id>();
		Set<Id> everything = new Set<Id>();
		List<String> watched = watchedFields();
		for (SObject record : newRecords()) {
			if (!PersonRecordSelector.isPersonRecord(record)) {
				continue;
			}
			// Only the watched fields are read: copying every field of the record into a map,
			// twice per record, cost more than the comparison itself.
			SObject before = oldRecordsById().get(record.Id);
			if (individualLinkHere && record.get(INDIVIDUAL_LINK) != before.get(INDIVIDUAL_LINK)) {
				everything.add(record.Id);
			} else if (valuesChanged(record, before, watched)) {
				valuesOnly.add(record.Id);
			}
		}
		ContactPointSyncService.syncOrQueue(claimRunFor('afterUpdate', everything), null);
		ContactPointSyncService.syncOrQueue(
			claimRunFor('afterUpdateValues', valuesOnly),
			VALUE_KINDS
		);
	}

	public override void beforeDelete() {
		ContactPointSyncService.deleteCopiesOf(idsOf(oldRecords()));
	}

	public override void afterDelete() {
		if (!HouseholdService.isPersonAccountOrg()) {
			return;
		}
		Set<Id> survivors = new Set<Id>();
		for (SObject record : oldRecords()) {
			Object survivor = record.getPopulatedFieldsAsMap().get('MasterRecordId');
			if (survivor instanceof Id && PersonRecordSelector.isPersonRecord(record)) {
				survivors.add((Id) survivor);
			}
		}
		ContactPointSyncService.syncOrQueue(survivors, null);
	}

	public override void afterUndelete() {
		ContactPointSyncService.syncOrQueue(idsOf(newRecords()), null);
	}

	/** The ids of the person accounts among these records; none where the org has none. */
	private static Set<Id> idsOf(List<SObject> records) {
		Set<Id> result = new Set<Id>();
		if (records == null || !HouseholdService.isPersonAccountOrg()) {
			return result;
		}
		for (SObject record : records) {
			if (PersonRecordSelector.isPersonRecord(record)) {
				result.add(record.Id);
			}
		}
		return result;
	}

	private static Boolean valuesChanged(SObject now, SObject before, List<String> watched) {
		for (String field : watched) {
			if (now.get(field) != before.get(field)) {
				return true;
			}
		}
		return false;
	}

	/**
	 * The watched fields Account has in this org, checked once a transaction: an org without
	 * one (no Individual object, say) skips it rather than fail on reading it.
	 */
	@TestVisible
	private static List<String> watchedFields() {
		if (watchedHere == null) {
			Map<String, Schema.SObjectField> fields = Schema.SObjectType.Account.fields.getMap();
			List<String> found = new List<String>();
			for (String field : ACCOUNT_FIELDS) {
				if (fields.containsKey(field.toLowerCase())) {
					found.add(field);
				}
			}
			individualLinkHere = fields.containsKey(INDIVIDUAL_LINK.toLowerCase());
			watchedHere = found;
		}
		return watchedHere;
	}
}
