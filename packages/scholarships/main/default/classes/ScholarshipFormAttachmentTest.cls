/**
 * Lee applies through the cycle's form: the application is made with its eligibility, a second
 * submission updates it, a draft started in the portal is filled, and a recipient's report fills
 * its requirement (R-SG3, R-SG5).
 */
@IsTest(testFor='ApexClass:ScholarshipFormAttachment')
private class ScholarshipFormAttachmentTest {
	private static final String RULES = '[{"answer":"gpa","op":"atLeast","value":3},{"answer":"enrolled","op":"isTrue"}]';

	@TestSetup
	static void setup() {
		TestUsers.adminWith(ScholarshipsTestData.ADMIN_SET);
	}

	private static FormSubmissionReceipt receipt(
		Id contextId,
		Id personId,
		Map<String, Object> answers
	) {
		FormSubmissionReceipt receipt = new FormSubmissionReceipt();
		receipt.contextRecordId = contextId;
		receipt.personId = personId;
		receipt.answers = answers;
		return receipt;
	}

	@IsTest
	static void eligibilityRulesCheckEachOp() {
		// runs-as: deploying user (pure evaluation, no records or permissions)
		Map<String, Object> answers = new Map<String, Object>{
			'gpa' => 3.5,
			'enrolled' => 'Yes',
			'county' => 'Marion'
		};
		Assert.areEqual(0, ScholarshipFormAttachment.unmetRules(RULES, answers).size(), 'All met');
		List<String> unmet = ScholarshipFormAttachment.unmetRules(
			'[{"answer":"gpa","op":"atMost","value":3},{"answer":"county","op":"equals","value":"marion"},{"answer":"county","op":"notEquals","value":"Lake"},{"answer":"county","op":"contains","value":"ari"},{"answer":"x","op":"bogus"}]',
			answers
		);
		Assert.areEqual(2, unmet.size(), 'atMost and the unknown op fail');
		Assert.isNull(ScholarshipFormAttachment.unmetRules(null, answers), 'No rules');
		Assert.isNull(
			ScholarshipFormAttachment.unmetRules('{bad', answers),
			'Unreadable rules are ignored'
		);
	}

	@IsTest
	static void aSubmissionMakesThenUpdatesOneApplication() {
		System.runAs(ScholarshipsTestData.admin()) {
			Award_Cycle__c cycle = ScholarshipsTestData.cycle(null, RULES);
			Contact lee = ScholarshipsTestData.person('Lee');
			ScholarshipFormAttachment seam = new ScholarshipFormAttachment();
			Assert.isTrue(seam.handles(Award_Cycle__c.SObjectType), 'Cycles take a form');
			Assert.isFalse(seam.signedClaim(cycle.Id), 'A cycle link is public');
			Assert.isNull(seam.formFor(cycle.Id), 'No form named yet');

			Test.startTest();
			seam.received(
				receipt(
					cycle.Id,
					lee.Id,
					new Map<String, Object>{
						'gpa' => 2.5,
						'enrolled' => true,
						'purpose' => 'Tuition',
						'amountRequested' => '900'
					}
				)
			);
			seam.received(
				receipt(
					cycle.Id,
					lee.Id,
					new Map<String, Object>{ 'gpa' => 3.2, 'enrolled' => true }
				)
			);
			Test.stopTest();

			Award_Application__c row = [
				SELECT
					Status__c,
					Title__c,
					Amount_Requested__c,
					Eligibility_Notes__c,
					Submitted_Date__c,
					Answers__c
				FROM Award_Application__c
				WHERE Cycle__c = :cycle.Id
			];
			Assert.areEqual('Eligible', row.Status__c, 'The second answers meet the rules');
			Assert.areEqual('Tuition', row.Title__c, 'Purpose kept from the first');
			Assert.areEqual(900, row.Amount_Requested__c, 'Amount kept');
			Assert.isNull(row.Eligibility_Notes__c, 'No unmet rules now');
			Assert.isTrue(row.Answers__c.contains('3.2'), 'Answers kept');
		}
	}

	@IsTest
	static void aDraftIsFilledAndAReportFillsItsRequirement() {
		System.runAs(ScholarshipsTestData.admin()) {
			Award_Cycle__c cycle = ScholarshipsTestData.cycle(null, RULES);
			Contact lee = ScholarshipsTestData.person('Lee');
			Award_Application__c draft = ScholarshipsTestData.application(
				cycle.Id,
				lee.Id,
				'Draft'
			);
			Award__c award = ScholarshipsTestData.award(cycle.Id, draft.Id, lee.Id, 500);
			Award_Requirement__c report = new Award_Requirement__c(
				Award__c = award.Id,
				Name = 'Progress report',
				Type__c = 'Progress Report'
			);
			insert report;
			ScholarshipFormAttachment seam = new ScholarshipFormAttachment();
			Assert.isTrue(
				seam.signedClaim(draft.Id),
				'A person\'s own application needs a signed link'
			);

			Test.startTest();
			seam.received(receipt(draft.Id, null, new Map<String, Object>{ 'gpa' => 1 }));
			seam.received(
				receipt(
					report.Id,
					lee.Id,
					new Map<String, Object>{ 'progress' => 'Finished first year' }
				)
			);
			Test.stopTest();

			Award_Application__c filled = [
				SELECT Status__c, Contact__c, Eligibility_Notes__c
				FROM Award_Application__c
				WHERE Id = :draft.Id
			];
			Assert.areEqual('Ineligible', filled.Status__c, 'Rules checked');
			Assert.areEqual(lee.Id, filled.Contact__c, 'Still Lee');
			Assert.isTrue(filled.Eligibility_Notes__c.contains('gpa'), 'The unmet rule named');
			Award_Requirement__c sent = [
				SELECT Status__c, Response__c, Submitted_Date__c
				FROM Award_Requirement__c
				WHERE Id = :report.Id
			];
			Assert.areEqual('Submitted', sent.Status__c, 'Submitted');
			Assert.isTrue(sent.Response__c.contains('Finished first year'), 'Report kept');
		}
	}
}
