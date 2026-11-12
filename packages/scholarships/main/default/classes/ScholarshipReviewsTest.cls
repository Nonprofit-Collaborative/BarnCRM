/**
 * Ana's committee scores scholarship applications: the rubric's weighted score, each reviewer's
 * own review, recusal, and Assign Reviewers sharing the work evenly (R-SG4, R-SG6 to R-SG8).
 */
@IsTest(testFor='ApexClass:ScholarshipReviews')
private class ScholarshipReviewsTest {
	private static final String RUBRIC = '[{"key":"need","label":"Need","max":10,"weight":2},{"key":"essay","label":"Essay","max":10,"weight":1}]';

	@TestSetup
	static void setup() {
		TestUsers.adminWith(ScholarshipsTestData.ADMIN_SET);
	}

	@IsTest
	static void aRubricWeighsAndCapsScores() {
		// runs-as: deploying user (pure calculation, no records or permissions)
		List<ScholarshipReviews.Criterion> criteria = ScholarshipReviews.rubric(RUBRIC);
		Assert.areEqual(2, criteria.size(), 'Two criteria');
		Assert.areEqual(
			22,
			ScholarshipReviews.score(
				criteria,
				new Map<String, Object>{ 'need' => 8, 'essay' => '6' }
			),
			'8 x 2 + 6'
		);
		Assert.areEqual(
			20,
			ScholarshipReviews.score(
				criteria,
				new Map<String, Object>{ 'need' => 15, 'essay' => -3 }
			),
			'Capped at the max, never below 0'
		);
		Assert.areEqual(
			'overall',
			ScholarshipReviews.rubric('not json')[0].key,
			'Unreadable is one overall score'
		);
		Assert.areEqual(
			'overall',
			ScholarshipReviews.rubric(null)[0].key,
			'Blank is one overall score'
		);
	}

	@IsTest
	static void aReviewerSubmitsAndRecusesTheirOwnReview() {
		System.runAs(ScholarshipsTestData.admin()) {
			Award_Cycle__c cycle = ScholarshipsTestData.cycle(RUBRIC, null);
			Award_Application__c first = ScholarshipsTestData.application(
				cycle.Id,
				ScholarshipsTestData.person('Lee').Id,
				'Eligible'
			);
			Award_Application__c second = ScholarshipsTestData.application(
				cycle.Id,
				ScholarshipsTestData.person('Kim').Id,
				'Eligible'
			);

			Test.startTest();
			ScholarshipReviews.saveOwn(
				first.Id,
				new Map<String, Object>{ 'need' => 8, 'essay' => 6 },
				'Strong',
				'submit',
				null
			);
			ScholarshipReviews.saveOwn(second.Id, null, null, 'recuse', 'My niece');
			Test.stopTest();

			Award_Application__c scored = [
				SELECT Average_Score__c, Review_Count__c
				FROM Award_Application__c
				WHERE Id = :first.Id
			];
			Assert.areEqual(22, scored.Average_Score__c, 'Weighted score counts');
			Assert.areEqual(1, scored.Review_Count__c, 'One submitted');
			Assert.areEqual(
				ScholarshipReviews.RECUSED,
				ScholarshipReviews.own(second.Id).Status__c,
				'Recused'
			);
			try {
				ScholarshipReviews.saveOwn(second.Id, null, null, 'recuse', ' ');
				Assert.fail('A recusal needs a reason');
			} catch (Scholarships.ScholarshipException expected) {
				Assert.isNotNull(expected.getMessage(), 'Refused in words');
			}
		}
	}

	@IsTest
	static void assignReviewersBalancesTheLoadAndSkipsRecusals() {
		User admin = ScholarshipsTestData.admin();
		User reviewerA = ScholarshipsTestData.staff('ReviewerA');
		User reviewerB = ScholarshipsTestData.staff('ReviewerB');
		System.runAs(admin) {
			Group panel = new Group(
				Name = 'Test Panel',
				DeveloperName = 'Test_Scholarship_Panel',
				Type = 'Regular'
			);
			insert panel;
			insert new List<GroupMember>{
				new GroupMember(GroupId = panel.Id, UserOrGroupId = reviewerA.Id),
				new GroupMember(GroupId = panel.Id, UserOrGroupId = reviewerB.Id)
			};
		}
		System.runAs(admin) {
			Award_Cycle__c cycle = ScholarshipsTestData.cycle(null, null);
			cycle.Reviewer_Group__c = 'Test_Scholarship_Panel';
			update cycle;
			List<Award_Application__c> applications = new List<Award_Application__c>();
			for (Integer i = 0; i < 4; i++) {
				applications.add(ScholarshipsTestData.application(cycle.Id, null, 'Submitted'));
			}
			insert new Application_Review__c(
				Application__c = applications[0].Id,
				Reviewer__c = reviewerA.Id,
				Status__c = 'Recused',
				Recusal_Reason__c = 'Friend'
			);

			Test.startTest();
			Integer created = ScholarshipReviews.assign(cycle.Id);
			Test.stopTest();

			Assert.areEqual(4, created, 'One review for each application');
			Assert.areEqual(
				reviewerB.Id,
				[
					SELECT Reviewer__c
					FROM Application_Review__c
					WHERE Application__c = :applications[0].Id AND Status__c = 'Assigned'
				]
				.Reviewer__c,
				'Never the reviewer who recused'
			);
			Assert.areEqual(
				2,
				[
					SELECT COUNT()
					FROM Application_Review__c
					WHERE Reviewer__c = :reviewerA.Id AND Status__c = 'Assigned'
				],
				'Even load'
			);
			Assert.areEqual(
				4,
				[SELECT COUNT() FROM Award_Application__c WHERE Status__c = 'In Review'],
				'In Review'
			);
			Assert.areEqual(0, ScholarshipReviews.assign(cycle.Id), 'A second press adds nothing');
			Assert.isFalse(Scholarships.sentTitles.isEmpty(), 'Reviewers are told');
		}
	}

	@IsTest
	static void staffCannotAssignAndTheBoardRanksByScore() {
		User staff = ScholarshipsTestData.staff('Staff');
		Award_Cycle__c cycle;
		System.runAs(ScholarshipsTestData.admin()) {
			cycle = ScholarshipsTestData.cycle(null, null);
			Award_Application__c low = ScholarshipsTestData.application(
				cycle.Id,
				ScholarshipsTestData.person('Low').Id,
				'In Review'
			);
			Award_Application__c high = ScholarshipsTestData.application(
				cycle.Id,
				ScholarshipsTestData.person('High').Id,
				'In Review'
			);
			insert new List<Application_Review__c>{
				new Application_Review__c(
					Application__c = low.Id,
					Status__c = 'Submitted',
					Score__c = 4
				),
				new Application_Review__c(
					Application__c = high.Id,
					Status__c = 'Submitted',
					Score__c = 9
				)
			};
			List<ScholarshipReviews.BoardRow> rows = ScholarshipReviews.board(cycle.Id, true);
			Assert.areEqual(high.Id, rows[0].id, 'Highest first');
			Assert.areEqual(1, rows[0].rank, 'Ranked');
			Assert.isNull(rows[0].applicant, 'Blind hides the applicant');
			Assert.areEqual(
				'High',
				ScholarshipReviews.board(cycle.Id, false)[0].applicant,
				'Shown otherwise'
			);
		}
		System.runAs(staff) {
			try {
				ScholarshipReviews.assign(cycle.Id);
				Assert.fail('Staff cannot assign');
			} catch (Scholarships.ScholarshipException expected) {
				Assert.isNotNull(expected.getMessage(), 'Refused in words');
			}
		}
	}
}
