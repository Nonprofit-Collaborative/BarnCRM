/**
 * Dana picks a survey for the spring gala, Sam who came gets the survey email with his own link,
 * Sam answers it and the summary has his answers; without Forms nothing is offered (EV-18).
 * Forms may or may not be installed, so a stand-in catalog extension is installed (Core's
 * `FormCatalogTestSupport`) and a missing Forms is simulated by installing none.
 */
@IsTest(
	testFor='ApexClass:EventSurveyController, ApexClass:EventSurveyService, ApexClass:EventFormAttachment, ApexClass:EventEmailService'
)
private class EventSurveyControllerTest {
	private static final String FORM_KEY = String.valueOf(UserInfo.getUserId());

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	private static User staff() {
		return TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	/** A catalog with one public form, two questions and an address for any record. */
	private class Catalog implements FormCatalogExtension {
		public List<FormCatalogEntry> publicForms() {
			FormCatalogEntry entry = new FormCatalogEntry();
			entry.key = FORM_KEY;
			entry.label = 'After the Event';
			return new List<FormCatalogEntry>{ entry };
		}

		public List<FormCatalogEntry> questions(Id formId) {
			FormCatalogEntry rating = new FormCatalogEntry();
			rating.key = 'rating';
			rating.label = 'How was it?';
			rating.kind = 'number';
			FormCatalogEntry comment = new FormCatalogEntry();
			comment.key = 'comment';
			comment.label = 'Anything else?';
			comment.kind = 'textarea';
			return new List<FormCatalogEntry>{ rating, comment };
		}

		public String publicLink(Id formId, Id contextRecordId) {
			return 'https://zzforms.example.org/FormsPublic?form=' +
				formId +
				'&record=' +
				contextRecordId;
		}
	}

	private static Event__c past(String surveyKey) {
		Datetime start = Datetime.now().addDays(-2);
		Event__c record = new Event__c(
			Name = 'Spring Gala',
			Status__c = 'Completed',
			Format__c = 'In Person',
			Start__c = start,
			End__c = start.addHours(3),
			Survey_Form_Key__c = surveyKey
		);
		insert as user record;
		return record;
	}

	private static Event_Attendee__c attendee(Event__c event, String last) {
		Contact person = new Contact(
			FirstName = 'A',
			LastName = last,
			Email = last + '@example.org'
		);
		insert as user person;
		EventPersonMatcher.PersonInput input = new EventPersonMatcher.PersonInput();
		input.contactId = person.Id;
		EventRegistrationService.Request request = new EventRegistrationService.Request();
		request.eventId = event.Id;
		request.registrant = input;
		request.attendeeStatus = 'Attended';
		EventRegistrationService.register(request);
		return [
			SELECT Id, Contact__c
			FROM Event_Attendee__c
			WHERE Contact__c = :person.Id
			WITH USER_MODE
		];
	}

	private static FormSubmissionReceipt receipt(Id attendeeId, Object rating, String comment) {
		FormSubmissionReceipt receipt = new FormSubmissionReceipt();
		receipt.contextRecordId = attendeeId;
		receipt.answers.put('rating', rating);
		receipt.answers.put('comment', comment);
		return receipt;
	}

	@IsTest
	static void offersNothingWithoutForms() {
		System.runAs(staff()) {
			FormCatalogTestSupport.install(null);
			Event__c event = past(null);

			EventSurveyController.Survey result = EventSurveyController.getSurvey(event.Id);

			Assert.isFalse(result.available, 'No Forms, no survey option');
			Assert.isTrue(result.forms.isEmpty());
			Assert.isTrue(EventSurveyService.linksFor(null).isEmpty());
		}
	}

	@IsTest
	static void choosesAndClearsTheSurveyForm() {
		System.runAs(staff()) {
			FormCatalogTestSupport.install(new Catalog());
			Event__c event = past(null);

			EventSurveyController.saveForm(event.Id, FORM_KEY);
			EventSurveyController.Survey chosen = EventSurveyController.getSurvey(event.Id);

			Assert.isTrue(chosen.available);
			Assert.areEqual(FORM_KEY, chosen.formKey);
			Assert.areEqual(1, chosen.forms.size());
			Assert.areEqual('rating', chosen.questions[0].key);

			EventSurveyController.saveForm(event.Id, '');
			Assert.isNull(EventSurveyController.getSurvey(event.Id).formKey, 'Cleared');

			try {
				EventSurveyController.saveForm(event.Id, event.Id);
				Assert.fail('A form that is not a public form is refused');
			} catch (AuraHandledException refused) {
				Assert.isTrue(refused != null);
			}
		}
	}

	@IsTest
	static void keepsAnAttendeesAnswersOnceAndSummarisesThem() {
		System.runAs(staff()) {
			FormCatalogTestSupport.install(new Catalog());
			Event__c event = past(FORM_KEY);
			Event_Attendee__c sam = attendee(event, 'Lee');
			EventFormAttachment attachment = new EventFormAttachment();

			Test.startTest();
			attachment.received(receipt(sam.Id, 3, 'Loud'));
			attachment.received(receipt(sam.Id, 5, 'Great'));
			Test.stopTest();

			Assert.isTrue(
				attachment.handles(Event_Attendee__c.SObjectType),
				'Attendees take a form'
			);
			Assert.areEqual(
				FORM_KEY,
				String.valueOf(attachment.formFor(sam.Id)),
				'The event survey'
			);
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Event_Survey_Response__c WITH USER_MODE],
				'A second submission replaces the first'
			);
			EventSurveyController.Survey result = EventSurveyController.getSurvey(event.Id);
			Assert.areEqual(1, result.responses.size());
			Assert.areEqual(1, result.attended);
			Assert.areEqual(0, result.sent, 'No link has been sent yet');
			Assert.areEqual('Lee', result.responses[0].name.substringAfter(' '));
			Map<String, Object> answers = (Map<String, Object>) JSON.deserializeUntyped(
				result.responses[0].answers
			);
			Assert.areEqual('Great', answers.get('comment'));
			Assert.areEqual(sam.Id, result.responses[0].attendeeId);
		}
	}

	@IsTest
	static void anEventWithoutASurveyKeepsRegistrationsAndIgnoresSurveyAnswers() {
		System.runAs(staff()) {
			FormCatalogTestSupport.install(new Catalog());
			Event__c event = past(null);
			Event_Attendee__c sam = attendee(event, 'Lee');

			Assert.isNull(new EventFormAttachment().formFor(sam.Id), 'No survey chosen');
			Assert.isNull(EventSurveyService.formId('not an id'));
			Assert.isNull(EventSurveyService.formId(null));
			Assert.isTrue(
				EventSurveyService.linksFor(new List<Event_Attendee__c>{ sam }).isEmpty()
			);
		}
	}

	@IsTest
	static void clipsLongAnswersToFitTheField() {
		System.runAs(staff()) {
			String long1 = 'x'.repeat(40000);
			String json = EventSurveyService.answersJson(
				new Map<String, Object>{ 'comment' => long1, 'rating' => 4 }
			);
			Assert.isTrue(json.length() <= EventSurveyService.MAX_ANSWERS_LENGTH);
			Assert.isTrue(json.contains('"rating":4'));
			Assert.areEqual('{}', EventSurveyService.answersJson(null));
		}
	}

	@IsTest
	static void theFollowUpCarriesTheSurveyLinkOnlyForEventsWithASurvey() {
		System.runAs(staff()) {
			FormCatalogTestSupport.install(new Catalog());
			OrgSettingsSystemWriter.save(
				Events_Settings__c.SObjectType,
				new Map<Schema.SObjectField, Object>{
					Events_Settings__c.Follow_Ups_Enabled__c => true
				}
			);
			SettingsService.clearCaches();
			Event__c surveyed = past(FORM_KEY);
			Event_Attendee__c sam = attendee(surveyed, 'Lee');
			Event_Attendee__c ray = attendee(past(null), 'Ray');
			RecordingEmailSender stub = new RecordingEmailSender();
			EventEmailService.emailSender = stub;

			Test.startTest();
			Database.QueryLocatorIterator it = EventEmailService.locator(
					EventEmailService.PHASE_FOLLOW_UP
				)
				.iterator();
			List<Event_Attendee__c> due = new List<Event_Attendee__c>();
			while (it.hasNext()) {
				due.add((Event_Attendee__c) it.next());
			}
			Integer sent = EventEmailService.run(EventEmailService.PHASE_FOLLOW_UP, due);
			Test.stopTest();

			Assert.areEqual(2, sent, 'Both attended');
			Map<Id, Id> templateByPerson = new Map<Id, Id>();
			for (Messaging.SingleEmailMessage message : stub.received) {
				templateByPerson.put(message.getTargetObjectId(), message.getTemplateId());
			}
			Assert.areNotEqual(
				templateByPerson.get(sam.Contact__c),
				templateByPerson.get(ray.Contact__c),
				'Sam gets the survey template, Ray the plain follow-up'
			);
			Id surveyTemplate = [
				SELECT Id
				FROM EmailTemplate
				WHERE DeveloperName = :EventsSettings.DEFAULT_SURVEY_TEMPLATE
				LIMIT 1
			]
			.Id;
			Assert.areEqual(surveyTemplate, templateByPerson.get(sam.Contact__c));
			Assert.isTrue(
				[SELECT Survey_Link__c FROM Event_Attendee__c WHERE Id = :sam.Id WITH USER_MODE]
					.Survey_Link__c.endsWith('&record=' + sam.Id),
				'His own link'
			);
			Assert.isNull(
				[SELECT Survey_Link__c FROM Event_Attendee__c WHERE Id = :ray.Id WITH USER_MODE]
				.Survey_Link__c,
				'No survey, no link'
			);
			Assert.areEqual(
				1,
				EventSurveyController.getSurvey(surveyed.Id).sent,
				'One survey link sent'
			);
		}
	}
}
