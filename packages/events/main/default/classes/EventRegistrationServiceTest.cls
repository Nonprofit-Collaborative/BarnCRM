/**
 * Dana registers people for the spring gala: Jane is found by her email rather than created
 * twice, her son joins her household, a code takes money off, the last seat goes and the next
 * person waits, and Forms hands a submission over through Core's seam (EV-02, R-ERG1 to R-ERG3,
 * R-EAT1, R-EAT2, R-PC5).
 */
@IsTest(
	testFor='ApexClass:EventRegistrationService, ApexClass:EventPersonMatcher, ApexClass:EventPricing, ApexClass:EventFormAttachment'
)
private class EventRegistrationServiceTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	private static User staff() {
		return TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	private static Event__c gala(Integer capacity) {
		Datetime start = Datetime.now().addDays(30);
		Event__c record = new Event__c(
			Name = 'Spring Gala',
			Status__c = 'Open',
			Format__c = 'In Person',
			Start__c = start,
			End__c = start.addHours(4),
			Capacity__c = capacity
		);
		insert as user record;
		return record;
	}

	private static Ticket_Type__c ticket(Event__c event, String name, Decimal price, Integer qty) {
		Ticket_Type__c record = new Ticket_Type__c(
			Event__c = event.Id,
			Name = name,
			Price__c = price,
			Quantity__c = qty,
			Active__c = true
		);
		insert as user record;
		return record;
	}

	private static EventPersonMatcher.PersonInput person(String first, String last, String email) {
		EventPersonMatcher.PersonInput input = new EventPersonMatcher.PersonInput();
		input.firstName = first;
		input.lastName = last;
		input.email = email;
		return input;
	}

	private static EventRegistrationService.Request request(
		Event__c event,
		EventPersonMatcher.PersonInput registrant
	) {
		EventRegistrationService.Request request = new EventRegistrationService.Request();
		request.eventId = event.Id;
		request.registrant = registrant;
		return request;
	}

	@IsTest
	static void findsAnExistingPersonByEmailInsteadOfCreatingOne() {
		System.runAs(staff()) {
			Event__c event = gala(null);
			ticket(event, 'General', 50, null);
			Contact jane = new Contact(
				FirstName = 'Jane',
				LastName = 'Doe',
				Email = 'jane@example.org'
			);
			insert as user jane;

			Test.startTest();
			EventRegistrationService.Result result = EventRegistrationService.register(
				request(event, person('Jane', 'Doe', 'JANE@example.org '))
			);
			Test.stopTest();

			Assert.areEqual(jane.Id, result.registrantId, 'Matched by email, not created');
			Assert.areEqual(1, [SELECT COUNT() FROM Contact WITH USER_MODE], 'No duplicate person');
			Assert.areEqual('Registered', result.status, 'A seat was free');
			Assert.isTrue(result.amountOwed == 50, 'The ticket price is owed');
		}
	}

	@IsTest
	static void createsANewPersonAndPutsAGuestInTheirHousehold() {
		System.runAs(staff()) {
			Event__c event = gala(null);
			ticket(event, 'General', 0, null);
			EventRegistrationService.Request request = request(
				event,
				person('Sam', 'Lee', 'sam@example.org')
			);
			EventRegistrationService.GuestInput guest = new EventRegistrationService.GuestInput();
			guest.person = person('Max', 'Lee', null);
			request.guests.add(guest);

			Test.startTest();
			EventRegistrationService.Result result = EventRegistrationService.register(request);
			Test.stopTest();

			Assert.areEqual(2, result.registered, 'Both attend');
			Id household = EventPersonMatcher.householdOf(result.registrantId);
			Contact max = [
				SELECT Id, AccountId
				FROM Contact
				WHERE FirstName = 'Max'
				WITH USER_MODE
			];
			if (household != null && !HouseholdService.isJunctionMode()) {
				Assert.areEqual(household, max.AccountId, 'The guest joins the household');
			}
		}
	}

	@IsTest
	static void appliesACodeAndRefusesOneUsedUp() {
		System.runAs(staff()) {
			Event__c event = gala(null);
			Ticket_Type__c general = ticket(event, 'General', 80, null);
			Promo_Code__c code = new Promo_Code__c(
				Event__c = event.Id,
				Name = 'FRIENDS',
				Discount_Type__c = 'Percent',
				Discount_Value__c = 25,
				Max_Uses__c = 1,
				Active__c = true
			);
			insert as user code;
			EventRegistrationService.Request first = request(event, person('A', 'One', null));
			first.promoCode = 'friends';
			first.ticketType = 'general';

			Test.startTest();
			EventRegistrationService.Result result = EventRegistrationService.register(first);
			EventRegistrationService.Request second = request(event, person('B', 'Two', null));
			second.promoCode = 'FRIENDS';
			Boolean refused = false;
			try {
				EventRegistrationService.register(second);
			} catch (EventRegistrationService.RegistrationException e) {
				refused = true;
			}
			Test.stopTest();

			Assert.isTrue(result.amountOwed == 60, '25 percent off 80');
			Assert.isTrue(refused, 'The code has no use left');
			Assert.areEqual(
				general.Id,
				[SELECT Ticket_Type__c FROM Event_Attendee__c WITH USER_MODE LIMIT 1]
				.Ticket_Type__c,
				'Ticket found by name'
			);
		}
	}

