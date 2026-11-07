/**
 * Dana runs the call for speakers for the community conference: two proposals arrive, reviewers
 * score them, the best is accepted (the applicant becomes a speaker and gets the accepted notice
 * the settings name) and the other is declined (EV-06, R-SA1 to R-SA5).
 */
@IsTest(
	testFor='ApexClass:EventApplicationsController, ApexClass:EventsSettings, ApexClass:EventKeyHandler'
)
private class EventApplicationsControllerTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	private static User staff() {
		return TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	private static Event__c conference() {
		Datetime start = Datetime.now().addDays(30);
		Event__c record = new Event__c(
			Name = 'Community Dreamin',
			Status__c = 'Open',
			Format__c = 'In Person',
			Start__c = start,
			End__c = start.addHours(8)
		);
		insert as user record;
		return record;
	}

	private static Speaker_Application__c application(Event__c event, String title, String email) {
		Contact person = new Contact(FirstName = 'Ana', LastName = title, Email = email);
		insert as user person;
		Speaker_Application__c record = new Speaker_Application__c(
			Event__c = event.Id,
			Contact__c = person.Id,
			Name = title,
			Abstract__c = 'A talk'
		);
		insert as user record;
		return record;
	}

	private static void chooseTemplates(String accepted, String declined) {
		OrgSettingsSystemWriter.save(
			Events_Settings__c.SObjectType,
			new Map<Schema.SObjectField, Object>{
				Events_Settings__c.Accept_Notice_Template__c => accepted,
				Events_Settings__c.Decline_Notice_Template__c => declined
			}
		);
		SettingsService.clearCaches();
	}

	private static void makeTemplate(String developerName) {
		System.runAs(new User(Id = UserInfo.getUserId())) {
			insert new EmailTemplate(
				Name = developerName,
				DeveloperName = developerName,
				TemplateType = 'text',
				FolderId = UserInfo.getUserId(),
				IsActive = true,
				Subject = 'Your proposal',
				Body = 'Thank you'
			);
		}
	}

	@IsTest
	static void averagesScoresAndRanksTheBestFirst() {
		System.runAs(staff()) {
			Event__c event = conference();
			Speaker_Application__c weak = application(event, 'Weak', 'a@example.org');
			Speaker_Application__c strong = application(event, 'Strong', 'b@example.org');

			Test.startTest();
			EventApplicationsController.saveReview(weak.Id, 2, 'Thin');
			EventApplicationsController.saveReview(strong.Id, 5, 'Great');
			EventApplicationsController.saveReview(strong.Id, 4, 'Great, a little long');
			EventApplicationsController.Applications result = EventApplicationsController.getApplications(
				event.Id
			);
			Test.stopTest();

			Assert.areEqual(2, result.applications.size(), 'Two applications');
			Assert.areEqual('Strong', result.applications[0].name, 'Best average first');
			Assert.areEqual(
				1,
				result.applications[0].reviewCount,
				'A second save replaces the first'
			);
			Assert.areEqual(4, result.applications[0].myScore, 'The latest score is mine');
			Assert.areEqual('In Review', result.applications[0].status, 'A review moves it along');
			Assert.areEqual(4, result.applications[0].averageScore, 'Average of one score');
			Assert.isTrue(result.canAdd && result.canReview && result.canDecide, 'Staff may act');
		}
	}

	@IsTest
	static void refusesAScoreOutsideOneToFive() {
		System.runAs(staff()) {
			Speaker_Application__c talk = application(conference(), 'Talk', 'a@example.org');

			Test.startTest();
			Boolean refused = false;
			try {
				EventApplicationsController.saveReview(talk.Id, 6, null);
			} catch (AuraHandledException e) {
				refused = true;
			}
			Test.stopTest();

			Assert.isTrue(refused, 'A score of 6 is refused');
			Assert.areEqual(0, [SELECT COUNT() FROM Speaker_Review__c], 'Nothing saved');
		}
	}

