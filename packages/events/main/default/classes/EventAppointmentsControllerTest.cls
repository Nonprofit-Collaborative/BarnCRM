/**
 * Dana adds Priya's advice slots at the community conference, books a person into one, cannot
 * book that person into an overlapping slot, and moves slots between statuses (EV-15, R-EAP1 to
 * R-EAP4).
 */
@IsTest(testFor='ApexClass:EventAppointmentsController')
private class EventAppointmentsControllerTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Events_Admin');
	}

	private static User staff() {
		return TestUsers.adminWith('Events_Admin');
	}

	private static Event__c conference(Datetime start) {
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

	private static Contact person(String lastName) {
		Contact record = TestDataFactory.person(
			new Contact(FirstName = 'Test', LastName = lastName)
		);
		insert as user record;
		return record;
	}

	private static String slotsJson(Datetime start, Integer count) {
		List<Object> slots = new List<Object>();
		for (Integer i = 0; i < count; i++) {
			slots.add(
				new Map<String, Object>{
					'start' => start.addMinutes(i * 20),
					'finish' => start.addMinutes(i * 20 + 20)
				}
			);
		}
		return JSON.serialize(slots);
	}

	@IsTest
	static void addsOpenSlotsForAHostAndListsThemByTime() {
		System.runAs(staff()) {
			Datetime start = Datetime.now().addDays(30);
			Event__c event = conference(start);
			Contact priya = person('Priya');
			Integer added = EventAppointmentsController.addSlots(
				event.Id,
				priya.Id,
				slotsJson(start.addHours(1), 3),
				'Table 4'
			);
			Assert.areEqual(3, added);
			EventAppointmentsController.Appointments result = EventAppointmentsController.getAppointments(
				event.Id
			);
			Assert.areEqual(3, result.slots.size());
			Assert.areEqual('Open', result.slots[0].status);
			Assert.areEqual('Table 4', result.slots[0].location);
			Assert.areEqual(priya.Id, result.slots[0].hostId);
			Assert.isTrue(result.slots[0].start < result.slots[1].start, 'In time order');
			Assert.isTrue(result.canAdd);
			Assert.isTrue(result.canBook);
			Assert.isNotNull(result.eventEnd);
			Assert.isTrue(result.fieldLabels.containsKey('Host__c'));
		}
	}

	@IsTest
	static void refusesNoSlotsTooManyOrSlotsOutsideTheEvent() {
		System.runAs(staff()) {
			Datetime start = Datetime.now().addDays(30);
			Event__c event = conference(start);
			Contact priya = person('Priya');
			for (
				String bad : new List<String>{
					'[]',
					slotsJson(start, 101),
					slotsJson(start.addDays(2), 1)
				}
			) {
				try {
					EventAppointmentsController.addSlots(event.Id, priya.Id, bad, null);
					Assert.fail('A bad batch is refused');
				} catch (AuraHandledException refused) {
					Assert.areEqual(
						0,
						[SELECT COUNT() FROM Event_Appointment__c WHERE Event__c = :event.Id],
						'Nothing was added'
					);
				}
			}
		}
	}

	@IsTest
	static void booksAPersonOnlyIntoAnOpenSlotAndNotTwiceAtOnce() {
		System.runAs(staff()) {
			Datetime start = Datetime.now().addDays(30);
			Event__c event = conference(start);
			Contact priya = person('Priya');
			Contact omar = person('Omar');
			EventAppointmentsController.addSlots(
				event.Id,
				priya.Id,
				slotsJson(start.addHours(1), 2),
				null
			);
			Contact sam = person('Sam');
			// A second host with a slot at the very same time as Priya's first slot.
			EventAppointmentsController.addSlots(
				event.Id,
				sam.Id,
				slotsJson(start.addHours(1), 1),
				null
			);
			List<Event_Appointment__c> priyas = [
				SELECT Id
				FROM Event_Appointment__c
				WHERE Host__c = :priya.Id
				ORDER BY Start__c
			];
			Event_Appointment__c samsSlot = [
				SELECT Id
				FROM Event_Appointment__c
				WHERE Host__c = :sam.Id
			];
			EventAppointmentsController.book(priyas[0].Id, omar.Id);
			Event_Appointment__c booked = [
				SELECT Status__c, Contact__c
				FROM Event_Appointment__c
				WHERE Id = :priyas[0].Id
			];
			Assert.areEqual('Booked', booked.Status__c);
			Assert.areEqual(omar.Id, booked.Contact__c);
			try {
				EventAppointmentsController.book(priyas[0].Id, sam.Id);
				Assert.fail('A booked slot cannot be booked again');
			} catch (AuraHandledException refused) {
				Assert.areEqual(
					omar.Id,
					[SELECT Contact__c FROM Event_Appointment__c WHERE Id = :priyas[0].Id]
					.Contact__c
				);
			}
			try {
				EventAppointmentsController.book(samsSlot.Id, omar.Id);
				Assert.fail('Omar is already booked at that time');
			} catch (AuraHandledException refused) {
				Assert.areEqual(
					'Open',
					[SELECT Status__c FROM Event_Appointment__c WHERE Id = :samsSlot.Id].Status__c
				);
			}
			EventAppointmentsController.book(priyas[1].Id, omar.Id);
			Assert.areEqual(
				'Booked',
				[SELECT Status__c FROM Event_Appointment__c WHERE Id = :priyas[1].Id].Status__c
			);
		}
	}

	@IsTest
	static void movesASlotThroughItsStatuses() {
		System.runAs(staff()) {
			Datetime start = Datetime.now().addDays(30);
			Event__c event = conference(start);
			Contact priya = person('Priya');
			Contact omar = person('Omar');
			EventAppointmentsController.addSlots(
				event.Id,
				priya.Id,
				slotsJson(start.addHours(1), 1),
				null
			);
			Id slotId = [SELECT Id FROM Event_Appointment__c WHERE Host__c = :priya.Id].Id;
			try {
				EventAppointmentsController.setStatus(slotId, 'Completed');
				Assert.fail('An open slot has nobody to complete');
			} catch (AuraHandledException refused) {
				Assert.areEqual(
					'Open',
					[SELECT Status__c FROM Event_Appointment__c WHERE Id = :slotId].Status__c
				);
			}
			EventAppointmentsController.book(slotId, omar.Id);
			EventAppointmentsController.setStatus(slotId, 'No-Show');
			Assert.areEqual(
				'No-Show',
				[SELECT Status__c FROM Event_Appointment__c WHERE Id = :slotId].Status__c
			);
			EventAppointmentsController.setStatus(slotId, 'Open');
			Event_Appointment__c reopened = [
				SELECT Status__c, Contact__c
				FROM Event_Appointment__c
				WHERE Id = :slotId
			];
			Assert.areEqual('Open', reopened.Status__c);
			Assert.isNull(reopened.Contact__c, 'Releasing a slot clears the person');
			EventAppointmentsController.setStatus(slotId, 'Cancelled');
			Assert.areEqual(
				'Cancelled',
				[SELECT Status__c FROM Event_Appointment__c WHERE Id = :slotId].Status__c
			);
			try {
				EventAppointmentsController.setStatus(slotId, 'Booked');
				Assert.fail('Booked goes through book()');
			} catch (AuraHandledException refused) {
				Assert.areEqual(
					'Cancelled',
					[SELECT Status__c FROM Event_Appointment__c WHERE Id = :slotId].Status__c
				);
			}
		}
	}

	@IsTest
	static void aSlotCannotBeMarkedBookedWithoutAPerson() {
		System.runAs(staff()) {
			Datetime start = Datetime.now().addDays(30);
			Event__c event = conference(start);
			Contact priya = person('Priya');
			Event_Appointment__c slot = new Event_Appointment__c(
				Event__c = event.Id,
				Name = 'Priya',
				Host__c = priya.Id,
				Start__c = start.addHours(1),
				End__c = start.addHours(2),
				Status__c = 'Booked'
			);
			Database.SaveResult saved = Database.insert(slot, false, AccessLevel.USER_MODE);
			Assert.isFalse(saved.isSuccess(), 'R-EAP4');
			Event_Appointment__c noHost = new Event_Appointment__c(
				Event__c = event.Id,
				Name = 'No host',
				Start__c = start.addHours(1),
				End__c = start.addHours(2)
			);
			Assert.isFalse(
				Database.insert(noHost, false, AccessLevel.USER_MODE).isSuccess(),
				'R-EAP3'
			);
			Event_Appointment__c backwards = new Event_Appointment__c(
				Event__c = event.Id,
				Name = 'Backwards',
				Host__c = priya.Id,
				Start__c = start.addHours(2),
				End__c = start.addHours(1)
			);
			Assert.isFalse(
				Database.insert(backwards, false, AccessLevel.USER_MODE).isSuccess(),
				'R-EAP1'
			);
		}
	}

	@IsTest
	static void readOnlyPeopleCannotAddOrBook() {
		User viewer = TestUsers.standardUserWith(
			'EventViewer',
			new List<String>{ 'BarnCRM_Read_Only', 'Events_Read_Only' }
		);
		Event__c event;
		System.runAs(staff()) {
			event = conference(Datetime.now().addDays(30));
		}
		System.runAs(viewer) {
			EventAppointmentsController.Appointments result = EventAppointmentsController.getAppointments(
				event.Id
			);
			Assert.isFalse(result.canAdd, 'Read Only cannot add slots');
			Assert.isFalse(result.canBook, 'Read Only cannot book');
		}
	}
}
