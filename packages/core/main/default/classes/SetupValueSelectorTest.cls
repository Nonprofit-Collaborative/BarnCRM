/**
 * Tests for SetupValueSelector (ADR-NEXT): the values Setup holds that the settings console
 * shows read only.
 */
@IsTest(testFor='ApexClass:SetupValueSelector')
private class SetupValueSelectorTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    @IsTest
    static void theOrganizationNameIsTheOneSetupHolds() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual(
                [SELECT Name FROM Organization WITH SYSTEM_MODE LIMIT 1].Name,
                SetupValueSelector.valueOf('Organization', 'Name'),
                'Read from Company Information, with no copy in BarnCRM'
            );
        }
    }

    @IsTest
    static void theFiscalYearStartIsAMonthName() {
        System.runAs(TestUsers.admin()) {
            FiscalYearSelector.setTestStartMonth(10);

            Assert.areEqual(
                FiscalYearSelector.monthName(10),
                SetupValueSelector.valueOf('Organization', 'FiscalYearStartMonth'),
                'The month the rollups use, as a person reads it'
            );
        }
    }

    @IsTest
    static void onlyTheListedValuesAreShown() {
        System.runAs(TestUsers.admin()) {
            Assert.isTrue(
                SetupValueSelector.supports('Organization', 'name'),
                'Capitals do not matter'
            );
            Assert.isFalse(SetupValueSelector.supports('Organization', 'Phone'), 'Not listed');
            Assert.isFalse(SetupValueSelector.supports('Account', 'Name'), 'Not the org');
            Assert.isFalse(SetupValueSelector.supports(null, 'Name'), 'No object');
            Assert.isNull(
                SetupValueSelector.valueOf('Organization', 'Phone'),
                'An unlisted key reads as nothing'
            );
        }
    }
}
