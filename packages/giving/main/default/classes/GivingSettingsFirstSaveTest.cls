/**
 * The first save of the Giving settings, by every writer that can make it.
 *
 * Until an org saves its Giving settings there is no record, and `getOrgDefaults()` returns one
 * whose checkboxes are all false. Each of these writers used to save that record as it came, so
 * whichever ran first (often a nightly job) switched off three features that ship on: applying
 * gifts to installments, household soft credits, and the receipt logo. Every test here starts
 * with no record, makes one save, and asserts those three are still on (ADR-0035).
 */
@IsTest
private class GivingSettingsFirstSaveTest {
    private static final String PERMISSION_SET = 'GivingFirstSaveTestAccess';

    /** The console save needs Manage Nonprofit Settings, committed before a test runs. */
    @TestSetup
    static void grantPermission() {
        SettingsTestPermissions.grantTo(PERMISSION_SET, UserInfo.getUserId());
    }

    private static void assertNoRecordYet() {
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Giving_Settings__c],
            'The org has never saved its Giving settings'
        );
    }

    private static Giving_Settings__c stored() {
        List<Giving_Settings__c> rows = [
            SELECT
                Id,
                Auto_Apply_Gifts_To_Installments__c,
                Automatic_Household_Soft_Credits__c,
                Receipt_Print_Logo__c,
                Acknowledgments_Last_Run__c,
                Acknowledgments_Last_Run_Summary__c,
                Donor_Levels_Last_Recalculated__c,
                Books_Closed_Through__c,
                Installment_Top_Up_Last_Run__c,
                Installment_Overdue_Last_Run__c,
                Receipt_Number_Prefix__c
            FROM Giving_Settings__c
            WHERE SetupOwnerId = :UserInfo.getOrganizationId()
        ];
        Assert.areEqual(1, rows.size(), 'One org-level Giving settings record');
        return rows[0];
    }

    private static void assertShippedOnKept(Giving_Settings__c saved, String writer) {
        Assert.isTrue(
            saved.Auto_Apply_Gifts_To_Installments__c,
            writer + ' left gifts applying to installments, as it ships'
        );
        Assert.isTrue(
            saved.Automatic_Household_Soft_Credits__c,
            writer + ' left household soft credits on, as they ship'
        );
        Assert.isTrue(
            saved.Receipt_Print_Logo__c,
            writer + ' left the receipt logo on, as it ships'
        );
    }

    @IsTest
    static void anAcknowledgmentRunAsTheFirstSaveKeepsTheShippedDefaults() {
        assertNoRecordYet();

        Test.startTest();
        AcknowledgmentService.recordLastRun('Sent 3 thank yous.');
        Test.stopTest();

        Giving_Settings__c saved = stored();
        Assert.areEqual(
            'Sent 3 thank yous.',
            saved.Acknowledgments_Last_Run_Summary__c,
            'The run is recorded'
        );
        assertShippedOnKept(saved, 'AcknowledgmentService.recordLastRun');
    }

    @IsTest
    static void aDonorLevelStampAsTheFirstSaveKeepsTheShippedDefaults() {
        assertNoRecordYet();
        Datetime completedAt = System.now();

        Test.startTest();
        DonorLevelWriter.stampRecalculation(completedAt);
        Test.stopTest();

        Giving_Settings__c saved = stored();
        Assert.areEqual(
            completedAt,
            saved.Donor_Levels_Last_Recalculated__c,
            'The recalculation is stamped'
        );
        assertShippedOnKept(saved, 'DonorLevelWriter.stampRecalculation');
    }

    @IsTest
    static void closingAPeriodAsTheFirstSaveKeepsTheShippedDefaults() {
        assertNoRecordYet();
        Date closeDate = Date.today().addDays(-30);
        Assert.isNull(
            AccountingPeriodWriter.lockedClosedThrough(),
            'No period is closed on an org that has never saved'
        );

        Test.startTest();
        AccountingPeriodWriter.saveClosedThrough(closeDate);
        Test.stopTest();

        Giving_Settings__c saved = stored();
        Assert.areEqual(closeDate, saved.Books_Closed_Through__c, 'The books are closed');
        Assert.areEqual(
            closeDate,
            AccountingPeriodWriter.lockedClosedThrough(),
            'And the locked read sees the stored date'
        );
        assertShippedOnKept(saved, 'AccountingPeriodWriter.saveClosedThrough');
    }

    @IsTest
    static void aTopUpRunAsTheFirstSaveKeepsTheShippedDefaults() {
        assertNoRecordYet();
        Datetime completedAt = System.now();

        Test.startTest();
        CommitmentService.recordTopUpRun(completedAt, 'Added 4 installments.');
        Test.stopTest();

        Giving_Settings__c saved = stored();
        Assert.areEqual(completedAt, saved.Installment_Top_Up_Last_Run__c, 'The run is recorded');
        assertShippedOnKept(saved, 'CommitmentService.recordTopUpRun');
    }

    @IsTest
    static void anOverdueRunAsTheFirstSaveKeepsTheShippedDefaults() {
        assertNoRecordYet();
        Datetime completedAt = System.now();

        Test.startTest();
        CommitmentService.recordOverdueRun(completedAt, 'Nothing overdue.');
        Test.stopTest();

        Giving_Settings__c saved = stored();
        Assert.areEqual(completedAt, saved.Installment_Overdue_Last_Run__c, 'The run is recorded');
        assertShippedOnKept(saved, 'CommitmentService.recordOverdueRun');
    }

    @IsTest
    static void aConsoleSaveAsTheFirstSaveKeepsTheShippedDefaults() {
        assertNoRecordYet();

        Test.startTest();
        SettingsService.saveValues(
            'Giving_Settings__c',
            new Map<String, Object>{ 'Receipt_Number_Prefix__c' => 'R-' }
        );
        Test.stopTest();

        Giving_Settings__c saved = stored();
        Assert.areEqual('R-', saved.Receipt_Number_Prefix__c, 'The setting is saved');
        assertShippedOnKept(saved, 'The settings console');
    }

    /**
     * From the first save on, the stored value governs, including a deliberate off, and a run
     * record writes only its own keys.
     */
    @IsTest
    static void laterSavesLeaveADeliberateOffAlone() {
        insert new Giving_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Auto_Apply_Gifts_To_Installments__c = false,
            Automatic_Household_Soft_Credits__c = false,
            Receipt_Print_Logo__c = false,
            Receipt_Number_Prefix__c = 'GIFT-'
        );
        Datetime completedAt = System.now();

        Test.startTest();
        AcknowledgmentService.recordLastRun('Sent 1 thank you.');
        DonorLevelWriter.stampRecalculation(completedAt);
        AccountingPeriodWriter.saveClosedThrough(Date.today().addDays(-30));
        CommitmentService.recordTopUpRun(completedAt, 'Added 1 installment.');
        CommitmentService.recordOverdueRun(completedAt, 'Nothing overdue.');
        Test.stopTest();

        Giving_Settings__c saved = stored();
        Assert.isFalse(saved.Auto_Apply_Gifts_To_Installments__c, 'A deliberate off stays off');
        Assert.isFalse(saved.Automatic_Household_Soft_Credits__c, 'So does this one');
        Assert.isFalse(saved.Receipt_Print_Logo__c, 'And this one');
        Assert.areEqual('GIFT-', saved.Receipt_Number_Prefix__c, 'Other keys are untouched');
        Assert.areEqual(completedAt, saved.Installment_Overdue_Last_Run__c, 'Each run recorded');
    }
}
