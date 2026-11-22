/**
 * The Archive Rules and Archived Records panels' controller (`archiveRules`, `archivedRecords`,
 * canonical model R-SQ16 and Section 29D1): thin, plain shapes; the rules and permission checks
 * are in `ArchiveRuleService` and `ArchiveViewerService`.
 */
public with sharing class ArchiveController {
	private static final UserErrors.Screen ERRORS = new UserErrors.Screen(
		null,
		null,
		System.Label.Core_UnexpectedError
	);

	@AuraEnabled
	public static ArchiveRuleService.Panel getRules() {
		try {
			return ArchiveRuleService.page();
		} catch (Exception e) {
			throw ERRORS.wrap(e, 'ArchiveController.getRules');
		}
	}

	/**
	 * Saves a rule (JSON of `ArchiveRules.Rule`) on one of the person's saved queries, or takes it
	 * off when `ruleJson` is empty. `confirmedCount` is the preview count, typed to turn a schedule on.
	 */
	@AuraEnabled
	public static ArchiveRuleService.Panel saveRule(Id queryId, String ruleJson, Integer confirmedCount) {
		try {
			ArchiveRules.Rule rule = String.isBlank(ruleJson)
				? null
				: (ArchiveRules.Rule) JSON.deserialize(ruleJson, ArchiveRules.Rule.class);
			ArchiveRuleService.save(queryId, rule, confirmedCount);
			return ArchiveRuleService.page();
		} catch (Exception e) {
			throw ERRORS.wrap(e, 'ArchiveController.saveRule');
		}
	}

	@AuraEnabled
	public static BulkDeleteService.Preview previewRule(Id queryId) {
		try {
			return ArchiveRuleService.preview(queryId);
		} catch (Exception e) {
			throw ERRORS.wrap(e, 'ArchiveController.previewRule');
		}
	}

	/** Runs a rule now for at most the typed count. */
	@AuraEnabled
	public static ArchiveRuleService.Panel runRule(Id queryId, Integer confirmedCount) {
		try {
			ArchiveRuleService.run(queryId, confirmedCount);
			return ArchiveRuleService.page();
		} catch (Exception e) {
			throw ERRORS.wrap(e, 'ArchiveController.runRule');
		}
	}
}
