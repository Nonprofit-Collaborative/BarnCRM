/**
 * The nightly donor level and score pass writes only the values it changed (architect review
 * RT-09): a donor whose level and scores did not move is not written at all, and one that moved
 * goes out as its Id and the changed fields only.
 */
@IsTest(testFor='ApexClass:DonorLevelWriter')
private class DonorLevelWriterTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Giving_Admin');
    }

    @IsTest
    static void onlyChangedValuesOfChangedRecordsAreWritten() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact still = new Contact(LastName = 'Nguyen', RFM_Score__c = 3);
            Contact moved = new Contact(LastName = 'Okafor', RFM_Score__c = 3);
            insert new List<Contact>{ still, moved };
            List<Contact> read = [
                SELECT Id, LastName, RFM_Score__c, Account.Name
                FROM Contact
                WHERE Id IN :new List<Id>{ still.Id, moved.Id }
                ORDER BY LastName
            ];
            Map<Id, SObject> before = new Map<Id, SObject>();
            for (Contact record : read) {
                before.put(record.Id, record.clone(true, true, true, true));
            }
            read[1].RFM_Score__c = 5;

            List<SObject> slim = DonorLevelWriter.changedOnly(read, before);
            Integer written = DonorLevelWriter.saveChanged(read, before);

            Assert.areEqual(1, slim.size(), 'The donor that did not move is not written.');
            Map<String, Object> fields = slim[0].getPopulatedFieldsAsMap();
            Assert.areEqual(2, fields.size(), 'Its Id and the one changed value: ' + fields);
            Assert.areEqual(5, ((Decimal) fields.get('RFM_Score__c')).intValue(), 'New score.');
            Assert.areEqual(1, written, 'One record written.');
            Contact saved = [SELECT RFM_Score__c FROM Contact WHERE Id = :moved.Id];
            Assert.areEqual(5, saved.RFM_Score__c.intValue(), 'Saved.');
        }
    }
}
