/**
 * The Org Optimizer module's Settings rows: its thresholds and the Setup Changes retention sit
 * in their own Org Optimizer section, not under General, and the Health and Error Log rows
 * link out to Org Optimizer for an administrator.
 */
@IsTest(testFor='ApexClass:SettingsController')
private class OrgOptimizerSettingsTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	/** The console's keys by section, read as JSON so the test needs no Core model types. */
	private static Map<String, Set<String>> keysBySection() {
		Map<String, Object> model = (Map<String, Object>) JSON.deserializeUntyped(
			JSON.serialize(SettingsController.getConsoleModel())
		);
		Map<String, Set<String>> keys = new Map<String, Set<String>>();
		for (Object entry : (List<Object>) model.get('sections')) {
			Map<String, Object> section = (Map<String, Object>) entry;
			Set<String> inSection = new Set<String>();
			for (Object row : (List<Object>) section.get('settings')) {
				inSection.add((String) ((Map<String, Object>) row).get('key'));
			}
			keys.put((String) section.get('name'), inSection);
		}
		return keys;
	}

	@IsTest
	static void theThresholdsHaveTheirOwnSectionAndTheLinksShow() {
		System.runAs(TestUsers.admin()) {
			Test.startTest();
			Map<String, Set<String>> shown = keysBySection();
			Test.stopTest();

			Assert.areEqual(
				new Set<String>{
					'Stale_Record_Years__c',
					'Unused_Login_Days__c',
					'Unused_Report_Days__c',
					'Setup_Change_Retention_Days__c',
					'Field_Utilization_Retention_Days__c',
					'Old_Api_Version__c'
				},
				shown.get(SettingSections.ORG_OPTIMIZER),
				'The thresholds and the Setup Changes retention are under Org Optimizer'
			);
			Assert.isFalse(
				shown.get(SettingSections.GENERAL).contains('Unused_Login_Days__c'),
				'The thresholds do not show under General'
			);
			Set<String> all = new Set<String>();
			for (Set<String> inSection : shown.values()) {
				all.addAll(inSection);
			}
			Assert.isTrue(all.contains('Health_Check_Optimizer_Link'), 'Health links out');
			Assert.isTrue(all.contains('Error_Log_Optimizer_Link'), 'Error Log links out');
		}
	}
}
