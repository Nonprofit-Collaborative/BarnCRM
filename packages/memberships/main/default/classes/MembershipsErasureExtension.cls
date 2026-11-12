/**
 * What erasing a person does to their memberships (canonical model R-MEM8; ADR-0110). Core finds
 * this class by name in `PersonErasureExtensions.EXTENSION_CLASSES` and calls it inside the
 * erasure's own transaction. The terms are kept, as gifts are, so counts and history stand; what
 * the person or staff typed about them is cleared: the directory listing and the notes.
 */
@NamespaceAccessible
public with sharing class MembershipsErasureExtension implements PersonErasureExtension {
	@NamespaceAccessible
	public MembershipsErasureExtension() {
		return;
	}

	public Set<Schema.SObjectField> fieldsToKeep(Schema.SObjectType personType) {
		return new Set<Schema.SObjectField>();
	}

	public List<PersonErasure.Change> erase(Id personId) {
		// Rows are found in system mode, so a person with no memberships erases for any eraser;
		// only when there is something to clear must the eraser hold Memberships access.
		List<Membership_Term__c> terms = [
			SELECT Id
			FROM Membership_Term__c
			WHERE Contact__c = :personId OR Account__c = :personId
			WITH SYSTEM_MODE
		];
		List<Member_Certification__c> holdings = [
			SELECT Id, (SELECT Id FROM Continuing_Credits__r)
			FROM Member_Certification__c
			WHERE Contact__c = :personId
			WITH SYSTEM_MODE
		];
		if (!(terms.isEmpty() && holdings.isEmpty())) {
			requireMembershipsAccess();
		}
		List<PersonErasure.Change> changes = eraseCertifications(holdings);
		if (terms.isEmpty()) {
			return changes;
		}
		List<Id> ids = new List<Id>();
		for (Membership_Term__c term : terms) {
			term.Directory_Opt_In__c = false;
			term.Directory_Location__c = null;
			term.Directory_Bio__c = null;
			term.Notes__c = null;
			ids.add(term.Id);
		}
		update as user terms;
		changes.add(
			new PersonErasure.Change(
				PersonErasure.CLEARED,
				Membership_Term__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
					.getLabelPlural(),
				ids,
				new List<String>{
					'Directory_Opt_In__c',
					'Directory_Location__c',
					'Directory_Bio__c',
					'Notes__c'
				}
			)
		);
		return changes;
	}

	/**
	 * Clearing needs edit on terms, certifications and credits and their cleared fields. Without
	 * it the platform would refuse part way, with its own wording.
	 */
	private static void requireMembershipsAccess() {
		Boolean allowed =
			Schema.SObjectType.Membership_Term__c.isUpdateable() &&
			Schema.SObjectType.Membership_Term__c.fields.Notes__c.isUpdateable() &&
			Schema.SObjectType.Membership_Term__c.fields.Directory_Bio__c.isUpdateable() &&
			Schema.SObjectType.Member_Certification__c.isUpdateable() &&
			Schema.SObjectType.Member_Certification__c.fields.Notes__c.isUpdateable() &&
			Schema.SObjectType.Continuing_Credit__c.isUpdateable() &&
			Schema.SObjectType.Continuing_Credit__c.fields.Activity__c.isUpdateable();
		if (!allowed) {
			throw new PersonErasure.ErasureException(
				BarnHelp.text('Memberships', 'Memberships_Erase_NeedAccess')
			);
		}
	}

	/** R-MEM13: the notes on the person's certifications and the activity text of their credits. */
	private static List<PersonErasure.Change> eraseCertifications(
		List<Member_Certification__c> holdings
	) {
		List<PersonErasure.Change> changes = new List<PersonErasure.Change>();
		if (holdings.isEmpty()) {
			return changes;
		}
		List<Id> holdingIds = new List<Id>();
		List<Continuing_Credit__c> credits = new List<Continuing_Credit__c>();
		for (Member_Certification__c holding : holdings) {
			holding.Notes__c = null;
			holdingIds.add(holding.Id);
			for (Continuing_Credit__c credit : holding.Continuing_Credits__r) {
				credits.add(new Continuing_Credit__c(Id = credit.Id, Activity__c = null));
			}
		}
		update as user holdings;
		changes.add(
			new PersonErasure.Change(
				PersonErasure.CLEARED,
				Member_Certification__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
					.getLabelPlural(),
				holdingIds,
				new List<String>{ 'Notes__c' }
			)
		);
		if (!credits.isEmpty()) {
			update as user credits;
			List<Id> creditIds = new List<Id>();
			for (Continuing_Credit__c credit : credits) {
				creditIds.add(credit.Id);
			}
			changes.add(
				new PersonErasure.Change(
					PersonErasure.CLEARED,
					Continuing_Credit__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
						.getLabelPlural(),
					creditIds,
					new List<String>{ 'Activity__c' }
				)
			);
		}
		return changes;
	}
}
