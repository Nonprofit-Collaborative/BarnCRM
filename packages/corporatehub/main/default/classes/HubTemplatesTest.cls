/**
 * The shipped templates arrive once each, obligations Off and policies Draft, and a template the
 * org deleted comes back only when someone adds the missing ones again (R-CT1).
 */
@IsTest(testFor='ApexClass:HubTemplates')
private class HubTemplatesTest {
	private static final String ADMIN_SET = 'Corporate_Hub_Admin';

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(ADMIN_SET);
	}

	@IsTest
	static void theShippedSetLoadsOnceWithEveryNoteAndNothingSwitchedOn() {
		System.runAs(TestUsers.adminWith(ADMIN_SET)) {
			Integer loaded = HubTemplates.loadMissing(null, false);
			Integer again = HubTemplates.loadMissing(null, false);

			List<Compliance_Obligation__c> obligations = [
				SELECT Status__c, Template_Key__c, Instructions__c, OwnerId
				FROM Compliance_Obligation__c
				WITH USER_MODE
			];
			List<Hub_Document__c> policies = [
				SELECT Status__c, Template_Key__c, Summary__c, Requires_Acknowledgment__c
				FROM Hub_Document__c
				WITH USER_MODE
			];
			Assert.areEqual(10, loaded, 'Six obligations and four policies');
			Assert.areEqual(0, again, 'Never twice');
			Assert.areEqual(6, obligations.size(), 'Six obligations');
			Assert.areEqual(4, policies.size(), 'Four policies');
			for (Compliance_Obligation__c row : obligations) {
				Assert.areEqual('Off', row.Status__c, row.Template_Key__c + ' arrives Off');
				Assert.isTrue(
					row.Instructions__c.containsIgnoreCase('not legal advice'),
					row.Template_Key__c
				);
				Assert.areEqual(UserInfo.getUserId(), row.OwnerId, 'Owned by whoever added it');
			}
			Integer needsAcknowledgment = 0;
			for (Hub_Document__c row : policies) {
				Assert.areEqual('Draft', row.Status__c, row.Template_Key__c + ' arrives Draft');
				Assert.isTrue(
					row.Summary__c.containsIgnoreCase('not legal advice'),
					row.Template_Key__c
				);
				needsAcknowledgment += row.Requires_Acknowledgment__c ? 1 : 0;
			}
			Assert.areEqual(2, needsAcknowledgment, 'Conflict of interest and whistleblower');
		}
	}

	@IsTest
	static void aDeletedTemplateComesBackAndAnOwnerCanBeGiven() {
		HubTemplates.bodyOverride =
			'{"obligations":[{"key":"test_filing","name":"Test filing","recurrence":"Yearly"}],' +
			'"policies":[{"key":"test_policy","name":"Test policy","requiresAcknowledgment":true,"reviewMonths":24}]}';
		User installer = TestUsers.adminWith(ADMIN_SET);
		System.runAs(installer) {
			Assert.areEqual(2, HubTemplates.loadMissing(installer.Id, true), 'Both');
			delete [SELECT Id FROM Compliance_Obligation__c WITH USER_MODE];

			Assert.areEqual(1, HubTemplates.loadMissing(null, false), 'Only the deleted one');
			Hub_Document__c policy = [
				SELECT Review_Months__c, Requires_Acknowledgment__c, OwnerId, Type__c
				FROM Hub_Document__c
				WHERE Template_Key__c = 'test_policy'
				WITH USER_MODE
			];
			Assert.areEqual(24, policy.Review_Months__c, 'From the template');
			Assert.isTrue(policy.Requires_Acknowledgment__c, 'From the template');
			Assert.areEqual('Policy', policy.Type__c, 'A policy');
			Assert.areEqual(installer.Id, policy.OwnerId, 'The installer');
		}
	}
}
