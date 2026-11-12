/**
 * BarnCRM Admin holders get Giving Admin (ADR-0194, simpler permission sets, D2), at install, at
 * Turn on and with the hourly access check; nobody else gets a Giving set from it.
 */
@IsTest(testFor='ApexClass:GivingAccessSync')
private class GivingAccessSyncTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static Map<String, Id> people() {
		Map<String, Id> ids = new Map<String, Id>{
			'Outsider' => TestUsers.standardUser('Outsider').Id
		};
		Map<String, String> groupByName = new Map<String, String>{
			'Member' => 'Program_Staff',
			'Reader' => 'Read_Only',
			'Boss' => 'BarnCRM_Admin_Group'
		};
		List<PermissionSetAssignment> roles = new List<PermissionSetAssignment>();
		for (String name : groupByName.keySet()) {
			Id userId = TestUsers.standardUser(name).Id;
			ids.put(name, userId);
			Id groupId = TestDataFactory.prepareRoleGroup(groupByName.get(name)).Id;
			roles.add(
				new PermissionSetAssignment(AssigneeId = userId, PermissionSetGroupId = groupId)
			);
		}
		Id direct = TestUsers.standardUserWith('Direct', new List<String>{ 'BarnCRM_Admin' }).Id;
		ids.put('Direct', direct);
		insert roles;
		return ids;
	}

	private static Set<String> setsOf(Id userId) {
		Set<String> names = new Set<String>();
		for (PermissionSetAssignment row : [
			SELECT PermissionSet.Name
			FROM PermissionSetAssignment
			WHERE AssigneeId = :userId AND PermissionSet.Name LIKE 'Giving_%'
			WITH SYSTEM_MODE
		]) {
			names.add(row.PermissionSet.Name);
		}
		return names;
	}

	@IsTest
	static void givesGivingAdminToBarnCrmAdminsOnly() {
		System.runAs(TestUsers.admin()) {
			Map<String, Id> ids = people();

			Test.startTest();
			Boolean more = GivingAccessSync.syncOnce();
			Boolean again = GivingAccessSync.syncOnce();
			Test.stopTest();

			Assert.isFalse(more, 'A small org is done in one pass');
			Assert.isFalse(again, 'And a second pass finds nothing to give');
			Set<String> admin = new Set<String>{ GivingAccessSync.ADMIN_SET };
			Assert.areEqual(admin, setsOf(ids.get('Boss')), 'The role holder gets Giving Admin');
			Assert.areEqual(admin, setsOf(ids.get('Direct')), 'So does a direct set holder');
			for (String name : new List<String>{ 'Member', 'Reader', 'Outsider' }) {
				Assert.isTrue(setsOf(ids.get(name)).isEmpty(), name + ' gets no Giving set');
			}
		}
	}

	@IsTest
	static void theHourlyAccessCheckQueuesTheSync() {
		System.runAs(TestUsers.admin()) {
			Map<String, Id> ids = people();

			Test.startTest();
			ModuleAccessSyncs.requestAll();
			Test.stopTest();

			Assert.isTrue(
				setsOf(ids.get('Boss')).contains(GivingAccessSync.ADMIN_SET),
				'An admin given the role since the install gets Giving Admin within the hour'
			);
		}
	}
}
