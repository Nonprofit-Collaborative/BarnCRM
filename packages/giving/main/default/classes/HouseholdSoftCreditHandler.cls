/**
 * Recomputes automatic household soft credits when household membership changes (R-SC3,
 * feature G-08).
 *
 * The rule is that every current member of the donor's household other than the donor is
 * recognized. "Current" is the word that makes this class necessary: a household's members
 * change after its gifts are recorded, so the credits recorded at save time go stale unless
 * something puts them right. A person who joins has to be credited on the gifts already there,
 * and a person who leaves has to stop being credited on them.
 *
 * One class, two registry rows, because membership is stored two ways (ADR-0013): as
 * `Household_Member__c` rows in junction mode, and as `Contact.AccountId` in contact mode. Both
 * of the Core triggers for those objects run through the dispatcher, so this handler is
 * registered rather than adding a trigger of its own.
 *
 * The work itself is queued rather than done inline. Recomputing every gift of a household is
 * unbounded work, and it must not be what makes moving one person between households fail.
 */
@NamespaceAccessible
public with sharing class HouseholdSoftCreditHandler extends TriggerHandler {
	@NamespaceAccessible
	public HouseholdSoftCreditHandler() {
		return;
	}

	public override void afterInsert() {
		enqueue(householdIdsOf(newRecords(), null));
	}

	public override void afterUpdate() {
		enqueue(householdIdsOf(newRecords(), oldRecordsById()));
	}

	public override void afterDelete() {
		enqueue(householdIdsOf(oldRecords(), null));
	}

	public override void afterUndelete() {
		enqueue(householdIdsOf(newRecords(), null));
	}

	/**
	 * The households whose membership these records may have changed, from both sides of the
	 * change: a person who moves house makes two households wrong, not one.
	 *
	 * On an update, only a record whose household actually moved is interesting. Every other
	 * edit to a contact (a phone number, a salutation) reaches this handler too, and recomputing
	 * a household's whole giving history for those would be work nobody asked for.
	 */
	private static Set<Id> householdIdsOf(List<SObject> records, Map<Id, SObject> priorById) {
		Set<Id> households = new Set<Id>();
		if (records == null) {
			return households;
		}
		for (SObject record : records) {
			String field = record.getSObjectType() == Household_Member__c.SObjectType
				? 'Household__c'
				: 'AccountId';
			Id household = (Id) record.get(field);
			Id priorHousehold = null;
			if (priorById != null && priorById.containsKey((Id) record.get('Id'))) {
				priorHousehold = (Id) priorById.get((Id) record.get('Id')).get(field);
			}
			if (priorById != null && household == priorHousehold) {
				continue;
			}
			if (household != null) {
				households.add(household);
			}
			if (priorHousehold != null) {
				households.add(priorHousehold);
			}
		}
		return households;
	}

	private static void enqueue(Set<Id> householdIds) {
		HouseholdSoftCreditRecompute.enqueue(householdIds);
	}
}
