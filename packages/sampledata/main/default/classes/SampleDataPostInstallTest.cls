/**
 * Maria installs the Sample Data package and can load the sample set straight away: she holds
 * Sample Data, nothing in the install can fail it, and Core finds the package's host by name.
 */
@IsTest(testFor='ApexClass:SampleDataPostInstall, ApexClass:SampleDataPackageHost')
private class SampleDataPostInstallTest {
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
	static void theInstallerGetsTheSetOnce() {
		System.runAs(TestUsers.admin()) {
			Id fresh = TestDataFactory.createUser('Installer', new List<String>()).Id;
			Id alreadyHolding = TestDataFactory.createUser('Holder', new List<String>{ 'Sample_Data' }).Id;

			Test.startTest();
			Test.testInstall(new SampleDataPostInstall(), null);
			System.enqueueJob(new ModuleAccessSyncs.Job(SampleDataPostInstall.MODULE_KEY, fresh));
			System.enqueueJob(new ModuleAccessSyncs.Job(SampleDataPostInstall.MODULE_KEY, alreadyHolding));
			Test.stopTest();

			Assert.areEqual(1, setsHeldBy(fresh, 'Sample_Data'), 'The installer holds it');
			Assert.areEqual(1, setsHeldBy(alreadyHolding, 'Sample_Data'), 'Never twice');
		}
	}

	@IsTest
	static void aMissingContextDoesNothingAndSetupNeverThrows() {
		System.runAs(TestUsers.admin()) {
			Test.startTest();
			new SampleDataPostInstall().onInstall(null);
			new SampleDataPostInstall().runSetup(null);
			Test.stopTest();

			Assert.areEqual(
				1,
				[SELECT COUNT() FROM PermissionSet WHERE Name = 'Sample_Data' WITH SYSTEM_MODE],
				'The set ships with the package'
			);
		}
	}

	@IsTest
	static void coreFindsThePackageHost() {
		System.runAs(TestUsers.admin()) {
			SampleDataHost host = SampleDataModules.host();

			Assert.isTrue(host instanceof SampleDataPackageHost, 'The catalog row names this package\'s host');
			Assert.isTrue(host.coreRemoveStages() instanceof SampleDataRemoveStages, 'Core\'s removal stages');
		}
	}

	@IsTest
	static void theHostLoadsTheSampleSetAndTellsTheLoaderWhenItIsIn() {
		System.runAs(TestUsers.adminWithInstalledModules()) {
			insert new BarnCRM_Settings__c(SetupOwnerId = UserInfo.getOrganizationId(), Job_Notifications__c = true);
			SettingsService.clearCaches();
			SampleDataHost host = new SampleDataPackageHost();

			Test.startTest();
			host.load();
			Test.stopTest();

			Assert.isTrue(SampleDataLoader.status().householdCount > 0, 'The host started the load, households are in');

			host.notifyLoadFinished();

			List<JobNotifier.Notice> sent = JobNotifier.sentNotices();
			Assert.areEqual(1, sent.size(), 'One notice when the load is in');
			Assert.areEqual(UserInfo.getUserId(), sent[0].recipientId, 'To the person who loaded it');
		}
	}
}
