/**
 * Run state never touches a setting.
 *
 * Each writer here records what a run or a page did (a last run, a recalculation, the books
 * closed date) as Giving run state, never as a setting, so the three features that ship on
 * (applying gifts to installments, household soft credits, and the receipt logo) stay on, and a
 * deliberate off stays off (ADR-0035). A settings save changes only the setting it names.
 */
@IsTest(
	testFor='ApexClass:CommitmentService, ApexClass:AccountingPeriodWriter, ApexClass:AcknowledgmentService, ApexClass:DonorLevelWriter'
)
private class GivingSettingsFirstSaveTest {
	private static final String PERMISSION_SET = 'GivingFirstSaveTestAccess';

	/** The settings save needs Manage BarnCRM Settings, committed before a test runs. */
	@TestSetup
	static void grantPermission() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			SettingsTestPermissions.grantTo(PERMISSION_SET, UserInfo.getUserId());
		}
	}

	private static void assertShippedOnKept(String writer) {
		Assert.isTrue(
			ModuleSettings.flag('Auto_Apply_Gifts_To_Installments'),
			writer + ' left gifts applying to installments, as it ships'
		);
		Assert.isTrue(
			ModuleSettings.flag('Giving_Automatic_Household_Soft_Credits'),
			writer + ' left household soft credits on, as they ship'
		);
		Assert.isTrue(ModuleSettings.flag('Giving_Receipt_Print_Logo'), writer + ' left the receipt logo on, as it ships');
	}

	@IsTest
	static void anAcknowledgmentRunKeepsTheShippedDefaults() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Test.startTest();
			AcknowledgmentService.recordLastRun('Sent 3 thank yous.');
			Test.stopTest();

			Assert.areEqual(
				'Sent 3 thank yous.',
				GivingState.text(GivingState.ACKNOWLEDGMENTS_SUMMARY),
				'The run is recorded'
			);
			Assert.isNotNull(GivingState.moment(GivingState.ACKNOWLEDGMENTS_LAST_RUN), 'With its time');
			assertShippedOnKept('AcknowledgmentService.recordLastRun');
		}
	}

	@IsTest
	static void aDonorLevelStampKeepsTheShippedDefaults() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Datetime completedAt = Datetime.newInstance(2026, 6, 1, 9, 0, 0);

			Test.startTest();
			DonorLevelWriter.stampRecalculation(completedAt);
			Test.stopTest();

			Assert.areEqual(
				completedAt,
				GivingState.moment(GivingState.DONOR_LEVELS_RECALCULATED),
				'The recalculation is stamped'
			);
			assertShippedOnKept('DonorLevelWriter.stampRecalculation');
		}
	}

	@IsTest
	static void closingAPeriodKeepsTheShippedDefaults() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Date closeDate = Date.today().addDays(-30);
			Assert.isNull(AccountingPeriodWriter.lockedClosedThrough(), 'No period is closed yet');

			Test.startTest();
			AccountingPeriodWriter.saveClosedThrough(closeDate);
			Test.stopTest();

			Assert.areEqual(closeDate, GivingState.dateValue(GivingState.BOOKS_CLOSED_THROUGH), 'The books are closed');
			Assert.areEqual(
				closeDate,
				AccountingPeriodWriter.lockedClosedThrough(),
				'And the locked read sees the stored date'
			);
			assertShippedOnKept('AccountingPeriodWriter.saveClosedThrough');
		}
	}

	@IsTest
	static void aTopUpRunKeepsTheShippedDefaults() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Datetime completedAt = Datetime.newInstance(2026, 6, 1, 9, 0, 0);

			Test.startTest();
			CommitmentService.recordTopUpRun(completedAt, 'Added 4 installments.');
			Test.stopTest();

			Assert.areEqual(
				completedAt,
				GivingState.moment(GivingState.INSTALLMENT_TOP_UP_LAST_RUN),
				'The run is recorded'
			);
			assertShippedOnKept('CommitmentService.recordTopUpRun');
		}
	}

	@IsTest
	static void anOverdueRunKeepsTheShippedDefaults() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Datetime completedAt = Datetime.newInstance(2026, 6, 1, 9, 0, 0);

			Test.startTest();
			CommitmentService.recordOverdueRun(completedAt, 'Nothing overdue.');
			Test.stopTest();

			Assert.areEqual(
				completedAt,
				GivingState.moment(GivingState.INSTALLMENT_OVERDUE_LAST_RUN),
				'The run is recorded'
			);
			assertShippedOnKept('CommitmentService.recordOverdueRun');
		}
	}

	@IsTest
	static void aSettingsSaveKeepsTheShippedDefaults() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Test.startTest();
			Id deployment = ModuleSettings.save(new Map<String, Object>{ 'Giving_Receipt_Number_Prefix' => 'R-' });
			Test.stopTest();

			Assert.isNotNull(deployment, 'The save returns its deployment');
			Assert.areEqual('R-', ModuleSettings.text('Giving_Receipt_Number_Prefix'), 'The setting is saved');
			assertShippedOnKept('A settings save');
		}
	}

	/** Before anything is saved, the shipped values are read, so a feature in effect never shows as off (ADMIN-4). */
	@IsTest
	static void theShippedDefaultsAreReadBeforeAnySave() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Test.startTest();
			Object autoApply = SettingsService.getValue('Giving_Settings__c', 'Auto_Apply_Gifts_To_Installments__c');
			Object softCredits = SettingsService.getValue('Giving_Settings__c', 'Automatic_Household_Soft_Credits__c');
			Object logo = SettingsService.getValue('Giving_Settings__c', 'Receipt_Print_Logo__c');
			Test.stopTest();

			Assert.areEqual(true, autoApply, 'Applying gifts to installments reads as on');
			Assert.areEqual(true, softCredits, 'Household soft credits read as on');
			Assert.areEqual(true, logo, 'The receipt logo reads as on');
		}
	}

	/** The stored value governs, including a deliberate off, and a run writes only its own keys. */
	@IsTest
	static void runsLeaveADeliberateOffAlone() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			ModuleSettings.setForTest('Auto_Apply_Gifts_To_Installments', false);
			ModuleSettings.setForTest('Giving_Automatic_Household_Soft_Credits', false);
			ModuleSettings.setForTest('Giving_Receipt_Print_Logo', false);
			ModuleSettings.setForTest('Giving_Receipt_Number_Prefix', 'GIFT-');
			Datetime completedAt = Datetime.newInstance(2026, 6, 1, 9, 0, 0);

			Test.startTest();
			AcknowledgmentService.recordLastRun('Sent 1 thank you.');
			DonorLevelWriter.stampRecalculation(completedAt);
			AccountingPeriodWriter.saveClosedThrough(Date.today().addDays(-30));
			CommitmentService.recordTopUpRun(completedAt, 'Added 1 installment.');
			CommitmentService.recordOverdueRun(completedAt, 'Nothing overdue.');
			Test.stopTest();

			Assert.isFalse(ModuleSettings.flag('Auto_Apply_Gifts_To_Installments'), 'A deliberate off stays off');
			Assert.isFalse(ModuleSettings.flag('Giving_Automatic_Household_Soft_Credits'), 'So does this one');
			Assert.isFalse(ModuleSettings.flag('Giving_Receipt_Print_Logo'), 'And this one');
			Assert.areEqual('GIFT-', ModuleSettings.text('Giving_Receipt_Number_Prefix'), 'Other keys are untouched');
			Assert.areEqual(
				completedAt,
				GivingState.moment(GivingState.INSTALLMENT_OVERDUE_LAST_RUN),
				'Each run recorded'
			);
		}
	}
}
