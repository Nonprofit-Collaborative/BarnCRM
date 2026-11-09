/**
 * The spring gala's public page shows only what Dana published: its tickets with prices and the
 * payment note, seats left only with Show Seats Left, confirmed sessions, confirmed speakers only
 * with Show Speakers, and the registration form only while registration is open; a Draft or
 * unpublished event has no page, and the list shows upcoming public events (EV-16, R-EV5;
 * ADR-0190 public event pages). Health Check reports a public event that cannot be shown.
 */
@IsTest(
	testFor='ApexClass:EventPublicPage, ApexClass:EventsHealthCheckExtension, ApexClass:EventsSettings'
)
private class EventPublicPageTest {
	// Any record identifier stands for the form: Events never reads it.
	private static final String FORM_KEY = 'a0B000000000001';

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	private static User staff() {
		return TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	private static Event__c gala(Boolean published, Boolean speakers, Boolean seats) {
		Datetime start = Datetime.now().addDays(30);
		Event__c record = new Event__c(
			Name = 'Spring Gala',
			Status__c = 'Open',
			Format__c = 'In Person',
			Start__c = start,
			End__c = start.addHours(4),
			Capacity__c = 2,
			Venue_Name__c = 'Grange Hall',
			Online_Link__c = 'https://example.org/secret-join-link',
			Registration_Form_Key__c = FORM_KEY,
			Public_Page__c = published,
			Public_Speakers__c = speakers,
			Public_Seats__c = seats
		);
		insert as user record;
		insert as user new List<Ticket_Type__c>{
			new Ticket_Type__c(
				Event__c = record.Id,
				Name = 'General',
				Price__c = 50,
				Active__c = true,
				Sort_Order__c = 1
			),
			new Ticket_Type__c(
				Event__c = record.Id,
				Name = 'Student',
				Price__c = 0,
				Quantity__c = 10,
				Active__c = true,
				Sort_Order__c = 2
			),
			new Ticket_Type__c(
				Event__c = record.Id,
				Name = 'Retired Ticket',
				Price__c = 10,
				Active__c = false
			)
		};
		Contact pat = new Contact(FirstName = 'Pat', LastName = 'Lee', Email = 'pat@example.org');
		Contact sam = new Contact(FirstName = 'Sam', LastName = 'Ray', Email = 'sam@example.org');
		insert as user new List<Contact>{ pat, sam };
		Event_Speaker__c confirmed = new Event_Speaker__c(
			Event__c = record.Id,
			Contact__c = pat.Id,
			Status__c = 'Confirmed',
			Headline__c = 'Farmer',
			Travel_Needs__c = 'Private travel note'
		);
		Event_Speaker__c invited = new Event_Speaker__c(
			Event__c = record.Id,
			Contact__c = sam.Id,
			Status__c = 'Invited'
		);
		insert as user new List<Event_Speaker__c>{ confirmed, invited };
		Event_Session__c keynote = new Event_Session__c(
			Event__c = record.Id,
			Name = 'Opening Keynote',
			Status__c = 'Confirmed',
			Start__c = start,
			End__c = start.addHours(1),
			Room__c = 'Main Hall'
		);
		Event_Session__c draft = new Event_Session__c(
			Event__c = record.Id,
			Name = 'Unannounced Talk',
			Status__c = 'Draft',
			Start__c = start.addHours(1),
			End__c = start.addHours(2)
		);
		insert as user new List<Event_Session__c>{ keynote, draft };
		insert as user new Session_Speaker__c(
			Event_Session__c = keynote.Id,
			Event_Speaker__c = confirmed.Id,
			Role__c = 'Speaker'
		);
		return record;
	}

	private static void seat(Event__c event) {
		EventRegistrationService.Request request = new EventRegistrationService.Request();
		request.eventId = event.Id;
		request.registrant = new EventPersonMatcher.PersonInput();
		request.registrant.firstName = 'Jo';
		request.registrant.lastName = 'Moss';
		request.registrant.email = 'jo@example.org';
		request.ticketType = 'General';
		EventRegistrationService.register(request);
	}

	private static Map<String, Object> section(Map<String, Object> page, String key) {
		for (Object each : (List<Object>) page.get('sections')) {
			Map<String, Object> found = (Map<String, Object>) each;
			if (found.get('key') == key) {
				return found;
			}
		}
		return null;
	}

	private static Map<String, Object> roundTrip(Map<String, Object> page) {
		return (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(page));
	}

	@IsTest
	static void showsWhatWasPublishedAndNothingElse() {
		System.runAs(staff()) {
			Event__c event = gala(true, true, true);
			seat(event);
			// The help catalog and settings are read once a transaction: read them first, so
			// the count below is the page's own.
			BarnHelp.text('Events', 'Events_Public_Tickets');
			EventsSettings.publicPaymentNote();

			Test.startTest();
			Map<String, Object> page = roundTrip(new EventPublicPage().page(event.Id));
			Integer queries = Limits.getQueries();
			Test.stopTest();

			Assert.areEqual(
				3,
				queries,
				'The event with tickets, sessions and speakers, seats left, and session speakers (was 6)'
			);
			String shown = JSON.serialize(page);
			Assert.areEqual('Spring Gala', page.get('title'));
			Assert.areEqual(EventPublicPage.OPEN, page.get('registration'));
			Assert.areEqual(String.valueOf(Id.valueOf(FORM_KEY)), page.get('formId'));
			Assert.isFalse(shown.contains('secret-join-link'), 'Online link never shown');
			Assert.isFalse(shown.contains('Private travel note'), 'Speaker needs never shown');
			Assert.isFalse(shown.contains('pat@example.org'), 'No email');
			Assert.isFalse(shown.contains('Retired Ticket'), 'Inactive tickets left out');
			Assert.isFalse(shown.contains('Unannounced Talk'), 'Draft sessions left out');
			Assert.isFalse(shown.contains('Sam'), 'Invited speakers left out');

			List<Object> tickets = (List<Object>) section(page, 'tickets').get('items');
			Assert.areEqual(2, tickets.size());
			Map<String, Object> general = (Map<String, Object>) tickets[0];
			Assert.areEqual(50, (Decimal) general.get('amount'));
			Assert.areEqual(EventsSettings.publicPaymentNote(), general.get('note'));
			Assert.areEqual(
				BarnHelp.text('Events', 'Events_Public_SeatsLeft', new List<Object>{ 1 }),
				((List<Object>) general.get('badges'))[0],
				'Capacity 2, one seated'
			);
			Map<String, Object> student = (Map<String, Object>) tickets[1];
			Assert.isNull(student.get('amount'), 'Free tickets carry no amount');

			List<Object> agenda = (List<Object>) section(page, 'agenda').get('items');
			Assert.areEqual(1, agenda.size());
			Assert.isTrue(
				String.valueOf(((Map<String, Object>) agenda[0]).get('badges')).contains('Pat Lee')
			);
			List<Object> speakers = (List<Object>) section(page, 'speakers').get('items');
			Assert.areEqual(1, speakers.size());
			Assert.areEqual('Pat Lee', ((Map<String, Object>) speakers[0]).get('title'));
		}
	}

	@IsTest
	static void speakersAndSeatsOnlyWhenChosen() {
		System.runAs(staff()) {
			Event__c event = gala(true, false, false);

			Map<String, Object> page = roundTrip(new EventPublicPage().page(event.Id));

			Assert.isNull(section(page, 'speakers'), 'Speakers not published');
			Assert.isFalse(JSON.serialize(page).contains('Pat'), 'No speaker names at all');
			Map<String, Object> general = (Map<String, Object>) ((List<Object>) section(
					page,
					'tickets'
				)
				.get('items'))[0];
			Assert.isTrue(((List<Object>) general.get('badges')).isEmpty(), 'No seats shown');
		}
	}

	@IsTest
	static void noPageUnlessPublishedAndAnnounced() {
		System.runAs(staff()) {
			Event__c event = gala(false, true, true);
			EventPublicPage pages = new EventPublicPage();
			Assert.isNull(pages.page(event.Id), 'Not published');

			event.Public_Page__c = true;
			event.Status__c = 'Draft';
			update as user event;
			Assert.isNull(pages.page(event.Id), 'Draft events have no page');
			Assert.isTrue(
				((List<Object>) pages.listPage().get('items')).isEmpty(),
				'Draft events are not listed'
			);

			event.Status__c = 'Open';
			update as user event;
			Assert.areEqual(1, ((List<Object>) pages.listPage().get('items')).size());
			Assert.areEqual('events', pages.kind());
			Assert.isTrue(pages.handles(Event__c.SObjectType));
		}
	}

	@IsTest
	static void registrationFollowsTheEventAndItsDates() {
		// runs-as: deploying user (pure logic: dates on an unsaved event, no DML or SOQL)
		Datetime now = Datetime.now();
		Event__c event = new Event__c(
			Status__c = 'Open',
			Start__c = now.addDays(10),
			End__c = now.addDays(11),
			Registration_Form_Key__c = FORM_KEY
		);
		Assert.areEqual(EventPublicPage.OPEN, EventPublicPage.registrationState(event));
		event.Registration_Opens__c = now.addDays(1);
		Assert.areEqual(EventPublicPage.NOT_YET, EventPublicPage.registrationState(event));
		event.Registration_Opens__c = null;
		event.Registration_Closes__c = now.addDays(-1);
		Assert.areEqual(EventPublicPage.CLOSED, EventPublicPage.registrationState(event));
		event.Registration_Closes__c = null;
		event.Status__c = 'Closed';
		Assert.areEqual(EventPublicPage.CLOSED, EventPublicPage.registrationState(event));
		event.Registration_Form_Key__c = 'not an id';
		Assert.areEqual(EventPublicPage.NONE, EventPublicPage.registrationState(event));
	}

	@IsTest
	static void healthCheckReportsPagesThatCannotBeShown() {
		System.runAs(staff()) {
			EventsHealthCheckExtension check = new EventsHealthCheckExtension();
			Assert.isTrue(check.findings().isEmpty(), 'Nothing published');

			Event__c event = gala(true, false, false);
			PublicPageExtensions.setHostInstalledForTest(false);
			String found = JSON.serialize(check.findings());
			Assert.isTrue(found.contains(EventsHealthCheckExtension.NO_HOST), found);

			PublicPageExtensions.setHostInstalledForTest(true);
			Assert.isTrue(check.findings().isEmpty(), 'Forms there and a form named');

			event.Registration_Form_Key__c = null;
			update as user event;
			found = JSON.serialize(check.findings());
			Assert.isTrue(found.contains(EventsHealthCheckExtension.NO_FORM), found);
		}
	}
}
