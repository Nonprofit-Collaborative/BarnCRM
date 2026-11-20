/**
 * Maria installs the Org Optimizer package and can open Org Optimizer straight away: she and
 * every BarnCRM Admin holder hold Org Optimizer Admin, and nothing in the install can fail it.
 */
@IsTest(testFor='ApexClass:OrgOptimizerPostInstall')
private class OrgOptimizerPostInstallTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static Integer setsHeldBy(Id userId, String setName) {
		return [
			SELECT COUNT()
			FROM PermissionSetAssignment
			WHERE AssigneeId = :userId AND PermissionSet.Name = :setName
			WITH SYSTEM_MODE
		];
	}

	@IsTest
	static void theInstallerGetsTheAdminSetOnce() {
		System.runAs(TestUsers.admin()) {
			Id fresh = TestDataFactory.createUser('Installer', new List<String>()).Id;
			Id alreadyHolding = TestDataFactory.createUser('Holder', new List<String>{ 'Org_Optimizer_Admin' }).Id;

			Test.startTest();
			Test.testInstall(new OrgOptimizerPostInstall(), null);
			System.enqueueJob(new ModuleAccessSyncs.Job(OrgOptimizerPostInstall.MODULE_KEY, fresh));
			System.enqueueJob(new ModuleAccessSyncs.Job(OrgOptimizerPostInstall.MODULE_KEY, alreadyHolding));
			Test.stopTest();

			Assert.areEqual(1, setsHeldBy(fresh, 'Org_Optimizer_Admin'), 'The installer holds it');
			Assert.areEqual(1, setsHeldBy(alreadyHolding, 'Org_Optimizer_Admin'), 'Never twice');
		}
	}

	@IsTest
	static void aMissingContextDoesNothingAndSetupNeverThrows() {
		System.runAs(TestUsers.admin()) {
			Test.startTest();
			new OrgOptimizerPostInstall().onInstall(null);
			new OrgOptimizerPostInstall().runSetup(null);
			Test.stopTest();

			Assert.areEqual(
				2,
				[
					SELECT COUNT()
					FROM PermissionSet
					WHERE Name IN ('Org_Optimizer_Admin', 'Org_Optimizer')
					WITH SYSTEM_MODE
				],
				'Both sets ship with the package'
			);
		}
	}
}
