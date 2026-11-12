/**
 * A migration kit extension's own check of a step (MIG-01, canonical model R-MR3): how many there
 * are to move and how many are moved. The step is verified when the two agree.
 */
@NamespaceAccessible
public inherited sharing class MigrationCheck {
	@NamespaceAccessible
	public Integer source;
	@NamespaceAccessible
	public Integer done;

	@NamespaceAccessible
	public MigrationCheck(Integer source, Integer done) {
		this.source = source;
		this.done = done;
	}
}