	@IsTest
	static void waitlistsWhenFullAndMovesOffWhenASeatFrees() {
		System.runAs(staff()) {
			Event__c event = gala(1);
			ticket(event, 'General', 10, null);
			EventRegistrationService.Result first = EventRegistrationService.register(
				request(event, person('A', 'One', null))
			);

			Test.startTest();
			EventRegistrationService.Result second = EventRegistrationService.register(
				request(event, person('B', 'Two', null))
			);
			Event_Attendee__c waiting = [
				SELECT Id
				FROM Event_Attendee__c
				WHERE Event_Registration__c = :second.registrationId
				WITH USER_MODE
			];
			Boolean noSeat = false;
			try {
				EventRegistrationService.setStatus(waiting.Id, 'Registered');
			} catch (EventRegistrationService.RegistrationException e) {
				noSeat = true;
			}
			EventRegistrationService.cancelRegistration(first.registrationId);
			String moved = EventRegistrationService.setStatus(waiting.Id, 'Registered');
			Test.stopTest();

			Assert.areEqual('Waitlisted', second.status, 'No seat left');
			Assert.isTrue(second.amountOwed == 0, 'A waitlisted person owes nothing yet');
			Assert.isTrue(noSeat, 'Still full');
			Assert.areEqual('Registered', moved, 'Moved off the waitlist');
			Event_Registration__c after = [
				SELECT Status__c, Amount_Owed__c
				FROM Event_Registration__c
				WHERE Id = :second.registrationId
				WITH USER_MODE
			];
			Assert.areEqual('Registered', after.Status__c, 'The registration follows');
			Assert.isTrue(after.Amount_Owed__c == 10, 'Now owes the price');
		}
	}

	@IsTest
	static void neverRegistersAPersonTwiceAndMarksAttendance() {
		System.runAs(staff()) {
			Event__c event = gala(null);
			Contact jane = new Contact(FirstName = 'Jane', LastName = 'Doe');
			insert as user jane;
			EventPersonMatcher.PersonInput chosen = new EventPersonMatcher.PersonInput();
			chosen.contactId = jane.Id;
			EventRegistrationService.Result result = EventRegistrationService.register(
				request(event, chosen)
			);

			Test.startTest();
			Boolean refused = false;
			try {
				EventRegistrationService.register(request(event, chosen));
			} catch (EventRegistrationService.RegistrationException e) {
				refused = true;
			}
			Event_Attendee__c attendee = [SELECT Id FROM Event_Attendee__c WITH USER_MODE];
			EventRegistrationService.setStatus(attendee.Id, 'No-Show');
			EventRegistrationService.setStatus(attendee.Id, 'Attended');
			Test.stopTest();

			Assert.isTrue(refused, 'Already registered');
			Assert.areEqual(
				'Attended',
				[SELECT Status__c FROM Event_Attendee__c WHERE Id = :attendee.Id WITH USER_MODE]
				.Status__c,
				'Marked attended'
			);
			Assert.isTrue(result.amountOwed == 0, 'No ticket, nothing owed');
		}
	}

	@IsTest
	static void registersTheFormsPersonThroughTheCoreSeam() {
		System.runAs(staff()) {
			Event__c event = gala(null);
			ticket(event, 'General', 5, null);
			ticket(event, 'Student', 2, null);
			Contact jane = new Contact(FirstName = 'Jane', LastName = 'Doe');
			insert as user jane;
			EventFormAttachment attachment = new EventFormAttachment();
			FormSubmissionReceipt receipt = new FormSubmissionReceipt();
			receipt.contextRecordId = event.Id;
			receipt.personId = jane.Id;
			receipt.answers.put('ticketType', 'Student');

			Test.startTest();
			attachment.received(receipt);
			Test.stopTest();

			Assert.isTrue(attachment.handles(Event__c.SObjectType), 'Events take a form');
			Assert.isFalse(attachment.handles(Contact.SObjectType), 'Nothing else');
			Assert.isNull(attachment.formFor(event.Id), 'No form named');
			Event_Attendee__c attendee = [
				SELECT Price__c, Event_Registration__r.Source__c
				FROM Event_Attendee__c
				WITH USER_MODE
			];
			Assert.isTrue(attendee.Price__c == 2, 'The Student ticket');
			Assert.areEqual('Form', attendee.Event_Registration__r.Source__c, 'From a form');
		}
	}