	@IsTest
	static void acceptingMakesTheSpeakerAndSendsTheNotice() {
		makeTemplate('Speaker_Accepted');
		RecordingEmailSender sender = new RecordingEmailSender();
		EventApplicationsController.emailSender = sender;
		System.runAs(staff()) {
			chooseTemplates('Speaker_Accepted', null);
			Event__c event = conference();
			Speaker_Application__c talk = application(event, 'Talk', 'a@example.org');

			Test.startTest();
			EventApplicationsController.Decision decision = EventApplicationsController.decide(
				talk.Id,
				'Accepted',
				true
			);
			Test.stopTest();

			Assert.areEqual('Accepted', decision.status, 'Accepted');
			Assert.areEqual(
				EventApplicationsController.NOTICE_SENT,
				decision.notice,
				'Notice sent'
			);
			Assert.areEqual(1, sender.received.size(), 'One email');
			Assert.areEqual(talk.Id, sender.received[0].getWhatId(), 'Merged with the application');
			Event_Speaker__c speaker = [
				SELECT Contact__c, Status__c
				FROM Event_Speaker__c
				WHERE Id = :decision.speakerId
			];
			Assert.areEqual('Invited', speaker.Status__c, 'The speaker is invited');
			Speaker_Application__c saved = [
				SELECT Status__c, Event_Speaker__c, Notice_Sent__c
				FROM Speaker_Application__c
				WHERE Id = :talk.Id
			];
			Assert.areEqual('Accepted', saved.Status__c, 'Status saved');
			Assert.areEqual(decision.speakerId, saved.Event_Speaker__c, 'Speaker linked');
			Assert.isNotNull(saved.Notice_Sent__c, 'Send time stamped');
		}
	}

	@IsTest
	static void acceptingLinksTheSpeakerAlreadyThere() {
		System.runAs(staff()) {
			Event__c event = conference();
			Speaker_Application__c talk = application(event, 'Talk', 'a@example.org');
			Event_Speaker__c existing = new Event_Speaker__c(
				Event__c = event.Id,
				Contact__c = talk.Contact__c
			);
			insert as user existing;

			Test.startTest();
			EventApplicationsController.Decision decision = EventApplicationsController.decide(
				talk.Id,
				'Accepted',
				false
			);
			Test.stopTest();

			Assert.areEqual(existing.Id, decision.speakerId, 'The existing speaker is linked');
			Assert.areEqual(1, [SELECT COUNT() FROM Event_Speaker__c], 'No second speaker');
			Assert.areEqual(
				EventApplicationsController.NOTICE_NONE,
				decision.notice,
				'No notice asked'
			);
		}
	}

	@IsTest
	static void decliningSendsTheDeclinedNoticeAndMakesNoSpeaker() {
		makeTemplate('Speaker_Declined');
		RecordingEmailSender sender = new RecordingEmailSender();
		EventApplicationsController.emailSender = sender;
		System.runAs(staff()) {
			chooseTemplates('Speaker_Accepted', 'Speaker_Declined');
			Speaker_Application__c talk = application(conference(), 'Talk', 'a@example.org');

			Test.startTest();
			EventApplicationsController.Decision decision = EventApplicationsController.decide(
				talk.Id,
				'Declined',
				true
			);
			Test.stopTest();

			Assert.areEqual(
				EventApplicationsController.NOTICE_SENT,
				decision.notice,
				'Notice sent'
			);
			Assert.areEqual(1, sender.received.size(), 'One email');
			Assert.areEqual(0, [SELECT COUNT() FROM Event_Speaker__c], 'No speaker made');
		}
	}

