/**
 * Maria installs the Migration package and can open the Migration Assistant straight away: she
 * and every BarnCRM Admin holder hold Migration Admin, and nothing in the install can fail it.
 */
@IsTest(testFor='ApexClass:MigrationPostInstall')
private class MigrationPostInstallTest {
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
			Id alreadyHolding = TestDataFactory.createUser('Holder', new List<String>{ 'Migration_Admin' }).Id;

			Test.startTest();
			Test.testInstall(new MigrationPostInstall(), null);
			System.enqueueJob(new ModuleAccessSyncs.Job(MigrationPostInstall.MODULE_KEY, fresh));
			System.enqueueJob(new ModuleAccessSyncs.Job(MigrationPostInstall.MODULE_KEY, alreadyHolding));
			Test.stopTest();

			Assert.areEqual(1, setsHeldBy(fresh, 'Migration_Admin'), 'The installer holds it');
			Assert.areEqual(1, setsHeldBy(alreadyHolding, 'Migration_Admin'), 'Never twice');
		}
	}

	@IsTest
	static void aMissingContextDoesNothingAndSetupNeverThrows() {
		System.runAs(TestUsers.admin()) {
			Test.startTest();
			new MigrationPostInstall().onInstall(null);
			new MigrationPostInstall().runSetup(null);
			Test.stopTest();

			Assert.isTrue(
				[SELECT COUNT() FROM PermissionSet WHERE Name = 'Migration_Admin' WITH SYSTEM_MODE] == 1,
				'The set ships with the package'
			);
		}
	}
}
