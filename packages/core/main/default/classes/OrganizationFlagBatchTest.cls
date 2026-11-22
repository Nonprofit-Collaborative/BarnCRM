/**
 * `Account.Is_Organization_Account__c` is kept by BarnCRM (canonical model R-O4; ADR-0238 settings as
 * custom metadata, decision 8): set on each save from the organization record type, and put
 * right on every account that disagrees by OrganizationFlagBatch.
 */
@IsTest(testFor='ApexClass:OrganizationFlagBatch')
private class OrganizationFlagBatchTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	@IsTest
	static void aSavedAccountCarriesTheFlagOfItsRecordType() {
		System.runAs(TestUsers.admin()) {
			Account organization = AddressTestDataFactory.newOrganization('Zztest Flag Org');
			Account household = HouseholdTestDataFactory.newHousehold('The Zztest Flag Family');
			Database.insert(new List<Account>{ organization, household }, AccessLevel.SYSTEM_MODE);

			Map<Id, Account> read = new Map<Id, Account>(
				[
					SELECT Id, RecordTypeId, Is_Organization_Account__c
					FROM Account
					WHERE Id IN :new List<Id>{ organization.Id, household.Id }
					WITH SYSTEM_MODE
				]
			);
			Assert.areEqual(
				AccountKinds.isOrganization(read.get(organization.Id).RecordTypeId),
				read.get(organization.Id).Is_Organization_Account__c,
				'The flag follows the resolver on insert.'
			);
			Assert.isFalse(read.get(household.Id).Is_Organization_Account__c, 'A household never is.');

			// A hand edit is put back on the next save.
			Account edited = new Account(Id = household.Id, Is_Organization_Account__c = true);
			Database.update(edited, AccessLevel.SYSTEM_MODE);
			Assert.isFalse(
				[SELECT Is_Organization_Account__c FROM Account WHERE Id = :household.Id WITH SYSTEM_MODE]
				.Is_Organization_Account__c,
				'The flag is not a field anyone sets by hand.'
			);
		}
	}

	@IsTest
	static void theBatchPutsRightEveryAccountThatDisagrees() {
		System.runAs(TestUsers.admin()) {
			List<Account> accounts = new List<Account>();
			for (Integer i = 0; i < 200; i++) {
				accounts.add(HouseholdTestDataFactory.newHousehold('The Zztest Batch ' + i + ' Family'));
			}
			// Saved with the account trigger off, as an org upgraded from the formula field holds
			// them: every flag wrong.
			AutomationControl.bypass('AccountTriggerHandler');
			for (Account record : accounts) {
				record.Is_Organization_Account__c = true;
			}
			Database.insert(accounts, AccessLevel.SYSTEM_MODE);
			AutomationControl.clearBypass('AccountTriggerHandler');

			OrganizationFlagBatch.runInTests = true;
			Test.startTest();
			Id jobId = OrganizationFlagBatch.run();
			Test.stopTest();

			Assert.isNotNull(jobId, 'The run started.');
			Assert.areEqual(
				0,
				[
					SELECT COUNT()
					FROM Account
					WHERE Id IN :accounts AND Is_Organization_Account__c = TRUE
					WITH SYSTEM_MODE
				],
				'Every household is put right.'
			);
		}
	}

	@IsTest
	static void noRunStartsInATestThatDidNotAskForOne() {
		System.runAs(TestUsers.admin()) {
			Assert.isNull(OrganizationFlagBatch.run(), 'Other tests are not handed a batch.');
		}
	}
}
