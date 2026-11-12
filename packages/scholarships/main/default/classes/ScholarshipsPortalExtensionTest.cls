/**
 * Lee, signed in to the applicant portal, applies to an open cycle once, withdraws, and accepts an
 * offered award; nobody acts on someone else's records (PB-06).
 */
@IsTest(testFor='ApexClass:ScholarshipsPortalExtension')
private class ScholarshipsPortalExtensionTest {
	@TestSetup
	static void setup() {
		TestUsers.adminWith(ScholarshipsTestData.ADMIN_SET);
	}

	@IsTest
	static void applyWithdrawAndAccept() {
		System.runAs(ScholarshipsTestData.admin()) {
			Award_Cycle__c cycle = ScholarshipsTestData.cycle(null, null);
			Contact lee = ScholarshipsTestData.person('Lee');
			Contact kim = ScholarshipsTestData.person('Kim');
			ScholarshipsPortalExtension actions = new ScholarshipsPortalExtension();
			Assert.isTrue(
				actions.actionNames().contains(ScholarshipsPortalExtension.APPLY),
				'Apply offered'
			);

			Test.startTest();
			String applied = actions.run(ScholarshipsPortalExtension.APPLY, lee.Id, cycle.Id);
			String again = actions.run(ScholarshipsPortalExtension.APPLY, lee.Id, cycle.Id);
			Test.stopTest();

			Assert.areEqual(
				BarnHelp.text('Scholarships', 'Scholarships_Portal_Applied'),
				applied,
				'Applied'
			);
			Assert.areEqual(
				BarnHelp.text('Scholarships', 'Scholarships_Portal_AlreadyApplied'),
				again,
				'Once only'
			);
			Award_Application__c draft = [
				SELECT Id, Status__c
				FROM Award_Application__c
				WHERE Contact__c = :lee.Id
			];
			Assert.areEqual('Draft', draft.Status__c, 'A draft');
			try {
				actions.run(ScholarshipsPortalExtension.WITHDRAW, kim.Id, draft.Id);
				Assert.fail('Not Kim\'s');
			} catch (QueryException expected) {
				Assert.isNotNull(expected.getMessage(), 'Refused');
			}
			actions.run(ScholarshipsPortalExtension.WITHDRAW, lee.Id, draft.Id);
			Assert.areEqual(
				'Withdrawn',
				[SELECT Status__c FROM Award_Application__c WHERE Id = :draft.Id].Status__c,
				'Withdrawn'
			);

			Award__c award = ScholarshipsTestData.award(cycle.Id, null, lee.Id, 500);
			award.Status__c = 'Offered';
			update award;
			actions.run(ScholarshipsPortalExtension.ACCEPT, lee.Id, award.Id);
			Assert.areEqual(
				'Accepted',
				[SELECT Status__c FROM Award__c WHERE Id = :award.Id].Status__c,
				'Accepted'
			);
			Assert.areEqual(
				BarnHelp.text('Scholarships', 'Scholarships_Award_NotOffered'),
				actions.run(ScholarshipsPortalExtension.ACCEPT, lee.Id, award.Id),
				'Only once'
			);

			cycle.Status__c = 'Closed';
			update cycle;
			Assert.areEqual(
				BarnHelp.text('Scholarships', 'Scholarships_Portal_Closed'),
				actions.run(ScholarshipsPortalExtension.APPLY, kim.Id, cycle.Id),
				'Closed'
			);
		}
	}
}
