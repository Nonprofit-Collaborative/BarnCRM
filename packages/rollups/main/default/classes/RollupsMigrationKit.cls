/**
 * The rollup Migration Kits' own check (MIG-01, MIG-08, canonical model R-MR3), named by the
 * kits `DLRS_Rollups` and `NPSP_Rollups`: how many active rollups the other tool has, and how
 * many of them have a BarnCRM copy that is on. Their one step is done in the Rollup Builder,
 * so there are no rows to stage.
 */
public with sharing class RollupsMigrationKit implements MigrationKitExtension {
	/** The NPSP kit's step; any other step checks DLRS. */
	@TestVisible
	private static final String NPSP_STEP = 'copy_npsp';

	public List<Map<String, Object>> rows(String stepKey, List<SObject> records) {
		return null;
	}

	public MigrationCheck verify(String stepKey) {
		Set<String> keys = new Set<String>();
		for (RollupDlrs.Definition other : RollupDlrs.definitions(stepKey == NPSP_STEP)) {
			if (other.active == true) {
				keys.add(RollupDlrsImport.definitionKey(other).toLowerCase());
			}
		}
		Integer done = 0;
		for (Rollup_Definition__c copy : RollupSelector.selectAllAsUser()) {
			if (
				copy.Active__c == true &&
				copy.Definition_Key__c != null &&
				keys.contains(copy.Definition_Key__c.toLowerCase())
			) {
				done++;
			}
		}
		return new MigrationCheck(keys.size(), done);
	}
}
