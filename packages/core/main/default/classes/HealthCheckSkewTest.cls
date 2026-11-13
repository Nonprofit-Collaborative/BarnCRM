/**
 * Ownership skew (D-200 P12): a user with a role who owns more than the threshold of an
 * object's records is named; one without a role, or under the threshold, is not.
 */
@IsTest(testFor='ApexClass:HealthCheckSkew, ApexClass:HealthCheckService')
private class HealthCheckSkewTest {
	@TestSetup
	static void createTestUser() {
		User admin = TestUsers.admin();
		System.runAs(new User(Id = UserInfo.getUserId())) {
			// Built by name so the package does not compile against the role object (ADR-0013).
			SObject role = Schema.getGlobalDescribe().get('User' + 'Role').newSObject();
			role.put('Name', 'Skew Test Role');
			role.put('DeveloperName', 'Skew_Test_Role');
			insert as system role;
			update as system new User(Id = admin.Id, UserRoleId = role.Id);
		}
	}

	@IsTest
	static void anOwnerWithARolePastTheThresholdIsNamed() {
		System.runAs(TestUsers.admin()) {
			HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
			HouseholdTestDataFactory.insertHouseholds('Skewed', 3);
			HealthCheckSkew.skewAt = 2;

			HealthCheckService.Finding finding = new HealthCheckSkew.HouseholdOwnershipCheck()
				.run();

			Assert.isNotNull(finding, 'Three households past a threshold of two');
			Assert.areEqual('household_ownership_skew', finding.key);
			Assert.isTrue(
				finding.detail.contains(UserInfo.getName()),
				'The owner is named: ' + finding.detail
			);
		}
	}

	@IsTest
	static void underTheThresholdNothingIsSaid() {
		System.runAs(TestUsers.admin()) {
			HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
			HouseholdTestDataFactory.insertHouseholds('Fine', 3);
			HealthCheckSkew.skewAt = 3;

			Assert.isNull(
				new HealthCheckSkew.HouseholdOwnershipCheck().run(),
				'Three households is not more than three'
			);
		}
	}

	/** The owner seen most in the sample is counted first, whatever order the User query has. */
	@IsTest
	static void theMostSampledOwnersAreCountedFirst() {
		User admin = TestUsers.admin();
		User other;
		User noRole;
		System.runAs(new User(Id = UserInfo.getUserId())) {
			Id roleId = [SELECT UserRoleId FROM User WHERE Id = :admin.Id WITH SYSTEM_MODE]
			.UserRoleId;
			other = TestDataFactory.createUser('SkewOther', new List<String>());
			update as system new User(Id = other.Id, UserRoleId = roleId);
			noRole = TestDataFactory.createUser('SkewNoRole', new List<String>());
		}
		System.runAs(admin) {
			List<User> first = HealthCheckSkew.byMostSampled(
				new Map<Id, Integer>{ admin.Id => 2, other.Id => 9, noRole.Id => 50 }
			);
			List<User> second = HealthCheckSkew.byMostSampled(
				new Map<Id, Integer>{ admin.Id => 9, other.Id => 2 }
			);

			Assert.areEqual(2, first.size(), 'Only owners with a role: ' + first);
			Assert.areEqual(other.Id, first[0].Id, 'The most sampled owner first.');
			Assert.areEqual(admin.Id, second[0].Id, 'Whichever owner that is.');
		}
	}
}
