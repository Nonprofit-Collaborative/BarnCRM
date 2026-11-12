/**
 * The public volunteer pages and their form (V-09, R-VJ3, R-VU10): only Open shifts still to come
 * of public, active jobs are listed and shown, with places as a count; a full shift is closed
 * unless the waitlist is on; a person's own page shows only behind a checked signed claim; a
 * shift form books the person with their group and guardian; a profile form updates only the
 * person the sign-up names.
 */
@IsTest(
	testFor='ApexClass:VolunteerPublicPage, ApexClass:VolunteerFormAttachment, ApexClass:VolunteerReminderService'
)
private class VolunteerPublicPageTest {
	@TestSetup
	static void makeData() {
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			VolunteersTestData.contactModeWithoutAutomaticHouseholds();
			VolunteersTestData.contacts(3);
			Volunteer_Job__c open = new Volunteer_Job__c(
				Name = 'Food pantry sort',
				Active__c = true,
				Public_Page__c = true
			);
			Volunteer_Job__c hidden = new Volunteer_Job__c(Name = 'Board prep', Active__c = true);
			insert new List<Volunteer_Job__c>{ open, hidden };
			open.Signup_Form_Key__c = open.Id;
			update open;
			Volunteer_Shift__c shown = VolunteersTestData.newShift(
				open.Id,
				Datetime.now().addDays(7),
				3
			);
			shown.Volunteers_Needed__c = 1;
			shown.Location__c = 'Back dock';
			insert new List<Volunteer_Shift__c>{
				shown,
				VolunteersTestData.newShift(hidden.Id, Datetime.now().addDays(7), 3)
			};
		}
	}

	private static User admin() {
		return TestUsers.adminWith(VolunteersTestData.ADMIN);
	}

	private static Volunteer_Shift__c shiftOf(String jobName) {
		return [
			SELECT Id
			FROM Volunteer_Shift__c
			WHERE Volunteer_Job__r.Name = :jobName
			WITH SYSTEM_MODE
			LIMIT 1
		];
	}

	private static List<Contact> people() {
		return [SELECT Id FROM Contact WITH SYSTEM_MODE ORDER BY LastName];
	}

	private static FormSubmissionReceipt receipt(
		Id contextId,
		Id personId,
		Map<String, Object> answers
	) {
		FormSubmissionReceipt receipt = new FormSubmissionReceipt();
		receipt.contextRecordId = contextId;
		receipt.personId = personId;
		receipt.answers = answers;
		return receipt;
	}

	@IsTest
	static void onlyPublicShiftsAreListedAndShown() {
		System.runAs(admin()) {
			VolunteerPublicPage pages = new VolunteerPublicPage();
			Volunteer_Shift__c shown = shiftOf('Food pantry sort');

			Test.startTest();
			Map<String, Object> listed = pages.listPage();
			Map<String, Object> page = pages.page(shown.Id);
			Map<String, Object> hidden = pages.page(shiftOf('Board prep').Id);
			Test.stopTest();

			List<Object> items = (List<Object>) listed.get('items');
			Assert.areEqual(1, items.size(), 'Only the public job.');
			Assert.areEqual(shown.Id, ((Map<String, Object>) items[0]).get('recordId'));
			Assert.isNull(hidden, 'A job not on the public page has no page.');
			Assert.areEqual('Food pantry sort', page.get('title'));
			Assert.areEqual('Open', page.get('registration'), 'A place is left.');
			Assert.isNotNull(page.get('formId'), 'The job form is offered.');
			String facts = JSON.serialize(page.get('facts'));
			Assert.isTrue(facts.contains('Back dock'), 'The place: ' + facts);
			Assert.isTrue(
				facts.contains(BarnHelp.text('Volunteers', 'Volunteers_Public_PlacesLeftOne')),
				facts
			);
		}
	}

	@IsTest
	static void aFullShiftClosesUnlessTheWaitlistIsOn() {
		System.runAs(admin()) {
			Volunteer_Shift__c shift = shiftOf('Food pantry sort');
			insert VolunteersTestData.newSignup(shift.Id, people()[0].Id);

			Test.startTest();
			Map<String, Object> closed = new VolunteerPublicPage().page(shift.Id);
			OrgSettingsSystemWriter.save(
				Volunteer_Settings__c.SObjectType,
				new Map<Schema.SObjectField, Object>{
					Volunteer_Settings__c.Waitlist_Enabled__c => true
				}
			);
			SettingsService.clearCaches();
			Map<String, Object> waitlist = new VolunteerPublicPage().page(shift.Id);
			Test.stopTest();

			Assert.areEqual('Closed', closed.get('registration'), 'Full, no waitlist.');
			Assert.areEqual('Open', waitlist.get('registration'), 'Full, waitlist on.');
			Assert.areEqual(
				BarnHelp.text('Volunteers', 'Volunteers_Public_SignUpWaitlist'),
				waitlist.get('message')
			);
		}
	}

	@IsTest
	static void aShiftFormBooksThePersonWithTheirGroupAndGuardian() {
		System.runAs(admin()) {
			Volunteer_Shift__c shift = shiftOf('Food pantry sort');
			List<Contact> people = people();
			FormSubmissionReceipt submitted = receipt(
				shift.Id,
				people[0].Id,
				new Map<String, Object>{ 'groupSize' => '2', 'groupName' => 'Rivera family' }
			);
			submitted.recordIds.put('guardian', people[1].Id);
			VolunteerFormAttachment attachment = new VolunteerFormAttachment();

			Test.startTest();
			attachment.received(submitted);
			Test.stopTest();

			Volunteer_Signup__c booked = [
				SELECT Contact__c, Group_Size__c, Group_Name__c, Status__c
				FROM Volunteer_Signup__c
				WITH SYSTEM_MODE
			];
			Assert.areEqual(people[0].Id, booked.Contact__c, 'The matched person.');
			Assert.areEqual(
				2,
				booked.Group_Size__c,
				'Over target is allowed for a form already sent (R-VS4).'
			);
			Assert.areEqual('Rivera family', booked.Group_Name__c);
			Assert.areEqual(
				people[1].Id,
				VolunteerMinors.guardianByPerson.get(people[0].Id),
				'The guardian is kept.'
			);
			Assert.isFalse(attachment.signedClaim(shift.Id), 'A shift needs no claim.');
			Assert.areEqual(
				[SELECT Id FROM Volunteer_Job__c WHERE Name = 'Food pantry sort' WITH SYSTEM_MODE]
				.Id,
				attachment.formFor(shift.Id),
				'The job form.'
			);
		}
	}

	@IsTest
	static void thePersonalPageNeedsTheClaimAndTheProfileFormUpdatesOnlyThatPerson() {
		System.runAs(admin()) {
			List<Contact> people = people();
			Volunteer_Signup__c signup = VolunteersTestData.newSignup(
				shiftOf('Food pantry sort').Id,
				people[0].Id
			);
			insert signup;
			VolunteerFormAttachment attachment = new VolunteerFormAttachment();

			Test.startTest();
			Map<String, Object> unsigned = PublicPageExtensions.page(signup.Id);
			Map<String, Object> signed = PublicPageExtensions.page(signup.Id, true);
			attachment.received(
				receipt(
					signup.Id,
					people[2].Id,
					new Map<String, Object>{
						'emergencyContactName' => 'Lee Rivera',
						'emergencyContactPhone' => ''
					}
				)
			);
			Test.stopTest();

			Assert.isNull(unsigned, 'No claim, no page.');
			Assert.areEqual(
				BarnHelp.text('Volunteers', 'Volunteers_Public_MyTitle'),
				signed.get('title')
			);
			Assert.isTrue(
				JSON.serialize(signed.get('sections')).contains('Food pantry sort'),
				'The upcoming shift.'
			);
			Assert.isTrue(attachment.signedClaim(signup.Id), 'A sign-up needs a claim.');
			Map<Id, Contact> after = new Map<Id, Contact>(
				[SELECT Id, Emergency_Contact_Name__c FROM Contact WITH SYSTEM_MODE]
			);
			Assert.areEqual(
				'Lee Rivera',
				after.get(people[0].Id).Emergency_Contact_Name__c,
				'The sign-up person.'
			);
			Assert.isNull(
				after.get(people[2].Id).Emergency_Contact_Name__c,
				'Never the person the answers name.'
			);
			Assert.isNull(
				VolunteerReminderService.personalPageLink(signup.Id),
				'No profile form, no link.'
			);
		}
	}
}
