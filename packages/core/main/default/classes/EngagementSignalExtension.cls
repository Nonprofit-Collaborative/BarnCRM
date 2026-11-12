/**
 * The seam a module uses to add a part to the engagement score (C-64, canonical model R-ES4,
 * ADR-NEXT `NEXT-engagement-score.md`), under the cross-package mechanism ADR-0017 settled.
 * Core finds an implementation by class name (`EngagementScore.SIGNAL_CLASSES`) and asks it
 * only when it is installed, so Core names no module.
 */
@NamespaceAccessible
public interface EngagementSignalExtension {
	/** The part this signal measures, as the weights and targets settings name it: Gifts, Hours or Events. */
	String key();

	/**
	 * Each person's total since the date (an amount, hours or a count), read in system mode.
	 * A person with nothing may be left out. Never null.
	 */
	Map<Id, Decimal> totals(Set<Id> contactIds, Date since);
}
