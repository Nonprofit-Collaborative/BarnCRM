/**
 * Contact Point Sync on `Address__c` (registry row `Contact_Point_Sync_Address`; ADR-0176 contact
 * point sync module, decisions 4, 6 and 7). A switch on the Automation page that Pause All covers.
 *
 * After an address is created, changed, deleted or restored, syncs the address copies of every
 * person it applies to: the person it belongs to, or every member of the household it belongs to
 * (before and after a change, so a moved address leaves its old owners too). Never fails a save.
 */
@NamespaceAccessible
public with sharing class ContactPointAddressHandler extends TriggerHandler {
	private static final Set<String> ADDRESS_ONLY = new Set<String>{ ContactPointPlan.ADDRESS };

	/** Built by name from Core's dispatcher, so it needs a public constructor. */
	@NamespaceAccessible
	public ContactPointAddressHandler() {
		return;
	}

	/** The fields a copy is made from, and the ones that say whose address it is. */
	private static final List<String> WATCHED = new List<String>{
		'Contact__c',
		'Account__c',
		'Person_Account__c',
		'Street__c',
		'City__c',
		'State__c',
		'Postal_Code__c',
		'Country__c',
		'Is_Default__c',
		'Type__c',
		'Status__c'
	};

	public override void afterInsert() {
		sync(newRecords());
	}

	public override void afterUpdate() {
		List<SObject> changed = new List<SObject>();
		for (SObject record : newRecords()) {
			SObject old = oldRecordsById().get(record.Id);
			for (String field : WATCHED) {
				if (ContactPointPlan.changed(record.get(field), old.get(field))) {
					changed.add(record);
					changed.add(old);
					break;
				}
			}
		}
		sync(changed);
	}

	public override void afterDelete() {
		sync(oldRecords());
	}

	public override void afterUndelete() {
		sync(newRecords());
	}

	private void sync(List<SObject> records) {
		if (
			records == null ||
			records.isEmpty() ||
			ContactPointSyncService.activeKinds().isEmpty()
		) {
			return;
		}
		Set<Id> people = new Set<Id>();
		Set<Id> households = new Set<Id>();
		for (SObject record : records) {
			Id personId = (Id) record.get('Contact__c');
			Id accountId = (Id) record.get('Account__c');
			Id personAccountId = (Id) record.get('Person_Account__c');
			if (personId != null) {
				people.add(personId);
			} else if (personAccountId != null) {
				// A person account's own address (decision 14).
				people.add(personAccountId);
			} else if (accountId != null) {
				households.add(accountId);
			}
		}
		if (!households.isEmpty()) {
			for (Set<Id> members : HouseholdService.getMemberPersonIds(households).values()) {
				people.addAll(members);
			}
		}
		// A person being erased is synced once when the erasure ends (ADR-NEXT erasure start seam).
		ContactPointSyncService.syncOrQueue(
			ContactPointSyncService.withoutHeld(people),
			ADDRESS_ONLY
		);
	}
}
