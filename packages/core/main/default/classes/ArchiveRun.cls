/**
 * One run of an archive rule, as a destination receives it (canonical model R-SQ18, ADR-0240
 * archive rules and big object archive): the saved query, its document, and how many records the
 * person confirmed (a manual run) or the run limit allowed (a scheduled run).
 */
@NamespaceAccessible
public with sharing class ArchiveRun {
	/** The saved query that is the rule. */
	@NamespaceAccessible
	public Id savedQueryId;
	/** The rule's name as it is now. */
	@NamespaceAccessible
	public String ruleName;
	/** The query document, checked by the caller as the running person. */
	@NamespaceAccessible
	public String queryJson;
	/** The API name of the object the query reads. */
	@NamespaceAccessible
	public String objectName;
	/** The most records this run may move: the typed count, or the count within the run limit. */
	@NamespaceAccessible
	public Integer confirmedCount;
	/** True when the nightly run started it rather than a person. */
	@NamespaceAccessible
	public Boolean scheduled = false;
	/**
	 * When the backup before the run started (ADR-0240 amendment AR-15), or null: a record changed
	 * after it is kept, so every record moved is as its backup holds it. Null means the run's start.
	 */
	@NamespaceAccessible
	public Datetime notChangedAfter;

	@NamespaceAccessible
	public ArchiveRun(Id savedQueryId, String ruleName, String queryJson, String objectName, Integer confirmedCount) {
		this.savedQueryId = savedQueryId;
		this.ruleName = ruleName;
		this.queryJson = queryJson;
		this.objectName = objectName;
		this.confirmedCount = confirmedCount;
	}
}
