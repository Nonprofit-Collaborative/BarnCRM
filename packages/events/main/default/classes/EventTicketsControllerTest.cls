/**
 * Dana sets up the gala's tickets: General and Student, and a code for early birds. The Tickets
 * tab lists them in order with the event's capacity, and a code is used once per event, whatever
 * its case (EV-03, R-TT1 to R-TT4, R-PC1 to R-PC4).
 */
@IsTest(
	testFor='ApexClass:EventTicketsController, ApexClass:EventKeyHandler, ApexTrigger:PromoCodeTrigger'
)
private class EventTicketsControllerTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	private static User staff() {
		return TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	private static Event__c gala() {
		Datetime start = Datetime.now().addDays(30);
		Event__c record = new Event__c(
			Name = 'Spring Gala',
			Status__c = 'Open',
			Format__c = 'In Person',
			Start__c = start,
			End__c = start.addHours(4),
			Capacity__c = 100
		);
		insert as user record;
		return record;
	}

	@IsTest
	static void listsTicketsInOrderAndCodes() {
		System.runAs(staff()) {
			Event__c event = gala();
			Ticket_Type__c student = new Ticket_Type__c(
				Event__c = event.Id,
				Name = 'Student',
				Price__c = 20,
				Sort_Order__c = 2
			);
			Ticket_Type__c general = new Ticket_Type__c(
				Event__c = event.Id,
				Name = 'General',
				Price__c = 50,
				Quantity__c = 80,
				Sort_Order__c = 1
			);
			insert as user new List<Ticket_Type__c>{ student, general };
			insert as user new Promo_Code__c(
				Event__c = event.Id,
				Name = '  early  ',
				Discount_Type__c = 'Percent',
				Discount_Value__c = 10,
				Ticket_Type__c = general.Id
			);

			Test.startTest();
			EventTicketsController.Tickets result = EventTicketsController.getTickets(event.Id);
			Test.stopTest();

			Assert.areEqual(100, result.capacity, 'The event capacity');
			Assert.areEqual(2, result.tickets.size(), 'Both ticket types');
			Assert.areEqual('General', result.tickets[0].name, 'By sort order');
			Assert.areEqual(1, result.codes.size(), 'The code');
			Assert.areEqual('early', result.codes[0].code, 'Spaces trimmed');
			Assert.areEqual(general.Id, result.codes[0].ticketTypeId, 'Limited to General');
			Assert.isTrue(result.canAddTicket && result.canAddCode, 'Staff may add');
			Assert.areEqual(
				'Price',
				result.fieldLabels.get('Ticket_Type__c.Price__c'),
				'Column labels'
			);
		}
	}

	@IsTest
	static void refusesTheSameCodeTwiceInOneEventWhateverItsCase() {
		System.runAs(staff()) {
			Event__c event = gala();
			insert as user new Promo_Code__c(
				Event__c = event.Id,
				Name = 'EARLY',
				Discount_Type__c = 'Amount',
				Discount_Value__c = 5
			);
			Promo_Code__c again = new Promo_Code__c(
				Event__c = event.Id,
				Name = 'early',
				Discount_Type__c = 'Amount',
				Discount_Value__c = 5
			);

			Test.startTest();
			Database.SaveResult saved = Database.insert(again, false, AccessLevel.USER_MODE);
			Test.stopTest();

			Assert.isFalse(saved.isSuccess(), 'A second EARLY is refused');
			Assert.isTrue(
				saved.getErrors()[0].getMessage().contains('early'),
				'The message names the code: ' + saved.getErrors()[0].getMessage()
			);
		}
	}

	@IsTest
	static void refusesTwoEqualCodesInOneSaveButAllowsThemInTwoEvents() {
		System.runAs(staff()) {
			Event__c first = gala();
			Event__c second = gala();
			List<Promo_Code__c> codes = new List<Promo_Code__c>{
				new Promo_Code__c(
					Event__c = first.Id,
					Name = 'VIP',
					Discount_Type__c = 'Percent',
					Discount_Value__c = 100
				),
				new Promo_Code__c(
					Event__c = first.Id,
					Name = 'vip',
					Discount_Type__c = 'Percent',
					Discount_Value__c = 50
				),
				new Promo_Code__c(
					Event__c = second.Id,
					Name = 'VIP',
					Discount_Type__c = 'Percent',
					Discount_Value__c = 100
				)
			};

			Test.startTest();
			List<Database.SaveResult> results = Database.insert(
				codes,
				false,
				AccessLevel.USER_MODE
			);
			Test.stopTest();

			Assert.isTrue(results[0].isSuccess(), 'The first VIP is saved');
			Assert.isFalse(results[1].isSuccess(), 'Its twin in the same event is refused');
			Assert.isTrue(results[2].isSuccess(), 'Another event may use VIP');
			Promo_Code__c saved = [
				SELECT Code_Key__c
				FROM Promo_Code__c
				WHERE Id = :results[0].getId()
				WITH USER_MODE
			];
			Assert.areEqual(String.valueOf(first.Id) + ':VIP', saved.Code_Key__c, 'The key');
		}
	}

	@IsTest
	static void validationRulesGuardPricesAndDiscounts() {
		System.runAs(staff()) {
			Event__c event = gala();
			Ticket_Type__c negative = new Ticket_Type__c(
				Event__c = event.Id,
				Name = 'Odd',
				Price__c = -1
			);
			Promo_Code__c tooMuch = new Promo_Code__c(
				Event__c = event.Id,
				Name = 'ALL',
				Discount_Type__c = 'Percent',
				Discount_Value__c = 120
			);

			Test.startTest();
			Database.SaveResult ticket = Database.insert(negative, false, AccessLevel.USER_MODE);
			Database.SaveResult code = Database.insert(tooMuch, false, AccessLevel.USER_MODE);
			Test.stopTest();

			Assert.isFalse(ticket.isSuccess(), 'R-TT1: no negative price');
			Assert.isFalse(code.isSuccess(), 'R-PC2: a percent at most 100');
		}
	}

	@IsTest
	static void readOnlyPeopleCannotAdd() {
		User viewer = TestUsers.standardUserWith(
			'EventViewer',
			new List<String>{ 'BarnCRM_Read_Only', 'Events_Read_Only' }
		);
		Event__c event;
		System.runAs(staff()) {
			event = gala();
		}
		System.runAs(viewer) {
			Test.startTest();
			EventTicketsController.Tickets result = EventTicketsController.getTickets(event.Id);
			Test.stopTest();

			Assert.isFalse(result.canAddTicket, 'Read Only cannot add tickets');
			Assert.areEqual(0, result.tickets.size(), 'No tickets yet');
		}
	}
}
