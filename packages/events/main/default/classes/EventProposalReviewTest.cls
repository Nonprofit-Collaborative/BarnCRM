/**
 * Dana runs the community conference's call for speakers with weighted criteria: she sets
 * Relevance (weight 2) and Clarity (weight 1), names a co-presenter, assigns Lee to review, Lee
 * scores each criterion, and accepting the proposal makes both people speakers (EV-21, R-SA6 to
 * R-SA9, R-PP1). The weighted cases are the ones `eventApplicationsModel` checks in Jest.
 */
@IsTest(testFor='ApexClass:EventProposalReview, ApexClass:EventApplicationsController')
private class EventProposalReviewTest {
	private static final String CRITERIA = '[{"label":"Relevance","weight":2},{"label":"Clarity","weight":1}]';

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	private static User staff() {
		return TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	private static Contact person(String lastName) {
		Contact record = TestDataFactory.person(
			new Contact(FirstName = 'Ana', LastName = lastName)
		);
		insert as user record;
		return record;
	}

	private static Speaker_Application__c proposal() {
		Datetime start = Datetime.now().addDays(30);
		Event__c event = new Event__c(
			Name = 'Community Dreamin',
			Status__c = 'Open',
			Format__c = 'In Person',
			Start__c = start,
			End__c = start.addHours(8)
		);
		insert as user event;
		Speaker_Application__c record = new Speaker_Application__c(
			Event__c = event.Id,
			Contact__c = person('Garcia').Id,
			Name = 'Scaling Flows',
			Abstract__c = 'A talk'
		);
		insert as user record;
		return record;
	}

	@IsTest
	static void weighsCriteriaLikeTheBrowser() {
		System.runAs(staff()) {
			weighsCriteria();
		}
	}

	private static void weighsCriteria() {
		List<EventProposalReview.Criterion> criteria = EventProposalReview.validated(CRITERIA);
		Assert.areEqual(
			4.00,
			EventProposalReview.weightedScore(
				criteria,
				new Map<String, Object>{ 'Relevance' => 5, 'Clarity' => 2 }
			)
		);
		Assert.areEqual(
			4.33,
			EventProposalReview.weightedScore(
				criteria,
				new Map<String, Object>{ 'Relevance' => 4, 'Clarity' => 5 }
			)
		);
		Assert.areEqual(
			2.67,
			EventProposalReview.weightedScore(
				criteria,
				new Map<String, Object>{ 'Relevance' => 3, 'Clarity' => 2 }
			)
		);
		for (
			Map<String, Object> bad : new List<Map<String, Object>>{
				new Map<String, Object>{ 'Relevance' => 5 },
				new Map<String, Object>{ 'Relevance' => 6, 'Clarity' => 1 }
			}
		) {
			Boolean refused = false;
			try {
				EventProposalReview.weightedScore(criteria, bad);
			} catch (IllegalArgumentException e) {
				refused = true;
			}
			Assert.isTrue(refused, 'Every criterion needs a score from 1 to 5: ' + bad);
		}
		for (
			String bad : new List<String>{
				'[{"label":"A","weight":0}]',
				'[{"label":"A","weight":11}]',
				'[{"label":" ","weight":1}]',
				'[{"label":"Fit","weight":1},{"label":"fit","weight":2}]'
			}
		) {
			Boolean refused = false;
			try {
				EventProposalReview.validated(bad);
			} catch (IllegalArgumentException e) {
				refused = true;
			}
			Assert.isTrue(refused, 'Refused: ' + bad);
		}
		Assert.isTrue(EventProposalReview.criteriaOf('not json').isEmpty(), 'Unreadable: none');
	}

	@IsTest
	static void runsAWeightedReviewWithAPresenterAndAnAssignment() {
		System.runAs(staff()) {
			Speaker_Application__c talk = proposal();
			Contact bo = person('Bo');

			Test.startTest();
			EventProposalReview.saveCriteria(talk.Event__c, CRITERIA);
			Id presenterId = EventProposalReview.addPresenter(talk.Id, bo.Id, 'Panelist');
			Boolean twice = false;
			try {
				EventProposalReview.addPresenter(talk.Id, talk.Contact__c, null);
			} catch (AuraHandledException e) {
				twice = true;
			}
			Integer assigned = EventProposalReview.assignReviewers(
				new List<Id>{ talk.Id },
				UserInfo.getUserId()
			);
			Integer again = EventProposalReview.assignReviewers(
				new List<Id>{ talk.Id },
				UserInfo.getUserId()
			);
			EventApplicationsController.Applications before = EventApplicationsController.getApplications(
				talk.Event__c
			);
			EventApplicationsController.saveReview(
				talk.Id,
				null,
				'Strong',
				'{"Relevance":4,"Clarity":5}'
			);
			EventApplicationsController.Applications after = EventApplicationsController.getApplications(
				talk.Event__c
			);
			EventApplicationsController.decide(
				talk.Id,
				EventApplicationsController.ACCEPTED,
				false
			);
			Test.stopTest();

			Assert.isNotNull(presenterId, 'Presenter named');
			Assert.isTrue(twice, 'The applicant is not named again');
			Assert.areEqual(1, assigned, 'Assigned once');
			Assert.areEqual(0, again, 'Never twice');
			Assert.areEqual(2, before.criteria.size(), 'Two criteria');
			Assert.isTrue(before.applications[0].assignedToMe, 'Shown as my assignment');
			Assert.areEqual(0, before.applications[0].reviewCount, 'An assignment is not a review');
			Assert.areEqual(1, before.applications[0].presenters.size(), 'One presenter');
			Speaker_Review__c review = [
				SELECT Score__c, Weighted_Score__c, Criteria_Scores__c
				FROM Speaker_Review__c
				WITH USER_MODE
				LIMIT 1
			];
			Assert.areEqual(4.33, review.Weighted_Score__c, 'Weighted score');
			Assert.areEqual(4, review.Score__c, 'Rounded score');
			Assert.isFalse(after.applications[0].assignedToMe, 'Scored');
			Assert.areEqual(4.33, after.applications[0].weightedAverage, 'Weighted average');
			Assert.areEqual(
				2,
				[
					SELECT COUNT()
					FROM Event_Speaker__c
					WHERE Event__c = :talk.Event__c
					WITH USER_MODE
				],
				'The applicant and the presenter are speakers'
			);
		}
	}

	@IsTest
	static void refusesAMissingCriterionScoreAndASixthPresenter() {
		System.runAs(staff()) {
			Speaker_Application__c talk = proposal();
			update as user new Event__c(Id = talk.Event__c, Review_Criteria__c = CRITERIA);
			List<Contact> people = new List<Contact>();
			for (Integer i = 0; i < EventProposalReview.MAX_PRESENTERS + 1; i++) {
				people.add(TestDataFactory.person(new Contact(LastName = 'Presenter' + i)));
			}
			insert as user people;

			Test.startTest();
			Boolean unscored = false;
			try {
				EventApplicationsController.saveReview(talk.Id, 5, null, '{"Relevance":4}');
			} catch (AuraHandledException e) {
				unscored = true;
			}
			for (Integer i = 0; i < EventProposalReview.MAX_PRESENTERS; i++) {
				EventProposalReview.addPresenter(talk.Id, people[i].Id, 'Speaker');
			}
			Boolean sixth = false;
			try {
				EventProposalReview.addPresenter(
					talk.Id,
					people[EventProposalReview.MAX_PRESENTERS].Id,
					'Speaker'
				);
			} catch (AuraHandledException e) {
				sixth = true;
			}
			EventProposalReview.removePresenter(
				[SELECT Id FROM Proposal_Presenter__c WITH USER_MODE LIMIT 1].Id
			);
			Boolean badCriteria = false;
			try {
				EventProposalReview.saveCriteria(talk.Event__c, '[{"label":"A","weight":0}]');
			} catch (AuraHandledException e) {
				badCriteria = true;
			}
			EventProposalReview.saveCriteria(talk.Event__c, '[]');
			Test.stopTest();

			Assert.isTrue(unscored, 'Every criterion must be scored');
			Assert.areEqual(0, [SELECT COUNT() FROM Speaker_Review__c WITH USER_MODE], 'No review');
			Assert.isTrue(sixth, 'Five more presenters at most');
			Assert.areEqual(
				EventProposalReview.MAX_PRESENTERS - 1,
				[SELECT COUNT() FROM Proposal_Presenter__c WITH USER_MODE],
				'One removed'
			);
			Assert.isTrue(badCriteria, 'A weight of 0 is refused');
			Assert.isNull(
				[SELECT Review_Criteria__c FROM Event__c WITH USER_MODE LIMIT 1].Review_Criteria__c,
				'Cleared'
			);
		}
	}
}
