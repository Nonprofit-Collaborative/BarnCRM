/**
 * The rollup kits' check (MIG-01, MIG-08): it counts the other tool's active rollups and the
 * ones whose BarnCRM copy is on, DLRS and NPSP apart. Organizations total their child
 * organizations, as in `RollupDlrsImportTest`.
 */
@IsTest(testFor='ApexClass:RollupsMigrationKit')
private class RollupsMigrationKitTest {
	private static final String COUNT_FIELD = 'Member_Count__c';

	@TestSetup
	static void createTestUser() {
		System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
			TestDataFactory.createUser(
				'Maria',
				new List<String>{ 'BarnCRM_Admin', 'Rollup_Builder_Admin' }
			);
		}
	}

	private static User maria() {
		return TestUsers.fromSetup('Maria');
	}

	@IsTest
	static void theCheckAgreesOnlyOnceTheCopyIsOn() {
		System.runAs(maria()) {
			RollupDlrsFake.use(
				new List<RollupDlrs.Definition>{ RollupDlrsFake.activeOn('Account', COUNT_FIELD) }
			);
			RollupsMigrationKit kit = new RollupsMigrationKit();
			Assert.isNull(kit.rows('copy', new List<SObject>()), 'No rows: the step is a tool');

			MigrationCheck before = kit.verify('copy');
			Assert.areEqual(1, before.source, 'One active DLRS rollup');
			Assert.areEqual(0, before.done, 'No copy yet');

			Id copyId = RollupDlrsImport.importRollups(new List<String>{ 'Child_Count' }, null)[0]
				.recordId;
			Assert.areEqual(0, kit.verify('copy').done, 'A copy that is off does not count');

			RollupDlrsImport.turnOn(copyId, true);
			MigrationCheck after = kit.verify('copy');
			Assert.areEqual(1, after.done, 'The copy is on');
			Assert.areEqual(0, kit.verify(RollupsMigrationKit.NPSP_STEP).source, 'NPSP apart');
		}
	}

	@IsTest
	static void theShippedKitsReadAndNameThisCheck() {
		System.runAs(maria()) {
			Map<String, String> stepByKit = new Map<String, String>{
				'DLRS_Rollups' => 'copy',
				'NPSP_Rollups' => RollupsMigrationKit.NPSP_STEP
			};
			List<Migration_Kit__mdt> kits = [
				SELECT DeveloperName, Steps_JSON__c, Retire_Checklist_JSON__c, Extension_Class__c
				FROM Migration_Kit__mdt
				WHERE DeveloperName IN :stepByKit.keySet()
				WITH SYSTEM_MODE
			];
			Assert.areEqual(2, kits.size(), 'Both kits ship');
			for (Migration_Kit__mdt kit : kits) {
				List<Object> steps = (List<Object>) JSON.deserializeUntyped(kit.Steps_JSON__c);
				Map<String, Object> step = (Map<String, Object>) steps[0];
				Assert.areEqual(stepByKit.get(kit.DeveloperName), step.get('key'), 'Its step');
				Assert.areEqual('tool', step.get('kind'), 'Done in the Rollup Builder');
				Assert.isFalse(
					((List<Object>) JSON.deserializeUntyped(kit.Retire_Checklist_JSON__c))
						.isEmpty(),
					'A retire checklist'
				);
				Assert.isTrue(
					Type.forName(kit.Extension_Class__c)
						.newInstance() instanceof MigrationKitExtension,
					'Names this check'
				);
			}
		}
	}
}
