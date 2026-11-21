/**
 * What erasing a person does to BarnCRM Connector (CN-18; canonical model R-ER8, R-CR17; design
 * Section 5). A run's Input, State and Step Log can hold what an app or a record said about the
 * person, and its Reference names the post it answered, so every run that names the person's
 * record Id or one of their email addresses is deleted, with all of that, in the erasure's own
 * transaction. Recipes are kept: they are the admin's settings, not data about a person.
 *
 * Core empties the person's email fields before it asks modules to `erase`, so `beforeErase`
 * reads them first (ADR-0193 erasure start seam). Runs are module bookkeeping that nobody edits
 * (R-RUN1), so they are found and deleted past sharing through `ConnectorRunStore`, whoever
 * erases. When the search finds too many runs to be sure of finding every one, the erasure is
 * refused, as for any module that cannot answer (R-ER8).
 *
 * `@NamespaceAccessible`, public, with a public no-argument constructor, because Core resolves
 * it with `Type.forName` under ADR-0017.
 */
@NamespaceAccessible
public with sharing class ConnectorErasureExtension implements PersonErasureExtension, PersonErasureStartExtension {
	/** The person's email addresses, read before Core empties them, by person. */
	private static Map<Id, List<String>> emailsByPerson = new Map<Id, List<String>>();

	@NamespaceAccessible
	public ConnectorErasureExtension() {
		return;
	}

	/** The module keeps nothing on the person's own record. */
	public Set<Schema.SObjectField> fieldsToKeep(Schema.SObjectType personType) {
		return new Set<Schema.SObjectField>();
	}

	/** Reads every email field of the person's record, before Core empties them. */
	public void beforeErase(Id personId) {
		Schema.SObjectType type = personId.getSObjectType();
		List<String> fields = new List<String>();
		for (Schema.SObjectField field : type.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap().values()) {
			Schema.DescribeFieldResult described = field.getDescribe();
			if (described.getType() == Schema.DisplayType.EMAIL) {
				fields.add(described.getName());
			}
		}
		List<String> emails = new List<String>();
		if (!fields.isEmpty()) {
			// Access mode: read past sharing and field access; only the addresses are kept, in memory.
			List<SObject> people = Database.queryWithBinds(
				'SELECT ' + String.join(fields, ', ') + ' FROM ' + type + ' WHERE Id = :personId',
				new Map<String, Object>{ 'personId' => personId },
				AccessLevel.SYSTEM_MODE
			);
			for (SObject person : people) {
				for (String field : fields) {
					String email = (String) person.get(field);
					if (
						String.isNotBlank(email) &&
						email.contains('@') &&
						!emails.contains(email.trim().toLowerCase())
					) {
						emails.add(email.trim().toLowerCase());
					}
				}
			}
		}
		emailsByPerson.put(personId, emails);
	}

	/** Deletes the runs that name the person and lists them as Deleted. */
	public List<PersonErasure.Change> erase(Id personId) {
		List<String> emails = emailsByPerson.containsKey(personId) ? emailsByPerson.get(personId) : new List<String>();
		List<Id> runs = ConnectorRunStore.runsNaming(personId, emails);
		if (runs == null) {
			throw new PersonErasure.ErasureException(
				BarnHelp.text(
					'Connector',
					'Connector_Erase_TooManyRuns',
					new List<Object>{ ConnectorRunStore.MOST_SEARCHED }
				)
			);
		}
		List<PersonErasure.Change> changes = new List<PersonErasure.Change>();
		if (runs.isEmpty()) {
			return changes;
		}
		ConnectorRunStore.deleteRuns(runs);
		changes.add(
			new PersonErasure.Change(
				PersonErasure.DELETED,
				Connector_Run__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getLabelPlural(),
				runs,
				null
			)
		);
		return changes;
	}

	/** Nothing is held past the run; the addresses read are dropped. */
	public void afterErase(Id personId) {
		emailsByPerson.remove(personId);
	}
}
