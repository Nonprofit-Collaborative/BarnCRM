/**
 * Ana awards a scholarship, makes the letter, schedules two payments, holds the first until
 * enrollment is proven, marks it paid, exports it and starts next year's renewal (R-SG1, R-SG9 to
 * R-SG12). Staff cannot decide or mark paid.
 */
@IsTest(
	testFor='ApexClass:ScholarshipAwards, ApexClass:AwardPaymentRulesHandler, ApexTrigger:AwardPaymentTrigger'
)
private class ScholarshipAwardsTest {
	@TestSetup
	static void setup() {
		TestUsers.adminWith(ScholarshipsTestData.ADMIN_SET);
	}

	@IsTest
	static void anAwardGoesFromDecisionToPaidAndExported() {
		System.runAs(ScholarshipsTestData.admin()) {
			Award_Cycle__c cycle = ScholarshipsTestData.cycle(null, null);
			Contact lee = ScholarshipsTestData.person('Lee');
			Award_Application__c application = ScholarshipsTestData.application(
				cycle.Id,
				lee.Id,
				'In Review'
			);

			Test.startTest();
			Id awardId = ScholarshipAwards.decide(application.Id, true, 1000);
			Id letter = ScholarshipAwards.makeLetter(awardId);
			ScholarshipAwards.respond(awardId, true);
			Integer scheduled = ScholarshipAwards.buildSchedule(awardId, 3, Date.today(), 6);
			Test.stopTest();

			Assert.areEqual(
				'Awarded',
				[SELECT Status__c FROM Award_Application__c WHERE Id = :application.Id].Status__c,
				'Awarded'
			);
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM ContentDocumentLink
					WHERE LinkedEntityId = :awardId AND ContentDocumentId = :letter
				],
				'Letter filed on the award'
			);
			Award__c award = [
				SELECT Status__c, Accepted_Date__c, Scheduled_Amount__c, Letter_Sent_Date__c
				FROM Award__c
				WHERE Id = :awardId
			];
			Assert.areEqual('Active', award.Status__c, 'Accepted, then active once scheduled');
			Assert.areEqual(Date.today(), award.Letter_Sent_Date__c, 'Letter dated');
			Assert.areEqual(3, scheduled, 'Three payments');
			Assert.areEqual(
				1000,
				award.Scheduled_Amount__c,
				'The remainder lands on the last payment'
			);
			Assert.areEqual(
				5000 - 1000,
				[SELECT Remaining_Budget__c FROM Award_Cycle__c WHERE Id = :cycle.Id]
				.Remaining_Budget__c,
				'Budget left'
			);

			List<Award_Payment__c> payments = [
				SELECT Id, Amount__c
				FROM Award_Payment__c
				WHERE Award__c = :awardId
				ORDER BY Scheduled_Date__c
			];
			Assert.areEqual(333.34, payments[2].Amount__c, 'Last takes the cents');
			Award_Requirement__c condition = new Award_Requirement__c(
				Award__c = awardId,
				Name = 'Proof of enrollment',
				Type__c = 'Condition',
				Disbursement__c = payments[0].Id
			);
			insert condition;
			Assert.isTrue(ScholarshipAwards.payments(awardId)[0].held, 'Held back');
			Assert.isFalse(ScholarshipAwards.payments(awardId)[1].held, 'Others not');
			try {
				ScholarshipAwards.markPaid(payments[0].Id, null, 'Check', '1001');
				Assert.fail('Held back');
			} catch (DmlException expected) {
				Assert.isTrue(expected.getDmlMessage(0).length() > 0, 'Refused by the rule');
			}
			ScholarshipAwards.setRequirement(condition.Id, 'Met');
			ScholarshipAwards.markPaid(payments[0].Id, null, 'Check', '1001');
			Assert.areEqual(
				333.33,
				[SELECT Paid_Amount__c FROM Award__c WHERE Id = :awardId].Paid_Amount__c,
				'Paid'
			);

