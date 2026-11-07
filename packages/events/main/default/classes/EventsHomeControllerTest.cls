/**
 * Dana runs the events: the Events page lists what is coming and what is over, and Repeat Event
 * makes the next occurrences of a monthly class in one step (EV-01, R-EV4).
 */
@IsTest(testFor='ApexClass:EventsHomeController')
private class EventsHomeControllerTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	private static User staff() {
		return TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	private static Event__c event(String name, Datetime start, String status) {
		return new Event__c(
			Name = name,
			Status__c = status,
			Format__c = 'In Person',
			Start__c = start,
			End__c = start.addHours(2),
			Registration_Closes__c = start.addHours(-24)
		);
	}

	@IsTest
	static void listsUpcomingSoonestFirstAndPastSeparately() {
		System.runAs(staff()) {
			Datetime now = Datetime.now();
			insert as user new List<Event__c>{
				event('Later', now.addDays(20), 'Open'),
				event('Sooner', now.addDays(2), 'Draft'),
				event('Held', now.addDays(-10), 'Completed'),
				event('Called Off', now.addDays(5), 'Cancelled')
			};

			Test.startTest();
			EventsHomeController.Home upcoming = EventsHomeController.getEvents('upcoming');
			EventsHomeController.Home past = EventsHomeController.getEvents(
				EventsHomeController.VIEW_PAST
			);
			Test.stopTest();

			Assert.areEqual(2, upcoming.events.size(), 'Two events are still to come');
			Assert.areEqual('Sooner', upcoming.events[0].name, 'Soonest first');
			Assert.isTrue(upcoming.canCreate, 'Staff may create events');
			Assert.areEqual('Status', upcoming.fieldLabels.get('Status__c'), 'Column labels');
			Assert.areEqual(2, past.events.size(), 'Held and cancelled events are past');
		}
	}

	@IsTest
	static void repeatMakesDraftCopiesInTheSeries() {
		System.runAs(staff()) {
			Datetime start = Datetime.now().addDays(7);
			Event__c first = event('Monthly Class', start, 'Open');
			insert as user first;
			insert as user new Ticket_Type__c(
				Event__c = first.Id,
				Name = 'General',
				Price__c = 15,
				Sales_End__c = start.addHours(-1)
			);

			Test.startTest();
			Integer made = EventsHomeController.repeatEvent(
				first.Id,
				new List<Datetime>{ start.addDays(28), start.addDays(56) }
			);
			Test.stopTest();

			Assert.areEqual(2, made, 'Two occurrences');
			List<Event__c> copies = [
				SELECT Status__c, Start__c, End__c, Registration_Closes__c, Series__c
				FROM Event__c
				WHERE Series__c = :first.Id
				WITH USER_MODE
				ORDER BY Start__c
			];
			Assert.areEqual(2, copies.size(), 'Both point at the first event');
			Assert.areEqual('Draft', copies[0].Status__c, 'Each starts as a draft');
			Assert.areEqual(start.addDays(28).addHours(2), copies[0].End__c, 'Same length');
			Assert.areEqual(
				start.addDays(27),
				copies[0].Registration_Closes__c,
				'Registration window moved with it'
			);
			List<Ticket_Type__c> tickets = [
				SELECT Name, Price__c, Sales_End__c
				FROM Ticket_Type__c
				WHERE Event__c = :copies[0].Id
				WITH USER_MODE
			];
			Assert.areEqual(1, tickets.size(), 'The ticket types are copied');
			Assert.areEqual(15, tickets[0].Price__c, 'With their price');
			Assert.areEqual(
				start.addDays(28).addHours(-1),
				tickets[0].Sales_End__c,
				'Sales window moved with the occurrence'
			);
		}
	}

	@IsTest
	static void repeatRefusesBadDatesAndCountsAndSavesNothing() {
		System.runAs(staff()) {
			Datetime start = Datetime.now().addDays(7);
			Event__c first = event('Class', start, 'Open');
			insert as user first;
			List<Datetime> tooMany = new List<Datetime>();
			for (Integer i = 1; i <= EventsHomeController.MAX_OCCURRENCES + 1; i++) {
				tooMany.add(start.addDays(7 * i));
			}

			Test.startTest();
			Boolean refusedEarlier = false;
			Boolean refusedMany = false;
			try {
				EventsHomeController.repeatEvent(
					first.Id,
					new List<Datetime>{ start.addDays(7), start.addDays(-7) }
				);
			} catch (AuraHandledException e) {
				refusedEarlier = true;
			}
			try {
				EventsHomeController.repeatEvent(first.Id, tooMany);
			} catch (AuraHandledException e) {
				refusedMany = true;
			}
			Test.stopTest();

			Assert.isTrue(refusedEarlier, 'An occurrence before the event is refused');
			Assert.isTrue(refusedMany, 'More than the limit is refused');
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Event__c WHERE Series__c = :first.Id WITH USER_MODE],
				'Nothing was saved'
			);
		}
	}

	@IsTest
	static void aReaderCannotRepeat() {
		User reader = TestUsers.standardUserWith(
			'Reader',
			new List<String>{ 'BarnCRM_Read_Only', 'Events_Read_Only' }
		);
		System.runAs(reader) {
			Boolean refused = false;
			try {
				EventsHomeController.repeatEvent(
					null,
					new List<Datetime>{ Datetime.now().addDays(1) }
				);
			} catch (AuraHandledException e) {
				refused = true;
			}
			Assert.isTrue(refused, 'Read Only cannot create events');
			Assert.isFalse(
				EventsHomeController.getEvents('upcoming').canCreate,
				'Read Only is offered no New Event'
			);
		}
	}
}
