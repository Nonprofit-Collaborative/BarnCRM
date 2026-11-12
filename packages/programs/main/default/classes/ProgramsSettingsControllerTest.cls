/**
 * The Programs settings page's server side (P-07, canonical model 29ZA): the intake picklists with
 * their choices, default and Setup link for someone who may manage settings, and nothing for
 * anyone else.
 */
@IsTest(testFor='ApexClass:ProgramsSettingsController')
private class ProgramsSettingsControllerTest {
	private static final String ADMIN = 'Programs_Admin';

	@TestSetup
	static void createTestUsers() {
		TestUsers.adminWith(ADMIN);
		TestUsers.standardUserWith(
			'Reader',
			new List<String>{ 'BarnCRM_Read_Only', 'Programs_Read_Only' }
		);
	}

	@IsTest
	static void anAdminSeesTheIntakePicklistsWithTheirSetupLinks() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Test.startTest();
			ProgramsSettingsController.Settings settings = ProgramsSettingsController.getSettings();
			Test.stopTest();

			Assert.isTrue(settings.canManage, 'An admin manages settings.');
			Assert.areEqual(3, settings.intakePicklists.size(), 'Three intake picklists.');
			ProgramsSettingsController.Picklist status = settings.intakePicklists[1];
			Assert.areEqual('Eligibility_Status__c', status.apiName, 'In page order.');
			Assert.isTrue(status.values.contains('Not Screened'), 'Its choices.');
			Assert.areEqual('Not Screened', status.defaultValue, 'Its default.');
			Assert.isNull(settings.intakePicklists[0].defaultValue, 'Referral Source has none.');
			for (ProgramsSettingsController.Picklist each : settings.intakePicklists) {
				Assert.isTrue(
					each.setupUrl.startsWith('/lightning/setup/ObjectManager/') &&
					each.setupUrl.endsWith('/view'),
					'A Setup link: ' + each.setupUrl
				);
			}
		}
	}

	@IsTest
	static void aReaderGetsNothing() {
		System.runAs(TestUsers.standardUserWith(
			'Reader',
			new List<String>{ 'BarnCRM_Read_Only', 'Programs_Read_Only' }
		)) {
			Test.startTest();
			ProgramsSettingsController.Settings settings = ProgramsSettingsController.getSettings();
			Test.stopTest();

			Assert.isFalse(settings.canManage, 'Read Only manages nothing.');
			Assert.areEqual(0, settings.intakePicklists.size(), 'No picklists.');
		}
	}

	@IsTest
	static void anAdminSavesTheParticipantPrivacyPresetOrgWide() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Assert.areEqual(
				ProgramsSharing.SHARED,
				ProgramsSettingsController.getSettings().participantPrivacy,
				'Shared until an admin chooses'
			);

			Test.startTest();
			ProgramsSettingsController.Settings saved = ProgramsSettingsController.savePrivacy(
				true
			);
			Test.stopTest();

			Assert.areEqual(ProgramsSharing.PRIVATE_PRESET, saved.participantPrivacy, 'Private');
			Assert.isTrue(ProgramsSharing.isPrivate(), 'Saved org-wide');
			Assert.areEqual(
				ProgramsSharing.SHARED,
				ProgramsSettingsController.savePrivacy(false).participantPrivacy,
				'And back to Shared'
			);
		}
	}

	@IsTest
	static void aPageThatCannotLoadIsRefusedWithAMessage() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			// A broken entry in the list makes the read fail the way an unreadable field would.
			ProgramsSettingsController.INTAKE_PICKLISTS.add(null);
			try {
				ProgramsSettingsController.getSettings();
				Assert.fail('The page could not be read');
			} catch (AuraHandledException refused) {
				Assert.areEqual(
					BarnHelp.text('Programs', 'Programs_Fail_SettingsLoad'),
					refused.getMessage(),
					'Told in the page\'s words'
				);
			}
		}
	}

	@IsTest
	static void aReaderCannotSaveThePrivacyPreset() {
		System.runAs(TestUsers.standardUserWith(
			'Reader',
			new List<String>{ 'BarnCRM_Read_Only', 'Programs_Read_Only' }
		)) {
			try {
				ProgramsSettingsController.savePrivacy(true);
				Assert.fail('Refused');
			} catch (AuraHandledException refused) {
				Assert.areEqual(
					BarnHelp.text('Programs', 'Programs_Settings_NoAccess'),
					refused.getMessage(),
					'Told why'
				);
			}
			Assert.isFalse(ProgramsSharing.isPrivate(), 'Nothing changed');
		}
	}
}
