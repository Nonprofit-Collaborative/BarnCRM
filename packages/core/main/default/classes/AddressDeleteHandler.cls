/**
 * Contact and Account trigger handler, registered as "Addresses of a deleted person" and
 * "Addresses of a deleted account" (canonical model R-AD11, D-184). When a household,
 * organization or person is deleted, its addresses go to the Recycle Bin with it, unless the
 * Addresses of Deleted Records setting says Keep, and they come back when it is restored.
 *
 * The platform clears an address's owner lookup when the owner is deleted and never puts it
 * back, so before the delete each address is marked with its owner (`Deleted_With__c`, the
 * lookup's name and the owner's Id). Only after the delete does the platform say whether it
 * was a merge (`MasterRecordId`): a merge moves the addresses to the survivor, so their marks
 * are cleared instead. Deleting an account also deletes the contacts it holds, without their
 * triggers, so their addresses are taken with it. System mode, as package upkeep of rows that
 * depend on the deleted record (ADR-0021); a failure is logged and never blocks the delete.
 */
public with sharing class AddressDeleteHandler extends TriggerHandler {
	public static final String KEEP = 'Keep';
	private static final String PROPAGATION = 'Address_Default_Propagation';
	private static final List<Schema.SObjectField> OWNERS = new List<Schema.SObjectField>{
		Address__c.Account__c,
		Address__c.Contact__c,
		Address__c.Person_Account__c
	};

	/** The marked addresses of each record being deleted, from before the delete to after. */
	private static Map<Id, List<Address__c>> markedByRecord = new Map<Id, List<Address__c>>();

	public override void beforeDelete() {
		Map<Id, SObject> deleting = oldRecordsById();
		if (
			deleting == null ||
			KEEP.equalsIgnoreCase(SettingsService.getSettings().Address_Delete_Behavior__c)
		) {
			return;
		}
		try {
			Map<Id, Id> recordOf = new Map<Id, Id>();
			for (Id recordId : deleting.keySet()) {
				recordOf.put(recordId, recordId);
			}
			if (deleting.values()[0] instanceof Account) {
				for (Contact person : AddressSelector.selectContactsOf(deleting.keySet())) {
					recordOf.put(person.Id, person.AccountId);
				}
			}
			List<Address__c> marked = new List<Address__c>();
			for (Address__c address : AddressSelector.selectOwnedBy(recordOf.keySet())) {
				for (Schema.SObjectField owner : OWNERS) {
					Id ownerId = (Id) address.get(owner);
					if (ownerId != null && recordOf.containsKey(ownerId)) {
						// Only the mark is written, never the lookups: a merge reparents them.
						Address__c mark = new Address__c(
							Id = address.Id,
							Deleted_With__c = owner.getDescribe().getLocalName() + ':' + ownerId
						);
						Id recordId = recordOf.get(ownerId);
						if (!markedByRecord.containsKey(recordId)) {
							markedByRecord.put(recordId, new List<Address__c>());
						}
						markedByRecord.get(recordId).add(mark);
						marked.add(mark);
					}
				}
			}
			write(marked, false);
		} catch (Exception thrown) {
			ErrorLogger.log(thrown, 'AddressDeleteHandler.beforeDelete');
		}
	}

	public override void afterDelete() {
		List<SObject> deleted = oldRecords();
		if (deleted == null || markedByRecord.isEmpty()) {
			return;
		}
		List<Address__c> toDelete = new List<Address__c>();
		List<Address__c> toClear = new List<Address__c>();
		for (SObject record : deleted) {
			List<Address__c> marked = markedByRecord.remove(record.Id);
			if (marked != null) {
				(record.get('MasterRecordId') == null ? toDelete : toClear).addAll(marked);
			}
		}
		for (Address__c address : toClear) {
			address.Deleted_With__c = null;
		}
		try {
			write(toClear, false);
			write(toDelete, true);
		} catch (Exception thrown) {
			ErrorLogger.log(thrown, 'AddressDeleteHandler.afterDelete');
		}
	}

	/** Restores the addresses marked with these records, and links each to its owner again. */
	public override void afterUndelete() {
		Map<Id, SObject> restored = newRecordsById();
		if (restored == null) {
			return;
		}
		try {
			Set<Id> ownerIds = new Set<Id>(restored.keySet());
			if (restored.values()[0] instanceof Account) {
				for (Contact person : AddressSelector.selectContactsOf(restored.keySet())) {
					ownerIds.add(person.Id);
				}
			}
			Set<String> marks = new Set<String>();
			for (Id ownerId : ownerIds) {
				for (Schema.SObjectField owner : OWNERS) {
					marks.add(owner.getDescribe().getLocalName() + ':' + ownerId);
				}
			}
			List<Address__c> addresses = AddressSelector.selectDeletedWith(marks);
			if (addresses.isEmpty()) {
				return;
			}
			Database.undelete(addresses, AccessLevel.SYSTEM_MODE);
			for (Address__c address : addresses) {
				String mark = address.Deleted_With__c;
				address.put(
					NamespaceUtil.qualify(mark.substringBefore(':')),
					Id.valueOf(mark.substringAfter(':'))
				);
				address.Deleted_With__c = null;
			}
			Database.update(addresses, AccessLevel.SYSTEM_MODE);
		} catch (Exception thrown) {
			ErrorLogger.log(thrown, 'AddressDeleteHandler.afterUndelete');
		}
	}

	/** Marks, clears or deletes, with the primary address upkeep held off: the owner is going. */
	private static void write(List<Address__c> addresses, Boolean remove) {
		if (addresses.isEmpty()) {
			return;
		}
		Boolean held = AutomationControl.isBypassed(PROPAGATION);
		AutomationControl.bypass(PROPAGATION);
		try {
			if (remove) {
				Database.delete(addresses, AccessLevel.SYSTEM_MODE);
			} else {
				Database.update(addresses, AccessLevel.SYSTEM_MODE);
			}
		} finally {
			if (!held) {
				AutomationControl.clearBypass(PROPAGATION);
			}
		}
	}
}
