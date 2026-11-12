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
		List<Membership_Term__c> terms = [
			SELECT Id
			FROM Membership_Term__c
			WHERE Contact__c = :personId OR Account__c = :personId
			WITH USER_MODE
		];
		if (terms.isEmpty()) {
			return new List<PersonErasure.Change>();
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
		return new List<PersonErasure.Change>{
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
		};
	}
}
