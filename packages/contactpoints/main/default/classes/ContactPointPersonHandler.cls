/**
 * Contact Point Sync on Contact (registry row `Contact_Point_Sync_Person`; ADR-0176 contact point
 * sync module, decisions 6 and 7). A switch on the Automation page that Pause All covers.
 *
 * - Before insert and update: gives a person with an email or phone to copy an Individual, so the
 *   copy needs no second save of the person.
 * - After insert, update and undelete: syncs the people whose email or phone changed, and every
 *   kind for a person whose household account or Individual changed, or who was restored.
 * - Before delete: deletes the managed copies of the people being deleted (or merged away).
 * - After delete: syncs each merge's surviving person.
 *
 * Never fails a save: the service logs what it cannot do.
 */
@NamespaceAccessible
public with sharing class ContactPointPersonHandler extends TriggerHandler {
	private static final Set<String> VALUE_KINDS = new Set<String>{
		ContactPointPlan.EMAIL,
		ContactPointPlan.PHONE
	};
	/** Built once, not for every record of a save. */
	private static final List<String> PERSON_FIELDS = ContactPointPlan.personFields();
	/** What a sync of a person depends on: their values, household and Individual. */
	private static final List<String> SIGNATURE_FIELDS_WITHOUT_INDIVIDUAL = signatureFields(false);
	private static final List<String> SIGNATURE_FIELDS = signatureFields(true);

	private static List<String> signatureFields(Boolean withIndividual) {
		List<String> fields = new List<String>(PERSON_FIELDS);
		fields.add('AccountId');
		if (withIndividual) {
			fields.add('IndividualId');
		}
		return fields;
	}

	/** Built by name from Core's dispatcher, so it needs a public constructor. */
	@NamespaceAccessible
	public ContactPointPersonHandler() {
		return;
	}

	public override void beforeInsert() {
		List<Contact> people = new List<Contact>();
		for (SObject record : newRecords()) {
			people.add((Contact) record);
		}
		ContactPointSyncService.linkIndividualsBeforeSave(people);
	}

	public override void beforeUpdate() {
		if (ContactPointSyncService.running) {
			return;
		}
		List<Contact> changed = new List<Contact>();
		for (SObject record : newRecords()) {
			if (valuesChanged(record, oldRecordsById().get(record.Id))) {
				changed.add((Contact) record);
			}
		}
		ContactPointSyncService.linkIndividualsBeforeSave(changed);
	}

	public override void afterInsert() {
		ContactPointSyncService.syncInserted(newRecordsById());
	}

	public override void afterUpdate() {
		if (ContactPointSyncService.running) {
			return;
		}
		// A person who moved household: forget who was said to belong where, so the household
		// addresses are read for the new household in this same transaction (decision 15).
		HouseholdService.membershipChangeOf(newRecords(), oldRecordsById());
		Set<Id> valuesOnly = new Set<Id>();
		Set<Id> everything = new Set<Id>();
		for (SObject record : newRecords()) {
			SObject old = oldRecordsById().get(record.Id);
			if (moved(record, old)) {
				everything.add(record.Id);
			} else if (valuesChanged(record, old)) {
				valuesOnly.add(record.Id);
			}
		}
		ContactPointSyncService.syncOrQueue(claimValues('afterUpdate', everything), null);
		ContactPointSyncService.syncOrQueue(
			claimValues('afterUpdateValues', valuesOnly),
			VALUE_KINDS
		);
	}

	/**
	 * The people not yet synced with the values they hold now. A re-fire of the same save (a
	 * workflow or flow update) is synced once; a second, different change in the same
	 * transaction is synced again rather than left behind on the copy.
	 */
	private Set<Id> claimValues(String phase, Set<Id> personIds) {
		if (personIds.isEmpty()) {
			return personIds;
		}
		// One claim for the save; only a person already synced in this transaction is compared
		// with the record they were synced from (a field read each, no copy of the record).
		Set<Id> result = claimRunFor(phase, personIds);
		if (!SYNCED_FROM.containsKey(phase)) {
			SYNCED_FROM.put(phase, new Map<Id, SObject>());
		}
		Map<Id, SObject> last = SYNCED_FROM.get(phase);
		List<String> fields = ContactPointSyncService.individualsAvailable()
			? SIGNATURE_FIELDS
			: SIGNATURE_FIELDS_WITHOUT_INDIVIDUAL;
		for (Id personId : personIds) {
			SObject now = newRecordsById().get(personId);
			if (
				result.contains(personId) ||
				!last.containsKey(personId) ||
				ContactPointPlan.anyChanged(now, last.get(personId), fields)
			) {
				result.add(personId);
				last.put(personId, now);
			}
		}
		return result;
	}

	/** By phase, the record each person was last synced from in this transaction. */
	private static final Map<String, Map<Id, SObject>> SYNCED_FROM = new Map<String, Map<Id, SObject>>();

	public override void beforeDelete() {
		ContactPointSyncService.deleteCopiesOf(oldRecordsById().keySet());
	}

	public override void afterDelete() {
		Set<Id> survivors = new Set<Id>();
		for (SObject record : oldRecords()) {
			Id survivor = (Id) record.get('MasterRecordId');
			if (survivor != null) {
				survivors.add(survivor);
			}
		}
		ContactPointSyncService.syncOrQueue(survivors, null);
	}

	public override void afterUndelete() {
		ContactPointSyncService.syncOrQueue(newRecordsById().keySet(), null);
	}

	private static Boolean valuesChanged(SObject record, SObject old) {
		return old == null || ContactPointPlan.anyChanged(record, old, PERSON_FIELDS);
	}

	/** A new household (and so new household addresses) or a new Individual. */
	private static Boolean moved(SObject record, SObject old) {
		if (old == null || record.get('AccountId') != old.get('AccountId')) {
			return true;
		}
		return ContactPointSyncService.individualsAvailable() &&
			record.get('IndividualId') != old.get('IndividualId');
	}
}