	/** A form takes only tickets on sale now; staff may use any active ticket. */
	@IsTest
	static void aFormTakesOnlyTicketsOnSale() {
		System.runAs(staff()) {
			Event__c event = gala(null);
			Ticket_Type__c early = ticket(event, 'Early', 10, null);
			early.Sales_End__c = Datetime.now().addDays(-1);
			ticket(event, 'General', 25, null);
			Ticket_Type__c later = ticket(event, 'Later', 30, null);
			later.Sales_Start__c = Datetime.now().addDays(1);
			update as user new List<Ticket_Type__c>{ early, later };

			Test.startTest();
			EventRegistrationService.Request firstOnSale = request(
				event,
				person('Jane', 'Doe', 'jane@example.org')
			);
			firstOnSale.source = EventRegistrationService.SOURCE_FORM;
			EventRegistrationService.Result byForm = EventRegistrationService.register(firstOnSale);
			EventRegistrationService.Request notYet = request(
				event,
				person('Sam', 'Lee', 'sam@example.org')
			);
			notYet.source = EventRegistrationService.SOURCE_FORM;
			notYet.ticketType = 'Later';
			String refused;
			try {
				EventRegistrationService.register(notYet);
			} catch (EventRegistrationService.RegistrationException e) {
				refused = e.getMessage();
			}
			EventRegistrationService.Request byStaff = request(
				event,
				person('Sam', 'Lee', 'sam@example.org')
			);
			byStaff.ticketType = 'Early';
			EventRegistrationService.Result staffResult = EventRegistrationService.register(
				byStaff
			);
			Test.stopTest();

			Assert.isTrue(byForm.amountOwed == 25, 'A blank ticket is the first on sale: General');
			Assert.areEqual(
				BarnHelp.text(
					'Events',
					'Events_Register_TicketNotOnSale',
					new List<Object>{ 'Later' }
				),
				refused,
				'A ticket not on sale yet is refused to a form'
			);
			Assert.isTrue(staffResult.amountOwed == 10, 'Staff sell a ticket past its sale');
		}
	}

	/** A form posted outside the registration window registers nobody; staff still can (R-EV5). */
	@IsTest
	static void aFormRegistersOnlyWhileRegistrationIsOpen() {
		System.runAs(staff()) {
			Event__c notYet = gala(null);
			notYet.Registration_Opens__c = Datetime.now().addDays(1);
			Event__c closed = gala(null);
			closed.Status__c = 'Closed';
			update as user new List<Event__c>{ notYet, closed };

			Test.startTest();
			List<String> refusals = new List<String>();
			for (Event__c event : new List<Event__c>{ notYet, closed }) {
				EventRegistrationService.Request byForm = request(
					event,
					person('Jane', 'Doe', 'jane@example.org')
				);
				byForm.source = EventRegistrationService.SOURCE_FORM;
				try {
					EventRegistrationService.register(byForm);
				} catch (EventRegistrationService.RegistrationException refused) {
					refusals.add(refused.getMessage());
				}
			}
			EventRegistrationService.Result byStaff = EventRegistrationService.register(
				request(closed, person('Jane', 'Doe', 'jane@example.org'))
			);
			Test.stopTest();

			Assert.areEqual(
				new List<String>{
					BarnHelp.text('Events', 'Events_Public_RegisterNotYet'),
					BarnHelp.text('Events', 'Events_Public_RegisterClosed')
				},
				refusals,
				'Not yet open, then closed'
			);
			Assert.areEqual(1, byStaff.registered, 'Staff register past the window');
		}
	}

	@IsTest
	static void pricesFollowTheTicketsModelCases() {
		System.runAs(staff()) {
			Datetime now = Datetime.now();
			Promo_Code__c percent = new Promo_Code__c(
				Active__c = true,
				Discount_Type__c = 'Percent',
				Discount_Value__c = 33
			);
			Promo_Code__c amount = new Promo_Code__c(
				Active__c = true,
				Discount_Type__c = 'Amount',
				Discount_Value__c = 500
			);
			Promo_Code__c later = new Promo_Code__c(
				Active__c = true,
				Discount_Type__c = 'Percent',
				Discount_Value__c = 50,
				Valid_From__c = now.addDays(1)
			);

			Assert.isTrue(EventPricing.priceWithCode(10, percent, null, now) == 6.7, 'Rounded');
			Assert.isTrue(EventPricing.priceWithCode(25, amount, null, now) == 0, 'Never below 0');
			Assert.isTrue(EventPricing.priceWithCode(40, later, null, now) == 40, 'Not yet valid');
			Assert.areEqual('scheduled', EventPricing.codeState(later, now), 'Scheduled');
			Assert.areEqual('inactive', EventPricing.codeState(null, now), 'No code');
		}
	}
}
