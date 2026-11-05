/**
 * The seam a dependent package implements to resolve the row entities Core cannot (R-IR6).
 *
 * A row can describe a gift, its allocations, a soft credit and a tribute, and those objects
 * live in the Giving package, which depends on Core: Core may not reference them (ADR-0014).
 * Rather than leave those columns unloadable, or move the importer out of Core, Core looks for
 * the implementation by name (`ImportEntityProcessors`), the cross-package mechanism ADR-0017
 * settled on. Where none is installed the columns stay on the staged row and the run log says
 * so; no row is ever rejected for carrying one.
 *
 * The contract (R-IR6, R-IR7, R-IB9, ADR-0052) has three parts: the columns the processor
 * loads, the resolution of one chunk, and its part in an undo.
 */
@NamespaceAccessible
public interface ImportEntityProcessor {
	/**
	 * The targets this processor loads, in the order the column picker should offer them.
	 */
	List<ImportMapping.Target> targets();

	/**
	 * Resolves the entities this implementation owns for one chunk.
	 *
	 * Called after Core has resolved the organization, the household and the people and
	 * written them onto the rows: a row Core rejected arrives with Status Rejected and must be
	 * left alone. The implementation reports each row it handled by setting Status to Rejected
	 * (with Error Message), Created or Matched, and may set the row's Gift and Soft Credit
	 * identifiers; Core folds that into the row's final status (R-IR7). It must be bulk safe,
	 * must honor `dryRun` by writing nothing, and must not throw: a failure belongs on the row
	 * it came from.
	 *
	 * A commit is held to what its dry run showed (R-IB11): whatever settings the processor
	 * returned from the dry run arrive on the batch as Processor Settings, and the commit reads
	 * them there rather than from the template, which may have been edited since.
	 *
	 * @param batch the import being run, for the batch tag and the dry run's settings
	 * @param template the template the batch runs with
	 * @param rows the staged rows of this chunk, carrying Core's resolved references
	 * @param entitiesByRowId each row's values, entity to attribute to value, with the
	 *        template's defaults applied
	 * @param dryRun true when nothing may be written
	 * @return the run log note, the total of the gift amounts read and, in a dry run, the
	 *         settings it ran under; never null
	 */
	ImportEntityResult resolve(
		Import_Batch__c batch,
		Import_Template__c template,
		List<Import_Row__c> rows,
		Map<Id, Map<String, Map<String, String>>> entitiesByRowId,
		Boolean dryRun
	);

	/**
	 * The objects this processor tags with Created By Import Batch, in the order an undo
	 * deletes them. Each must carry a `Created_By_Import_Batch__c` reference and a Name.
	 */
	List<Schema.SObjectType> taggedObjects();

	/**
	 * Why each of these records must survive an undo of this batch, beyond Core's own checks,
	 * keyed by record identifier; records not in the map may go. Asked for the processor's own
	 * tagged objects and for Core's people, households and organizations (R-IB9).
	 */
	Map<Id, String> reasonsToKeep(Id batchId, Schema.SObjectType type, Set<Id> recordIds);
}