			List<ScholarshipAwards.Payment> exported = ScholarshipAwards.export(
				Date.today().addDays(-1),
				Date.today().addDays(1)
			);
			Assert.areEqual(1, exported.size(), 'Only the payment in range');
			Assert.areEqual('Lee', exported[0].recipient, 'With its recipient');
			Assert.areEqual(
				Date.today(),
				[SELECT Exported_Date__c FROM Award_Payment__c WHERE Id = :payments[0].Id]
				.Exported_Date__c,
				'Stamped'
			);
		}
	}

	@IsTest
	static void aConditionNamingNoPaymentHoldsThemAllAndDeclineDeclines() {
		System.runAs(ScholarshipsTestData.admin()) {
			Award_Cycle__c cycle = ScholarshipsTestData.cycle(null, null);
			Award_Application__c declined = ScholarshipsTestData.application(
				cycle.Id,
				null,
				'In Review'
			);
			Assert.isNull(ScholarshipAwards.decide(declined.Id, false, null), 'No award');
			Assert.areEqual(
				'Declined',
				[SELECT Status__c FROM Award_Application__c WHERE Id = :declined.Id].Status__c,
				'Declined'
			);
			Award__c award = ScholarshipsTestData.award(cycle.Id, null, null, 500);
			insert new Award_Requirement__c(
				Award__c = award.Id,
				Name = 'Signed agreement',
				Type__c = 'Condition'
			);
			List<Award_Payment__c> rows = new List<Award_Payment__c>();
			for (Integer i = 0; i < 200; i++) {
				rows.add(
					new Award_Payment__c(Award__c = award.Id, Amount__c = 1, Status__c = 'Paid')
				);
			}
			Test.startTest();
			List<Database.SaveResult> results = Database.insert(rows, false);
			Test.stopTest();
			for (Database.SaveResult result : results) {
				Assert.isFalse(result.isSuccess(), 'Every payment held back, in bulk');
			}
		}
	}

	@IsTest
	static void staffCannotDecideOrMarkPaid() {
		User staff = ScholarshipsTestData.staff('Staff');
		Award_Application__c application;
		Award_Payment__c payment;
		System.runAs(ScholarshipsTestData.admin()) {
			Award_Cycle__c cycle = ScholarshipsTestData.cycle(null, null);
			application = ScholarshipsTestData.application(cycle.Id, null, 'In Review');
			Award__c award = ScholarshipsTestData.award(cycle.Id, null, null, 500);
			payment = new Award_Payment__c(Award__c = award.Id, Amount__c = 500);
			insert payment;
		}
		System.runAs(staff) {
			try {
				ScholarshipAwards.decide(application.Id, true, 100);
				Assert.fail('Staff cannot decide');
			} catch (Scholarships.ScholarshipException expected) {
				Assert.isNotNull(expected.getMessage(), 'Refused in words');
			}
			try {
				ScholarshipAwards.markPaid(payment.Id, null, null, null);
				Assert.fail('Staff cannot mark paid');
			} catch (DmlException expected) {
				Assert.areEqual(
					BarnHelp.text('Scholarships', 'Scholarships_Error_NoPermission'),
					expected.getDmlMessage(0),
					'The rule'
				);
			}
		}
	}

	@IsTest
	static void aRenewableAwardStartsNextCyclesApplication() {
		System.runAs(ScholarshipsTestData.admin()) {
			Award_Cycle__c cycle = ScholarshipsTestData.cycle(null, null);
			Contact lee = ScholarshipsTestData.person('Lee');
			Award__c award = ScholarshipsTestData.award(cycle.Id, null, lee.Id, 500);
			try {
				ScholarshipAwards.startRenewal(award.Id);
				Assert.fail('No next cycle yet');
			} catch (Scholarships.ScholarshipException expected) {
				Assert.isNotNull(expected.getMessage(), 'Refused in words');
			}
			Award_Cycle__c next = new Award_Cycle__c(
				Name = '2028',
				Program__c = [SELECT Program__c FROM Award_Cycle__c WHERE Id = :cycle.Id]
				.Program__c,
				Status__c = 'Planned'
			);
			insert next;

			Test.startTest();
			Id renewalId = ScholarshipAwards.startRenewal(award.Id);
			Test.stopTest();

			Award_Application__c renewal = [
				SELECT Cycle__c, Contact__c, Status__c, Renewal_Of__c
				FROM Award_Application__c
				WHERE Id = :renewalId
			];
			Assert.areEqual(next.Id, renewal.Cycle__c, 'Next cycle');
			Assert.areEqual(lee.Id, renewal.Contact__c, 'Same recipient');
			Assert.areEqual('Draft', renewal.Status__c, 'Draft');
			Assert.areEqual(award.Id, renewal.Renewal_Of__c, 'Linked');
		}
	}
}
