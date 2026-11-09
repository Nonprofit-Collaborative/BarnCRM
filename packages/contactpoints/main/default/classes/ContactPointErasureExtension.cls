/**
 * What erasing a person does to Contact Point Sync (canonical model R-ER8, R-CPL4; ADR-0176
 * contact point sync module; ADR-0193 erasure start seam). The module keeps no records of its
 * own about a person: its copies follow the person's values, so this only times them.
 *
 * An erasure deletes the person's addresses and then ends their memberships, and each change
 * used to sync the person's address copies on its own. `beforeErase` holds that person's address
 * copies, `erase` (asked after every other module) makes them once from the final state, and
 * `afterErase` always ends the hold, so a failed run never leaves syncing off for the rest of
 * the transaction. Email and phone copies follow the person's own save as before.
 *
 * `@NamespaceAccessible`, public, with a public no-argument constructor, because Core resolves
 * it with `Type.forName` under ADR-0017.
 */
@NamespaceAccessible
public with sharing class ContactPointErasureExtension implements PersonErasureExtension, PersonErasureStartExtension {
	@NamespaceAccessible
	public ContactPointErasureExtension() {
		return;
	}

	/** The module keeps nothing on the person's own record. */
	public Set<Schema.SObjectField> fieldsToKeep(Schema.SObjectType personType) {
		return new Set<Schema.SObjectField>();
	}

	public void beforeErase(Id personId) {
		ContactPointSyncService.holdAddresses(personId);
	}

	/** Makes the held address copies once; nothing of the module's own to list. */
	public List<PersonErasure.Change> erase(Id personId) {
		ContactPointSyncService.releaseAddresses(personId, true);
		return new List<PersonErasure.Change>();
	}

	public void afterErase(Id personId) {
		ContactPointSyncService.releaseAddresses(personId, false);
	}
}
