/**
 * Download these records first (canonical model R-BD8): every record a bulk delete would delete,
 * read page by page in Id order as the person, with every field they may read, and nothing
 * deleted. The delete by file's download is tested in `DeleteByFileTest`.
 */
@IsTest(testFor='ApexClass:BulkDeleteService, ApexClass:BulkDeleteController')
private class BulkDeleteBackupTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static final String VOLUNTEERS = JSON.serialize(
        new Map<String, Object>{
            'version' => 1,
            'object' => 'Contact',
            'fields' => new List<Object>{ 'LastName' },
            'filter' => new Map<String, Object>{
                'version' => 1,
                'conditions' => new List<Object>{
                    new Map<String, Object>{
                        'id' => 1,
                        'field' => 'Title',
                        'operator' => 'equals',
                        'value' => 'Volunteer'
                    }
                }
            }
        }
    );

    private static void makePeople(Integer volunteers, Integer staff) {
        DataProtectedFields.targetsOverride = new Map<String, Set<String>>();
        Account organization = new Account(Name = 'Springfield Food Bank');
        insert organization;
        List<Contact> people = new List<Contact>();
        for (Integer index = 0; index < volunteers + staff; index++) {
            people.add(
                new Contact(
                    AccountId = organization.Id,
                    LastName = 'Person ' + String.valueOf(index).leftPad(4, '0'),
                    Title = index < volunteers ? 'Volunteer' : 'Staff',
                    MailingCity = 'Springfield'
                )
            );
        }
        insert people;
    }

    private static User deleter() {
        return TestUsers.withPermissionSets(
            new List<String>{ TestUsers.CORE_ADMIN, 'BarnCRM_Bulk_Delete' }
        );
    }

    @IsTest
    static void readsTwoHundredAndFiftyRecordsInPagesWithEveryReadableField() {
        System.runAs(TestUsers.admin()) {
            makePeople(250, 20);
            System.runAs(deleter()) {
                List<SObject> rows = new List<SObject>();
                Set<Id> seen = new Set<Id>();
                BulkDeleteService.BackupPage page;
                String afterId = null;
                Integer pages = 0;
                do {
                    page = BulkDeleteController.backupPage(VOLUNTEERS, null, afterId);
                    rows.addAll(page.rows);
                    for (SObject row : page.rows) {
                        seen.add(row.Id);
                    }
                    afterId = page.lastId;
                    pages++;
                } while (!page.done && pages < 5);

                Assert.areEqual(2, pages, 'Two pages of up to 200.');
                Assert.areEqual(250, rows.size(), 'Every volunteer, and only them.');
                Assert.areEqual(250, seen.size(), 'No record twice.');
                Assert.areEqual('Contact', page.objectName);
                Set<String> names = new Set<String>();
                for (BulkDeleteService.BackupColumn column : page.columns) {
                    names.add(column.fieldName);
                }
                Assert.areEqual('Id', page.columns[0].fieldName, 'The record ID first.');
                Assert.isTrue(names.contains('LastName') && names.contains('MailingCity'));
                Assert.isFalse(names.contains('MailingAddress'), 'Compound fields are left out.');
                Assert.areEqual('Springfield', rows[0].get('MailingCity'));
            }
            Assert.areEqual(270, [SELECT COUNT() FROM Contact], 'Nothing is deleted.');
        }
    }

    @IsTest
    static void aPersonWhoMayNotBulkDeleteCannotDownloadThroughIt() {
        System.runAs(TestUsers.admin()) {
            makePeople(2, 0);
            try {
                BulkDeleteController.backupPage(VOLUNTEERS, null, null);
                Assert.fail('Refused.');
            } catch (AuraHandledException refused) {
                Assert.areEqual(
                    System.Label.Core_BulkDelete_ErrorNoPermission,
                    refused.getMessage()
                );
            }
        }
    }
}
