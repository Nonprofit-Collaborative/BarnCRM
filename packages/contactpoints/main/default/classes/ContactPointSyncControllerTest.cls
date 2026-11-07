/**
 * Maria opens the Contact Point Sync page: she sees what each kind can do here, the preview
 * count, and starts the backfill, which records what it did; the page refuses in words when the
 * org cannot copy anything or she lacks the permission (ADR-NEXT contact point sync module,
 * decisions 10 and 11).
 */
@IsTest(testFor='ApexClass:ContactPointSyncController')
private class ContactPointSyncControllerTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
		TestUsers.standardUser('Reader');
	}

	private static Contact person(String lastName, String email) {
		return (Contact) TestDataFactory.pastDuplicateRules(
			new Contact(LastName = lastName, Personal_Email__c = email)
		);
	}

	@IsTest
	static void showsEachKindAndTheCounts() {
		System.runAs(TestUsers.admin()) {
			ContactPointSyncService.missingForTest.add(ContactPointPlan.ADDRESS);
			Database.insert(person('Rivera', 'ana@home.example'), AccessLevel.SYSTEM_MODE);
			ContactPointSyncController.countCap = 0;

			Test.startTest();
			ContactPointSyncController.Status status = ContactPointSyncController.getStatus();
			Test.stopTest();

			Assert.areEqual(3, status.kinds.size(), 'Email, phone and address');
			for (ContactPointSyncController.KindStatus line : status.kinds) {
				Assert.isTrue(String.isNotBlank(line.message), line.kind + ' says what it does');
				if (line.kind == ContactPointPlan.ADDRESS) {
					Assert.isFalse(line.ready, 'The missing object is explained, not copied');
				}
			}
			Assert.isTrue(status.peopleCountCapped, 'More people than the cap say so');
			Assert.areEqual(0, status.peopleCount);
			Assert.isTrue(status.canRun, 'An admin holds Manage BarnCRM Settings');
			Assert.isFalse(status.running);
		}
	}

	@IsTest
	static void theBackfillCopiesEveryoneAndRecordsWhatItDid() {
		System.runAs(TestUsers.admin()) {
			if (ContactPointSyncService.activeKinds().isEmpty()) {
				return;
			}
			AutomationControl.bypass('Contact_Point_Sync_Person');
			Database.insert(
				new List<Contact>{
					person('Rivera', 'ana@home.example'),
					person('Ortiz', 'sam@home.example'),
					person('Lee', 'lee@home.example')
				},
				AccessLevel.SYSTEM_MODE
			);
			AutomationControl.clearBypass('Contact_Point_Sync_Person');

			Test.startTest();
			ContactPointSyncController.Status started = ContactPointSyncController.runBackfill();
			Test.stopTest();

			Assert.isTrue(started.running, 'The page shows it running');
			Assert.areEqual(
				3,
				[SELECT COUNT() FROM Contact_Point_Link__c WITH SYSTEM_MODE],
				'Everyone already here is copied'
			);
			ContactPointSyncController.Status after = ContactPointSyncController.getStatus();
			Assert.isNotNull(after.lastBackfill, 'When it finished');
			Assert.isTrue(after.lastSummary.contains('3'), 'What it did: ' + after.lastSummary);
			Assert.areEqual(3, after.managedCount);
			Assert.isTrue(
				ContactPointSyncService.switchedOn(ContactPointPlan.EMAIL),
				'Recording the run keeps the switches on'
			);
		}
	}

	@IsTest
	static void refusesInWords() {
		ContactPointSyncController.Status nothing;
		System.runAs(TestUsers.admin()) {
			ContactPointSyncService.missingForTest.add('Individual');
			nothing = ContactPointSyncController.getStatus();
		}
		Assert.isFalse(nothing.anyReady);
		Assert.areEqual(
			BarnHelp.text('ContactPoints', 'ContactPoints_Page_NothingToCopy'),
			ContactPointSyncController.refusal(nothing),
			'Nothing to copy says so'
		);
		nothing.canRun = false;
		Assert.areEqual(
			BarnHelp.text('ContactPoints', 'ContactPoints_Page_NoManagePermission'),
			ContactPointSyncController.refusal(nothing),
			'Without Manage BarnCRM Settings, says what is needed'
		);
		System.runAs(TestUsers.standardUser('Reader')) {
			try {
				ContactPointSyncController.runBackfill();
				Assert.fail('Someone without the permission cannot start it');
			} catch (AuraHandledException refused) {
				Assert.isNotNull(refused.getMessage());
			}
		}
	}
}
