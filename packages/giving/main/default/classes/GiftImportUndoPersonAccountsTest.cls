/**
 * Undoing a gift import that created person accounts: the same undo as `GiftImportUndoTest`
 * where people are stored as accounts (canonical model R-IB9, ADR-0119). A Platform only org
 * has none (ADR-0013), so there the setup imports nothing and the test returns at once: the
 * contact shape is covered by `GiftImportUndoTest`.
 */
@IsTest(testFor='ApexClass:GiftImportProcessor')
private class GiftImportUndoPersonAccountsTest {
    private static Boolean personAccountsOrg() {
        return OrgShapeDetector.hasPersonAccounts() == true &&
            OrgShapeDetector.creatablePersonRecordTypeId() != null;
    }

    @TestSetup
    static void importDonors() {
        GiftImportUndoTest.createUsers();
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            if (personAccountsOrg()) {
                HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
                GiftImportUndoTest.imported(ImportTemplateService.PERSON_MODE_PERSON_ACCOUNTS);
            }
        }
    }

    @IsTest
    static void undoingRemovesPersonAccountsWhoseTotalsTheUndoRecalculated() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            if (!personAccountsOrg()) {
                return;
            }
            Id batchId = GiftImportUndoTest.batch().Id;
            Set<Id> personTypes = OrgShapeDetector.personAccountRecordTypeIds();
            Assert.areEqual(
                3,
                [
                    SELECT COUNT()
                    FROM Account
                    WHERE Created_By_Import_Batch__c = :batchId AND RecordTypeId IN :personTypes
                ],
                'Three person accounts were imported.'
            );

            GiftImportUndoTest.undo(batchId);

            Assert.areEqual(
                0,
                GiftImportUndoTest.taggedLeft(batchId),
                'Every person and household the import made goes.'
            );
        }
    }
}
