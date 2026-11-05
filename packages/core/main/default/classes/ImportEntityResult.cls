/**
 * What an entity processor did with one chunk (R-IR6): a sentence for the run log, the total
 * of the gift amounts it read, which the control totals are checked against (R-IB10), and in a
 * dry run the settings it ran under, which the commit is held to (R-IB11).
 *
 * The amount is the total of every row that carries a readable amount, rejected or not,
 * because the question a control total asks is whether this is the file on paper. It is null
 * when the processor read no amounts at all, which is different from a file totalling zero.
 */
@NamespaceAccessible
public with sharing class ImportEntityResult {
	/** One sentence for the run log, or null when there is nothing to say. */
	@NamespaceAccessible
	public String note;

	/** The total of the amounts read in this chunk, or null when none was read. */
	@NamespaceAccessible
	public Decimal fileAmount;

	/**
	 * In a dry run, the settings the processor ran under, as a document only it reads. Core
	 * records it on the batch as Processor Settings, and the commit reads it back from there
	 * rather than from the template, so it does what the dry run showed (R-IB11). Null when
	 * there is nothing to hold the commit to.
	 */
	@NamespaceAccessible
	public String settings;

	@NamespaceAccessible
	public ImportEntityResult() {
		this.note = null;
		this.fileAmount = null;
	}

	@NamespaceAccessible
	public ImportEntityResult(String note, Decimal fileAmount) {
		this.note = note;
		this.fileAmount = fileAmount;
	}
}
