/**
 * The shipped volunteer hours import template (V-06, canonical model Section 29V, R-VH1 to
 * R-VH3): 251 rows load as hours, a row whose email or job finds nobody is reported and not
 * loaded, imported hours start Submitted (or Approved when approval is off), approved hours
 * stay locked and are never touched by an import, and the module's install adds the template.
 *
 * The importer is a Standard User holding BarnCRM Admin (the import) and Volunteers Staff (the
 * hours), not an administrator, since the load runs in that user's own access. The people are
 * Contacts, or person Accounts in an org whose template is the person account one, so the tests
 * pass on an org with and without person accounts.
 */
@IsTest(testFor='ApexClass:VolunteersPostInstall, ApexClass:VolunteerHoursService')
private class VolunteerHoursImportTest {
    private static final Integer MANY = 251;
    private static final String IMPORTER = 'Importer';
    private static final String JOB_NAME = 'Food pantry sort';
    private static final String TEMPLATE_KEY = 'volunteer_hours';

    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            TestDataFactory.createUser(
                IMPORTER,
                new List<String>{ 'BarnCRM_Admin', 'Volunteers_Staff' }
            );
            VolunteersTestData.job(JOB_NAME);
        }
    }

    private static User importer() {
        return [SELECT Id FROM User WHERE LastName = :IMPORTER AND IsActive = TRUE LIMIT 1];
    }

    /** The shipped template this org materializes, for the org's own people. */
    private static Import_Template__c template() {
        ImportTemplateService.materializeDefaults();
        return [
            SELECT
                Id,
                Person_Mode__c,
                Target_Object__c,
                Load_Operation__c,
                Column_Mapping_JSON__c,
                Default_Values_JSON__c,
                Matching_Rule__c,
                Lookup_Not_Found__c,
                Several_Matches__c,
                Is_Package_Default__c,
                Active__c,
                Name
            FROM Import_Template__c
            WHERE Template_Key__c = :TEMPLATE_KEY
            WITH SYSTEM_MODE
        ];
    }

    private static Boolean accountsHoldPeople(Import_Template__c shipped) {
        return ImportTemplateService.isPersonAccountMode(shipped);
    }

    private static Schema.SObjectField personField(Import_Template__c shipped) {
        return accountsHoldPeople(shipped)
            ? Volunteer_Hours__c.Account__c
            : Volunteer_Hours__c.Contact__c;
    }

    /** The emails of this many new people, as the template's people mode holds them. */
    private static List<String> people(Import_Template__c shipped, Integer howMany) {
        List<String> emails = new List<String>();
        List<SObject> records = new List<SObject>();
        for (Integer i = 0; i < howMany; i++) {
            String email = 'vol' + i + '@example.org';
            emails.add(email);
            if (accountsHoldPeople(shipped)) {
                Account person = new Account();
                person.put('LastName', 'Unteer' + i);
                person.put('RecordTypeId', OrgShapeDetector.creatablePersonRecordTypeId());
                person.put('PersonEmail', email);
                records.add(person);
            } else {
                records.add(new Contact(FirstName = 'Vol', LastName = 'Unteer' + i, Email = email));
            }
        }
        insert records;
        return emails;
    }

    private static Map<String, String> row(String email, String job, String hours) {
        return new Map<String, String>{
            'Email' => email,
            'Job' => job,
            'Date' => '2026-03-14',
            'Hours' => hours,
            'Notes' => 'Sorted donations'
        };
    }

    private static List<Map<String, String>> rowsFor(List<String> emails) {
        List<Map<String, String>> values = new List<Map<String, String>>();
        for (String email : emails) {
            values.add(row(email, JOB_NAME, '2.5'));
        }
        return values;
    }

    private static Import_Batch__c lastBatch;

    /** Loads the rows with the shipped template as one chunk, committing. */
    private static ImportRowProcessor.Outcome load(
        Import_Template__c shipped,
        List<Map<String, String>> values
    ) {
        Import_Batch__c batch = ImportTestDataFactory.batch(shipped);
        ImportTestDataFactory.rows(batch, values);
        ImportBatchService.beginPass(batch.Id);
        List<Import_Row__c> staged = ImportTestDataFactory.reload(batch.Id);
        lastBatch = ImportBatchSelector.selectById(batch.Id);
        return ImportRowProcessor.process(
            lastBatch,
            ImportTemplateSelector.selectById(shipped.Id),
            ImportMapping.parse(shipped.Column_Mapping_JSON__c, shipped.Default_Values_JSON__c),
            staged,
            false
        );
    }

    private static String rejections() {
        List<String> errors = new List<String>();
        for (Import_Row__c staged : [
            SELECT Row_Number__c, Error_Message__c
            FROM Import_Row__c
            WHERE Import_Batch__c = :lastBatch.Id
            WITH SYSTEM_MODE
            ORDER BY Row_Number__c
        ]) {
            if (String.isNotBlank(staged.Error_Message__c)) {
                errors.add(staged.Row_Number__c + ': ' + staged.Error_Message__c);
            }
        }
        return String.join(errors, '; ');
    }

    private static List<Volunteer_Hours__c> hours() {
        return [
            SELECT
                Contact__c,
                Account__c,
                Volunteer_Job__c,
                Date_Worked__c,
                Hours__c,
                Notes__c,
                Status__c,
                Approved_By__c
            FROM Volunteer_Hours__c
            WITH SYSTEM_MODE
            ORDER BY CreatedDate
        ];
    }

    @IsTest
    static void theTemplateLoadsOneObjectAndMatchesPeopleByEmailAndJobsByName() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Import_Template__c shipped = template();

            Assert.areEqual('Volunteer_Hours__c', shipped.Target_Object__c, 'Loads hours.');
            Assert.areEqual(ImportObjectSchema.OPERATION_INSERT, shipped.Load_Operation__c);
            Assert.areEqual(
                ImportObjectSchema.LOOKUP_REJECT,
                shipped.Lookup_Not_Found__c,
                'A row that finds nobody is rejected.'
            );
            Assert.isTrue(shipped.Active__c, 'Offered.');
            Assert.isTrue(
                shipped.Column_Mapping_JSON__c.contains(
                    accountsHoldPeople(shipped) ? 'PersonEmail' : '"Email"'
                ),
                'The person is found by email.'
            );
            Assert.isTrue(shipped.Column_Mapping_JSON__c.contains('"Name"'), 'The job by name.');
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Import_Template__c WHERE Template_Key__c = :TEMPLATE_KEY],
                'One template, whichever people mode: the other row is not materialized.'
            );
        }
    }

    @IsTest
    static void aTwoHundredFiftyOneRowFileCreatesSubmittedHoursForTheMatchedPeople() {
        Import_Template__c shipped;
        List<String> emails;
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            VolunteersTestData.volunteerSettings(true, false);
            shipped = template();
            emails = people(shipped, MANY);
        }

        System.runAs(importer()) {
            Test.startTest();
            ImportRowProcessor.Outcome outcome = load(shipped, rowsFor(emails));
            Test.stopTest();

            Assert.areEqual(MANY, outcome.created, 'Every row loads: ' + rejections());
            Assert.areEqual(0, outcome.rejected, 'None rejected.');
        }

        List<Volunteer_Hours__c> loaded = hours();
        Assert.areEqual(MANY, loaded.size(), 'One entry per row.');
        Set<Id> people = new Set<Id>();
        for (Volunteer_Hours__c entry : loaded) {
            Assert.areEqual('Submitted', entry.Status__c, 'Waiting for a coordinator.');
            Assert.isNull(entry.Approved_By__c, 'Nobody approved them.');
            Assert.areEqual(2.5, entry.Hours__c, 'Hours read.');
            Assert.areEqual(Date.newInstance(2026, 3, 14), entry.Date_Worked__c, 'Date read.');
            Assert.areEqual('Sorted donations', entry.Notes__c, 'Notes read.');
            people.add((Id) entry.get(personField(shipped)));
        }
        Assert.areEqual(MANY, people.size(), 'Each row found its own person by email.');
    }

    @IsTest
    static void aRowWhoseEmailOrJobFindsNobodyIsReportedAndNotLoaded() {
        Import_Template__c shipped;
        List<String> emails;
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            shipped = template();
            emails = people(shipped, 3);
        }
        List<Map<String, String>> values = new List<Map<String, String>>{
            row(emails[0], JOB_NAME, '1'),
            row('nobody@example.org', JOB_NAME, '1'),
            row(emails[1], 'No such job', '1'),
            row(emails[2], JOB_NAME.toUpperCase(), '1')
        };

        System.runAs(importer()) {
            Test.startTest();
            ImportRowProcessor.Outcome outcome = load(shipped, values);
            Test.stopTest();

            Assert.areEqual(2, outcome.created, 'The matched rows load: ' + rejections());
            Assert.areEqual(2, outcome.rejected, 'The two that find nobody are reported.');
            String reasons = rejections();
            Assert.isTrue(reasons.contains('nobody@example.org'), 'Names the email: ' + reasons);
            Assert.isTrue(
                reasons.contains(Schema.SObjectType.Volunteer_Job__c.getLabel()),
                'Names the job, found by name in the same upload (C-49c): ' + reasons
            );
        }
        Assert.areEqual(2, hours().size(), 'Nothing was created for the rejected rows.');
        Assert.isTrue(
            [SELECT Name FROM Volunteer_Job__c WHERE Name = :JOB_NAME].Name.equals(JOB_NAME),
            'The job keeps its name, not renamed to the row\'s capitals.'
        );
    }

    @IsTest
    static void hoursAreApprovedAtOnceOnlyWhenApprovalIsOff() {
        Import_Template__c shipped;
        List<String> emails;
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            VolunteersTestData.volunteerSettings(false, false);
            shipped = template();
            emails = people(shipped, 2);
        }

        System.runAs(importer()) {
            Test.startTest();
            ImportRowProcessor.Outcome outcome = load(shipped, rowsFor(emails));
            Test.stopTest();
            Assert.areEqual(2, outcome.created, 'Loaded: ' + rejections());
        }

        for (Volunteer_Hours__c entry : hours()) {
            Assert.areEqual('Approved', entry.Status__c, 'Approval is off.');
            Assert.areEqual(importer().Id, entry.Approved_By__c, 'By the person who imported.');
        }
    }

    @IsTest
    static void aTemplateNamingApprovedCannotSkipApproval() {
        Import_Template__c shipped;
        List<String> emails;
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            VolunteersTestData.volunteerSettings(true, false);
            shipped = template();
            emails = people(shipped, 2);
            // An administrator edits the shipped template to name Approved instead of Submitted.
            shipped.Default_Values_JSON__c = '{"version": 1, "defaults": [{"target": "Volunteer_Hours__c.Status__c", "value": "Approved"}]}';
            update shipped;
        }

        System.runAs(importer()) {
            Test.startTest();
            ImportRowProcessor.Outcome outcome = load(shipped, rowsFor(emails));
            Test.stopTest();

            Assert.areEqual(0, outcome.created, 'Nothing loads Approved: ' + rejections());
            Assert.areEqual(2, outcome.rejected, 'Each row is refused.');
            Assert.isTrue(
                rejections().contains(Label.Volunteers_Hours_StatusThroughApproval),
                'Says approval goes through a coordinator: ' + rejections()
            );
        }
        Assert.areEqual(0, hours().size(), 'No hours skipped approval.');
    }

    @IsTest
    static void approvedHoursStayLockedAndAnImportNeverChangesThem() {
        Import_Template__c shipped;
        List<String> emails;
        Volunteer_Hours__c approved;
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            VolunteersTestData.volunteerSettings(true, false);
            shipped = template();
            emails = people(shipped, 1);
        }

        System.runAs(importer()) {
            load(shipped, rowsFor(emails));
        }
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteerHoursService.approve(new Map<Id, Volunteer_Hours__c>(hours()).keySet());
        }
        approved = hours()[0];
        Assert.areEqual('Approved', approved.Status__c, 'A coordinator approved it.');

        System.runAs(importer()) {
            // The same person, job and date again: a new entry, never a change to the old one.
            ImportRowProcessor.Outcome again = load(shipped, rowsFor(emails));
            Assert.areEqual(1, again.created, 'Added beside it: ' + rejections());

            // And the approved entry cannot be edited by anyone, the importer included.
            String refusal = '';
            try {
                update new Volunteer_Hours__c(Id = approved.Id, Hours__c = 9);
            } catch (DmlException locked) {
                refusal = locked.getMessage();
            }
            Assert.isTrue(String.isNotBlank(refusal), 'An approved entry is locked.');
        }

        Volunteer_Hours__c unchanged = [
            SELECT Hours__c, Status__c
            FROM Volunteer_Hours__c
            WHERE Id = :approved.Id
            WITH SYSTEM_MODE
        ];
        Assert.areEqual(2.5, unchanged.Hours__c, 'The approved hours were not changed.');
        Assert.areEqual('Approved', unchanged.Status__c, 'Still approved.');
        Assert.areEqual(2, hours().size(), 'The import added one entry.');
    }

    @IsTest
    static void theInstallAddsTheTemplateOnceAndOnlyForTheOrgsPeople() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Test.startTest();
            Test.testInstall(new VolunteersPostInstall(), null);
            Test.testInstall(new VolunteersPostInstall(), new Version(1, 0), true);
            Test.stopTest();

            List<Import_Template__c> added = [
                SELECT Person_Mode__c, Target_Object__c, Is_Package_Default__c
                FROM Import_Template__c
                WHERE Template_Key__c = :TEMPLATE_KEY
            ];
            Assert.areEqual(1, added.size(), 'Once, however often it installs.');
            Assert.areEqual(ImportTemplateService.defaultPersonMode(), added[0].Person_Mode__c);
            Assert.areEqual('Volunteer_Hours__c', added[0].Target_Object__c);
            Assert.isTrue(added[0].Is_Package_Default__c, 'Marked as shipped.');
        }
    }
}
