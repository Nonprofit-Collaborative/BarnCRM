/**
 * The shipped program roster import template (P-06, canonical model 29ZA "Roster import"): an
 * upload of several objects (R-IT20) that finds each row's program by name and enrolls the
 * person found by email, with the stage, dates and intake fields; a row whose program or email
 * finds nothing, or whose person already has an open enrollment there, is reported and not
 * loaded; the program is never renamed; and the module's install adds the template.
 *
 * The importer is a Standard User holding BarnCRM Admin (the import) and Programs Staff (the
 * enrollments), since the load runs in that user's own access. The people are Contacts, or person
 * Accounts in an org whose template is the person account one.
 */
@IsTest(testFor='ApexClass:ProgramsPostInstall, ApexClass:EnrollmentService')
private class ProgramRosterImportTest {
    private static final String ADMIN = 'Programs_Admin';
    private static final String IMPORTER = 'Rosterimporter';
    private static final String TEMPLATE_KEY = 'program_roster';
    private static final Integer MANY = 120;

    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            TestDataFactory.createUser(
                IMPORTER,
                new List<String>{ 'BarnCRM_Admin', 'Programs_Staff' }
            );
            BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
                HouseholdTestDataFactory.MODE_CONTACT
            );
            settings.Auto_Create_Households__c = false;
            TestDataFactory.saveSettings(settings);
            insert new List<Program__c>{
                new Program__c(Name = 'Food Pantry'),
                new Program__c(Name = 'Tutoring')
            };
        }
    }

    private static User importer() {
        return [SELECT Id FROM User WHERE LastName = :IMPORTER AND IsActive = TRUE LIMIT 1];
    }

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

    /** The emails of this many new people, as the template's people mode holds them. */
    private static List<String> people(Import_Template__c shipped, Integer howMany) {
        List<String> emails = new List<String>();
        List<SObject> records = new List<SObject>();
        for (Integer i = 0; i < howMany; i++) {
            String email = 'roster' + i + '@example.org';
            emails.add(email);
            if (accountsHoldPeople(shipped)) {
                Account person = new Account();
                person.put('LastName', 'Roster' + i);
                person.put('RecordTypeId', OrgShapeDetector.creatablePersonRecordTypeId());
                person.put('PersonEmail', email);
                records.add(person);
            } else {
                records.add(new Contact(FirstName = 'Ros', LastName = 'Ter' + i, Email = email));
            }
        }
        insert records;
        return emails;
    }

    private static Map<String, String> row(String program, String email) {
        return new Map<String, String>{
            'Program' => program,
            'Email' => email,
            'Stage' => 'Enrolled',
            'Start Date' => '2026-09-01',
            'Intake Date' => '2026-08-25',
            'Referral Source' => 'School',
            'Eligibility Status' => 'Eligible',
            'Eligibility Date' => '2026-08-28'
        };
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

    @IsTest
    static void theTemplateLoadsEnrollmentsWithTheirProgramFoundByName() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Import_Template__c shipped = template();

            Assert.areEqual('Enrollment__c', shipped.Target_Object__c, 'Loads enrollments.');
            Assert.areEqual(ImportObjectSchema.OPERATION_INSERT, shipped.Load_Operation__c);
            Assert.isTrue(shipped.Active__c, 'Offered.');
            ImportMapping mapping = ImportMapping.parse(
                shipped.Column_Mapping_JSON__c,
                shipped.Default_Values_JSON__c
            );
            Assert.isTrue(mapping.loadsSeveralObjects(), 'Several objects in one upload (C-49c).');
            Assert.isNull(ImportObjectSchema.severalObjectsProblem(mapping), 'A valid upload.');
            Assert.isTrue(
                shipped.Column_Mapping_JSON__c.contains(
                    accountsHoldPeople(shipped) ? 'PersonEmail' : '"Email"'
                ),
                'The person is found by email.'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Import_Template__c WHERE Template_Key__c = :TEMPLATE_KEY],
                'One template, whichever people mode.'
            );
        }
    }

    @IsTest
    static void aRosterEnrollsEachPersonInTheProgramNamedOnTheRow() {
        Import_Template__c shipped;
        List<String> emails;
        System.runAs(TestUsers.adminWith(ADMIN)) {
            shipped = template();
            emails = people(shipped, MANY);
        }
        List<Map<String, String>> values = new List<Map<String, String>>();
        for (Integer i = 0; i < MANY; i++) {
            values.add(row(Math.mod(i, 2) == 0 ? 'Food Pantry' : 'Tutoring', emails[i]));
        }

        System.runAs(importer()) {
            Test.startTest();
            ImportRowProcessor.Outcome outcome = load(shipped, values);
            Test.stopTest();

            Assert.areEqual(MANY, outcome.created, 'Every row enrolls: ' + rejections());
            Assert.areEqual(0, outcome.rejected, 'None rejected.');
        }

        List<Enrollment__c> loaded = [
            SELECT
                Program__r.Name,
                Stage__c,
                Start_Date__c,
                Intake_Date__c,
                Referral_Source__c,
                Eligibility_Status__c,
                Eligibility_Date__c,
                Contact__c,
                Account__c
            FROM Enrollment__c
            WITH SYSTEM_MODE
        ];
        Assert.areEqual(MANY, loaded.size(), 'One enrollment per row.');
        Integer pantry = 0;
        for (Enrollment__c each : loaded) {
            pantry += each.Program__r.Name == 'Food Pantry' ? 1 : 0;
            Assert.areEqual('Enrolled', each.Stage__c, 'Stage read.');
            Assert.areEqual(Date.newInstance(2026, 9, 1), each.Start_Date__c, 'Start read.');
            Assert.areEqual(Date.newInstance(2026, 8, 25), each.Intake_Date__c, 'Intake read.');
            Assert.areEqual('School', each.Referral_Source__c, 'Referral read.');
            Assert.areEqual('Eligible', each.Eligibility_Status__c, 'Eligibility read.');
            Assert.areEqual(
                Date.newInstance(2026, 8, 28),
                each.Eligibility_Date__c,
                'Typed date kept.'
            );
            Assert.isTrue(each.Contact__c != null || each.Account__c != null, 'A person found.');
        }
        Assert.areEqual(MANY / 2, pantry, 'Half to each program.');
        Assert.areEqual(2, [SELECT COUNT() FROM Program__c], 'No program created.');
    }

    @IsTest
    static void aRowThatFindsNothingOrRepeatsAnOpenEnrollmentIsReported() {
        Import_Template__c shipped;
        List<String> emails;
        System.runAs(TestUsers.adminWith(ADMIN)) {
            shipped = template();
            emails = people(shipped, 3);
        }
        Map<String, String> noStage = row('Tutoring', emails[1]);
        noStage.remove('Stage');
        noStage.remove('Start Date');
        List<Map<String, String>> values = new List<Map<String, String>>{
            row('Food Pantry', emails[0]),
            noStage,
            row('No Such Program', emails[1]),
            row('Food Pantry', 'nobody@example.org'),
            row('FOOD PANTRY', emails[2]),
            row('Food Pantry', emails[0])
        };

        System.runAs(importer()) {
            Test.startTest();
            ImportRowProcessor.Outcome outcome = load(shipped, values);
            Test.stopTest();

            String reasons = rejections();
            Assert.areEqual(3, outcome.created, 'The three good rows load: ' + reasons);
            Assert.areEqual(3, outcome.rejected, 'Three reported: ' + reasons);
            Assert.isTrue(reasons.contains('nobody@example.org'), 'Names the email: ' + reasons);
        }
        Assert.areEqual(3, [SELECT COUNT() FROM Enrollment__c], 'Nothing else was created.');
        Enrollment__c blank = [
            SELECT Stage__c, Start_Date__c
            FROM Enrollment__c
            WHERE Program__r.Name = 'Tutoring'
            WITH SYSTEM_MODE
        ];
        Assert.areEqual('Enrolled', blank.Stage__c, 'A blank stage is Enrolled.');
        Assert.areEqual(Date.today(), blank.Start_Date__c, 'And its start date is filled in.');
        List<String> names = new List<String>();
        for (Program__c each : [SELECT Name FROM Program__c ORDER BY Name]) {
            names.add(each.Name);
        }
        Assert.isTrue(
            names.equals(new List<String>{ 'Food Pantry', 'Tutoring' }),
            'No program renamed, not even to another case: ' + names
        );
    }
}
