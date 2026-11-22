/**
 * What erasing a person does to the archive (canonical model R-ARC6, R-ER8; ADR-0240 archive rules
 * and big object archive item 10). Archived rows cannot be deleted in the erasure's own
 * transaction (an immediate big object call cannot follow its DML), so `erase` queues
 * `ArchiveErasureJob` and reports the rows as counted, not listed. The job does nothing unless
 * the Erasure record exists once it runs, so a preview, which is rolled back, deletes nothing.
 *
 * Registered in `PersonErasureExtensions.EXTENSION_CLASSES`; `@NamespaceAccessible`, public,
 * with a public no-argument constructor, because Core resolves it with `Type.forName` (ADR-0017).
 */
@NamespaceAccessible
public with sharing class ArchiveErasureExtension implements PersonErasureExtension {
	@NamespaceAccessible
	public ArchiveErasureExtension() {
		return;
	}

	/** The archive keeps nothing on the person's own record. */
	public Set<Schema.SObjectField> fieldsToKeep(Schema.SObjectType personType) {
		return new Set<Schema.SObjectField>();
	}

	/** Queues the archive scan when the archive holds any row. */
	public List<PersonErasure.Change> erase(Id personId) {
		List<PersonErasure.Change> changes = new List<PersonErasure.Change>();
		if (personId == null || BigObjectArchiveJob.archivedCount() <= 0) {
			return changes;
		}
		BigObjectArchiveJob.queue(new ArchiveErasureJob(personId));
		changes.add(
			new PersonErasure.Change(
				PersonErasure.DELETED,
				BarnHelp.text('Core', 'Core_ArchiveViewer_ErasureLabel'),
				0,
				BarnHelp.text('Core', 'Core_ArchiveViewer_ErasureNote')
			)
		);
		return changes;
	}
}