	@IsTest
	static void aNoticeThatCannotGoOutNeverUndoesTheDecision() {
		RecordingEmailSender sender = new RecordingEmailSender();
		EventApplicationsController.emailSender = sender;
		System.runAs(staff()) {
			Event__c event = conference();
			Speaker_Application__c missing = application(event, 'Two', 'b@example.org');
			Speaker_Application__c noEmail = application(event, 'Three', null);

			Test.startTest();
			chooseTemplates(null, 'No_Such_Template');
			String unknown = EventApplicationsController.decide(missing.Id, 'Declined', true)
				.notice;
			makeTemplate('Speaker_Declined');
			chooseTemplates(null, 'Speaker_Declined');
			String blank = EventApplicationsController.decide(noEmail.Id, 'Declined', true).notice;
			Test.stopTest();

			Assert.areEqual(
				EventApplicationsController.NOTICE_UNKNOWN_TEMPLATE,
				unknown,
				'Template not found'
			);
			Assert.areEqual(EventApplicationsController.NOTICE_NO_EMAIL, blank, 'No email address');
			Assert.areEqual(0, sender.received.size(), 'Nothing sent');
			Assert.areEqual(
				2,
				[SELECT COUNT() FROM Speaker_Application__c WHERE Status__c = 'Declined'],
				'Both decisions stand'
			);
			Assert.areEqual(
				2,
				[SELECT COUNT() FROM Speaker_Application__c WHERE Notice_Result__c != NULL],
				'Each records why no notice went'
			);
		}
	}

	@IsTest
	static void theSpeakerNoticesShipWithTemplatesAndTheyAreTheDefaults() {
		Assert.areEqual(
			'BarnCRM_Speaker_Accepted',
			EventsSettings.acceptNoticeTemplate(),
			'Accepted'
		);
		Assert.areEqual(
			'BarnCRM_Speaker_Declined',
			EventsSettings.declineNoticeTemplate(),
			'Declined'
		);
		Assert.areEqual(
			2,
			[
				SELECT COUNT()
				FROM EmailTemplate
				WHERE
					DeveloperName IN ('BarnCRM_Speaker_Accepted', 'BarnCRM_Speaker_Declined')
					AND IsActive = TRUE
			],
			'Both shipped templates are in the org'
		);
	}

	@IsTest
	static void aFailedSendIsRecordedAndTheDecisionStands() {
		makeTemplate('Speaker_Declined');
		RecordingEmailSender sender = new RecordingEmailSender();
		sender.failAll = true;
		EventApplicationsController.emailSender = sender;
		System.runAs(staff()) {
			chooseTemplates(null, 'Speaker_Declined');
			Speaker_Application__c talk = application(conference(), 'Talk', 'a@example.org');

			Test.startTest();
			EventApplicationsController.Decision decision = EventApplicationsController.decide(
				talk.Id,
				'Declined',
				true
			);
			Test.stopTest();

			Assert.areEqual(EventApplicationsController.NOTICE_FAILED, decision.notice, 'Failed');
			Assert.areEqual(
				'Declined',
				[SELECT Status__c FROM Speaker_Application__c WHERE Id = :talk.Id].Status__c,
				'Decision stands'
			);
		}
	}

	@IsTest
	static void aDecidedApplicationCannotBeDecidedOrReviewedAgain() {
		System.runAs(staff()) {
			Speaker_Application__c talk = application(conference(), 'Talk', 'a@example.org');
			EventApplicationsController.decide(talk.Id, 'Declined', false);

			Test.startTest();
			Boolean decideRefused = false;
			Boolean reviewRefused = false;
			try {
				EventApplicationsController.decide(talk.Id, 'Accepted', false);
			} catch (AuraHandledException e) {
				decideRefused = true;
			}
			try {
				EventApplicationsController.saveReview(talk.Id, 3, null);
			} catch (AuraHandledException e) {
				reviewRefused = true;
			}
			Test.stopTest();

			Assert.isTrue(decideRefused, 'A second decision is refused');
			Assert.isTrue(reviewRefused, 'A review after the decision is refused');
		}
	}

	@IsTest
	static void anApplicationNeedsAnApplicant() {
		System.runAs(staff()) {
			Test.startTest();
			Database.SaveResult saved = Database.insert(
				new Speaker_Application__c(Event__c = conference().Id, Name = 'No one'),
				false,
				AccessLevel.USER_MODE
			);
			Test.stopTest();

			Assert.isFalse(saved.isSuccess(), 'A new application names a person');
		}
	}
}
