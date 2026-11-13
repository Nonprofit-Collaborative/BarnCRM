/**
 * Maria installs Address Verification and can open its setup page straight away: she holds
 * Address Verification Admin, BarnCRM Admin holders get it too, it is never given twice, and a
 * refused grant is logged without failing the install.
 */
@IsTest(testFor='ApexClass:AddressVerificationPostInstall')
private class AddressVerificationPostInstallTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static Integer adminSetsHeldBy(Id userId) {
		return [
			SELECT COUNT()
			FROM PermissionSetAssignment
			WHERE AssigneeId = :userId AND PermissionSet.Name = 'Address_Verification_Admin'
			WITH SYSTEM_MODE
		];
	}

	@IsTest
	static void theInstallerAndBarnCrmAdminsGetTheAdminSetOnce() {
		System.runAs(TestUsers.admin()) {
			Id fresh = TestDataFactory.createUser('Installer', new List<String>()).Id;
			Id holding = TestDataFactory.createUser(
					'Holder',
					new List<String>{ 'Address_Verification_Admin' }
				)
				.Id;
			User boss = TestUsers.standardUser('Boss');
			insert new PermissionSetAssignment(
				AssigneeId = boss.Id,
				PermissionSetGroupId = TestDataFactory.prepareRoleGroup('BarnCRM_Admin_Group').Id
			);

			Test.startTest();
			Test.testInstall(new AddressVerificationPostInstall(), null);
			System.enqueueJob(new ModuleAccessSyncs.Job('AddressVerification', fresh));
			System.enqueueJob(new ModuleAccessSyncs.Job('AddressVerification', holding));
			Test.stopTest();

			Assert.areEqual(1, adminSetsHeldBy(fresh), 'The installer holds the admin set');
			Assert.areEqual(1, adminSetsHeldBy(holding), 'Never given twice');
			Assert.areEqual(1, adminSetsHeldBy(boss.Id), 'A BarnCRM Admin holder gets it');
			Assert.isFalse(
				ModuleAccessSyncs.syncOnce('AddressVerification'),
				'Nothing left to give'
			);
		}
	}

	@IsTest
	static void aRefusedGrantIsLoggedAndNeverFailsTheInstall() {
		System.runAs(TestUsers.admin()) {
			Id notAUser = TestUsers.admin().ProfileId;

			Test.startTest();
			new AddressVerificationPostInstall().onInstall(null);
			new AddressVerificationPostInstall().runSetup(null);
			System.enqueueJob(new ModuleAccessSyncs.Job('AddressVerification', notAUser));
			Test.stopTest();

			Assert.isTrue(
				[
					SELECT COUNT()
					FROM Error_Log__c
					WHERE Context__c = 'AddressVerificationPostInstall.grantInstallerAccess'
					WITH SYSTEM_MODE
				] >= 1,
				'The refusal is in the Error Log'
			);
		}
	}
}
