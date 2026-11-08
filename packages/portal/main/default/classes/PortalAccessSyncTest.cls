/**
 * BarnCRM Admin holders get Portal Builder Admin (ADR-0185
 * `0185-portal-builder-off-platform-portal-api.md`, decision 10), at install, at Turn on and with
 * the hourly access check; nobody else does, and nobody gets the integration set.
 */
@IsTest(testFor='ApexClass:PortalAccessSync')
private class PortalAccessSyncTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
		TestUsers.standardUser('Boss');
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
	static void givesBarnCrmAdminsTheSetAndNobodyElse() {
		System.runAs(TestUsers.admin()) {
			Id boss = TestUsers.standardUser('Boss').Id;
			insert new PermissionSetAssignment(
				AssigneeId = boss,
				PermissionSetGroupId = TestDataFactory.prepareRoleGroup('BarnCRM_Admin_Group').Id
			);
			Id member = TestUsers.standardUser('Member').Id;
			insert new PermissionSetAssignment(
				AssigneeId = member,
				PermissionSetGroupId = TestDataFactory.prepareRoleGroup('Program_Staff').Id
			);

			Test.startTest();
			Boolean more = PortalAccessSync.syncOnce();
			Boolean again = PortalAccessSync.syncOnce();
			Test.stopTest();

			Assert.isFalse(more, 'A small org is done in one pass');
			Assert.isFalse(again, 'And a second pass finds nothing to give');
			Assert.areEqual(1, setsHeldBy(boss, PortalAccessSync.ADMIN_SET), 'Admins hold it');
			Assert.areEqual(0, setsHeldBy(member, PortalAccessSync.ADMIN_SET), 'Staff do not');
			Assert.areEqual(
				0,
				setsHeldBy(boss, 'Portal_Integration'),
				'The integration set is never given automatically'
			);
		}
	}

	@IsTest
	static void theHourlyAccessCheckQueuesTheSync() {
		System.runAs(TestUsers.admin()) {
			Id boss = TestUsers.standardUser('Boss').Id;
			insert new PermissionSetAssignment(
				AssigneeId = boss,
				PermissionSetGroupId = TestDataFactory.prepareRoleGroup('BarnCRM_Admin_Group').Id
			);

			Test.startTest();
			ModuleAccessSyncs.requestAll();
			Test.stopTest();

			Assert.areEqual(
				1,
				setsHeldBy(boss, PortalAccessSync.ADMIN_SET),
				'Given within the hour'
			);
		}
	}
}
