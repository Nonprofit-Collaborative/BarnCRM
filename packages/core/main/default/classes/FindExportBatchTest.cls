/**
 * Find's export to Files (canonical model R-SQ12, ADR-NEXT `NEXT-find-export-to-files.md`):
 * every matching row up to the export limit, as R-SQ3's CSV, in parts the person owns, and one
 * notification opening the first file.
 *
 * The job is driven through its own start, execute and finish, as the bulk job tests do, except
 * the controller test, which runs it at Test.stopTest. These tests have not been executed: no
 * org in this environment.
 */
@IsTest
private class FindExportBatchTest {
    private static final String VOLUNTEERS = JSON.serialize(
        new Map<String, Object>{
            'version' => 1,
            'object' => 'Contact',
            'fields' => new List<Object>{ 'LastName', 'Title', 'Account.Name' },
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
        DataProtectedFields.definitionsOverride = new List<Rollup_Definition__c>();
        Account organization = new Account(Name = 'Springfield, "Food" Bank');
        insert organization;
        List<Contact> people = new List<Contact>();
        for (Integer index = 0; index < volunteers + staff; index++) {
            people.add(
                new Contact(
                    AccountId = organization.Id,
                    LastName = index == 0 ? '=SUM(A1)' : 'Person ' + index,
                    Title = index < volunteers ? 'Volunteer' : 'Staff'
                )
            );
        }
        insert people;
    }

    private static void notifications() {
        insert new BarnCRM_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Job_Notifications__c = true
        );
        SettingsService.clearCaches();
    }

    private static void run(FindExportBatch job) {
        List<SObject> scope = new List<SObject>();
        Database.QueryLocatorIterator records = job.start(null).iterator();
        while (records.hasNext()) {
            scope.add(records.next());
        }
        job.execute(null, scope);
        job.finish(null);
    }

    private static List<ContentVersion> parts(String tag) {
        String titles = '%-' + tag + '-part-%';
        return [
            SELECT Title, ContentDocumentId, VersionData
            FROM ContentVersion
            WHERE Title LIKE :titles AND IsLatest = TRUE
            ORDER BY CreatedDate, Id
        ];
    }

    private static Integer dataLines(ContentVersion part) {
        // The header, then one line per row, each ending CRLF.
        return part.VersionData.toString().split('\r\n').size() - 1;
    }

    @IsTest
    static void twoHundredFiftyRowsAreWrittenInPartsWithTheHeaderAndOneNotification() {
        System.runAs(TestUsers.admin()) {
            makePeople(250, 20);
            notifications();
            FindExportBatch.rowsPerPart = 100;
            run(
                new FindExportBatch(
                    VOLUNTEERS,
                    new Map<String, String>{
                        'LastName' => 'Last Name',
                        'Account.Name' => 'Household'
                    },
                    'abc123',
                    FindController.exportLimit()
                )
            );

            List<ContentVersion> written = parts('abc123');
            Assert.areEqual(3, written.size(), 'Parts of 100, 100 and 50 rows.');
            Assert.areEqual(100, dataLines(written[0]));
            Assert.areEqual(50, dataLines(written[2]));
            Assert.isTrue(written[0].Title.startsWith('Contact-'), written[0].Title);
            Assert.isTrue(written[2].Title.endsWith('-abc123-part-3'), written[2].Title);
            String first = written[0].VersionData.toString();
            Assert.areEqual(65279, first.charAt(0), 'A byte-order mark first.');
            Assert.isTrue(first.contains('Id,Last Name,Title,Household\r\n'), first.left(80));
            Assert.isTrue(first.contains(',\'=SUM(A1),Volunteer,'), 'A formula is kept as text.');
            Assert.isTrue(first.contains('"Springfield, ""Food"" Bank"'), 'Quoted as R-SQ3 says.');
            Assert.isFalse(first.contains('Staff'), 'Only the matching rows.');

            Assert.areEqual(1, JobNotifier.sent.size(), 'One notification.');
            Assert.areEqual(written[0].ContentDocumentId, JobNotifier.sent[0].targetId);
            Assert.isTrue(JobNotifier.sent[0].body.contains('250'), JobNotifier.sent[0].body);
        }
    }

    @IsTest
    static void theServerNeverWritesMoreRowsThanTheExportLimit() {
        System.runAs(TestUsers.admin()) {
            makePeople(200, 0);
            run(new FindExportBatch(VOLUNTEERS, null, 'def456', 30));
            List<ContentVersion> written = parts('def456');
            Assert.areEqual(1, written.size());
            Assert.areEqual(30, dataLines(written[0]), 'Stopped at the limit (FINDA-6).');
        }
    }

    @IsTest
    static void theControllerStartsTheJobAndListsOnlyItsOwnFiles() {
        System.runAs(TestUsers.admin()) {
            makePeople(200, 0);
            FindController.ServerExport started;
            Test.startTest();
            started = FindController.startServerExport(
                VOLUNTEERS,
                JSON.serialize(new Map<String, String>{ 'LastName' => 'Last Name' })
            );
            Test.stopTest();
            Assert.isTrue(Pattern.matches('[0-9a-f]{6}', started.tag), started.tag);

            FindController.ServerExport status = FindController.serverExportStatus(
                started.jobId,
                started.tag
            );
            Assert.isTrue(status.done, status.status);
            Assert.isFalse(status.failed);
            Assert.areEqual(1, status.files.size());
            Assert.areEqual(201, dataLines(parts(started.tag)[0]) + 1, 'Header and 200 rows.');
            try {
                FindController.serverExportStatus(started.jobId, '%');
                Assert.fail('A tag that is not one is refused.');
            } catch (AuraHandledException refused) {
                Assert.areEqual(System.Label.Core_Find_ExportFilesNotFound, refused.getMessage());
            }
        }
    }

    @IsTest
    static void aQueryThatWouldNotRunIsRefusedBeforeAnyJobStarts() {
        System.runAs(TestUsers.admin()) {
            try {
                FindController.startServerExport('{"version":1,"object":"No_Such__c"}', null);
                Assert.fail('Refused.');
            } catch (AuraHandledException refused) {
                Assert.isNotNull(refused.getMessage());
            }
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'FindExportBatch']
            );
        }
    }
}
