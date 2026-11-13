/**
 * Dana picks a rating form for the conference and prints each session's code; people in Talk A
 * rate it, the agenda shows its average and the Speakers tab its speaker's (EV-27). Forms may or
 * may not be installed, so a stand-in catalog is installed (Core's `FormCatalogTestSupport`) and a
 * missing Forms is simulated by installing none.
 */
@IsTest(
	testFor='ApexClass:EventSessionRatings, ApexClass:EventFormAttachment, ApexClass:EventAgendaController, ApexClass:EventSpeakersController'
)
private class EventSessionRatingsTest {
	private static final String FORM_KEY = String.valueOf(UserInfo.getUserId());

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Events_Admin');
	}

	private static User staff() {
		return TestUsers.adminWith('Events_Admin');
	}

	/** A catalog with one public form and an address for any record. */
	private class Catalog implements FormCatalogExtension {
		public List<FormCatalogEntry> publicForms() {
			FormCatalogEntry entry = new FormCatalogEntry();
			entry.key = FORM_KEY;
			entry.label = 'Rate This Session';
			return new List<FormCatalogEntry>{ entry };
		}

		public List<FormCatalogEntry> questions(Id formId) {
			return new List<FormCatalogEntry>();
		}

		public String publicLink(Id formId, Id contextRecordId) {
			return 'https://zzforms.example.org/FormsPublic?form=' +
				formId +
				'&record=' +
				contextRecordId;
		}
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

	private static Event_Session__c session(Event__c event, String name, String status) {
		Event_Session__c record = new Event_Session__c(
			Event__c = event.Id,
			Name = name,
			Status__c = status
		);
		insert as user record;
		return record;
	}

	private static FormSubmissionReceipt receipt(Id sessionId, Object rating, Id submissionId) {
		FormSubmissionReceipt receipt = new FormSubmissionReceipt();
		receipt.contextRecordId = sessionId;
		receipt.submissionId = submissionId;
		receipt.answers.put('rating', rating);
		receipt.answers.put('comment', 'Great talk');
		return receipt;
	}

	@IsTest
	static void offersNothingWithoutForms() {
		System.runAs(staff()) {
			FormCatalogTestSupport.install(null);
			Event__c event = conference();

			EventSessionRatings.Setup result = EventSessionRatings.getSetup(event.Id);

			Assert.isFalse(result.available, 'No Forms, no ratings');
			Assert.isTrue(result.forms.isEmpty(), 'No forms offered');
			Assert.isTrue(result.links.isEmpty(), 'No codes');
		}
	}

	@IsTest
	static void choosesTheFormAndGivesEachConfirmedSessionALink() {
		System.runAs(staff()) {
			FormCatalogTestSupport.install(new Catalog());
			Event__c event = conference();
			Event_Session__c talk = session(event, 'Talk A', 'Confirmed');
			session(event, 'Draft Talk', 'Draft');

			Test.startTest();
			EventSessionRatings.saveForm(event.Id, ' ' + FORM_KEY + ' ');
			EventSessionRatings.Setup result = EventSessionRatings.getSetup(event.Id);
			Boolean refused = false;
			try {
				EventSessionRatings.saveForm(event.Id, String.valueOf(event.Id));
			} catch (AuraHandledException e) {
				refused = true;
			}
			EventSessionRatings.saveForm(event.Id, '');
			Test.stopTest();

			Assert.isTrue(result.available, 'Forms is there');
			Assert.areEqual(FORM_KEY, result.formKey, 'The form is chosen');
			Assert.areEqual(1, result.forms.size(), 'One form offered');
			Assert.areEqual(1, result.links.size(), 'Only the confirmed session has a code');
			Assert.isTrue(result.links.get(talk.Id).endsWith('&record=' + talk.Id), 'Tied to it');
			Assert.isTrue(refused, 'A form that is not public is refused');
			Assert.isNull(
				[SELECT Session_Rating_Form_Key__c FROM Event__c WITH USER_MODE LIMIT 1]
				.Session_Rating_Form_Key__c,
				'Cleared'
			);
		}
	}

	@IsTest
	static void keepsEachRatingOnceAndAveragesIt() {
		System.runAs(staff()) {
			Event__c event = conference();
			event.Session_Rating_Form_Key__c = FORM_KEY;
			update as user event;
			Event_Session__c talk = session(event, 'Talk A', 'Confirmed');
			Contact ana = new Contact(FirstName = 'Ana', LastName = 'Garcia');
			insert as user ana;
			Id speakerId = EventSpeakersController.addSpeaker(event.Id, ana.Id);
			EventSpeakersController.assign(talk.Id, speakerId, 'Speaker');
			EventFormAttachment attachment = new EventFormAttachment();
			Id firstKey = UserInfo.getUserId();
			Id secondKey = event.Id;

			Test.startTest();
			attachment.received(receipt(talk.Id, 5, firstKey));
			attachment.received(receipt(talk.Id, 5, firstKey));
			attachment.received(receipt(talk.Id, '3', secondKey));
			attachment.received(receipt(talk.Id, 6, null));
			attachment.received(receipt(talk.Id, 2.5, null));
			attachment.received(receipt(talk.Id, 'great', null));
			attachment.received(receipt(talk.Id, null, null));
			EventAgendaController.Agenda agenda = EventAgendaController.getAgenda(event.Id);
			EventSpeakersController.Speakers speakers = EventSpeakersController.getSpeakers(
				event.Id
			);
			Test.stopTest();

			Assert.isTrue(attachment.handles(Event_Session__c.SObjectType), 'Sessions handled');
			Assert.isFalse(attachment.signedClaim(talk.Id), 'Rating links are anonymous');
			Assert.areEqual(Id.valueOf(FORM_KEY), attachment.formFor(talk.Id), 'The rating form');
			Assert.areEqual(
				2,
				[SELECT COUNT() FROM Session_Rating__c WITH USER_MODE],
				'Once per submission; only whole ratings from 1 to 5'
			);
			Assert.areEqual(2, agenda.sessions[0].ratingCount, 'Two ratings');
			Assert.areEqual(4, agenda.sessions[0].averageRating, 'Average of 5 and 3');
			Assert.areEqual(4.0, speakers.speakers[0].averageRating, 'The speaker average');
			Assert.areEqual(2, speakers.speakers[0].ratingCount, 'Over two ratings');
		}
	}
}
