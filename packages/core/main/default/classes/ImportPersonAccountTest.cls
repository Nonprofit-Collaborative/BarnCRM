/**
 * Importing people stored as person accounts: a row written in contact terms (Email,
 * MailingStreet, HasOptedOutOfEmail) lands in the account's person fields, and the next load
 * of the same file finds the people it made by the same key (R-IB12).
 *
 * These tests need person accounts the running user can create, and return early where
 * there are none, for one of two reasons PersonAccountTestShape checks and logs: the
 * Platform-only shape Core must also run on (ADR-0013) has no person fields at all, and an
 * org that has them may give the user none of its person record types (a Nonprofit Cloud
 * trial), which is an org setup gap and means these tests did not run there. The person
 * fields are named only as text and read through dynamic SOQL, so this class compiles on
 * the Platform-only shape too (plan Section 4.2).
 */
@IsTest
private class ImportPersonAccountTest {
    private static Import_Template__c template;
    private static Import_Batch__c batch;

    /**
     * Person accounts the running user can create. An org can have person accounts and still
     * give the user none of its person types (a Nonprofit Cloud trial does not give its Person
     * Account record type to the System Administrator profile); the import then creates
     * nobody, which noPersonTypeGivenToTheUserCreatesNobodyAndSaysWhy proves.
     */
    private static Boolean orgHasPersonAccounts() {
        return PersonAccountTestShape.skipReason() == null && personFieldsExist();
    }

    private static Boolean personFieldsExist() {
        return OrgShapeDetector.detect().hasPersonAccounts &&
            ImportMatcher.accountHasField('PersonEmail');
    }

    private static String mapping() {
        ImportMapping mapping = ImportMapping.parse(ImportTestDataFactory.donorMapping());
        mapping.columns.add(new ImportMapping.Column('Street', 'Contact1.MailingStreet'));
        mapping.columns.add(new ImportMapping.Column('Zip', 'Contact1.MailingPostalCode'));
        mapping.columns.add(
            new ImportMapping.Column('Email Opt Out', 'Contact1.HasOptedOutOfEmail')
        );
        mapping.columns.add(new ImportMapping.Column('Do Not Call', 'Contact1.DoNotCall'));
        mapping.columns.add(new ImportMapping.Column('Birthdate', 'Contact1.Birthdate'));
        mapping.columns.add(new ImportMapping.Column('Title', 'Contact1.Title'));
        return mapping.serialize();
    }

    private static Map<String, String> anasRow(String title) {
        Map<String, String> row = ImportTestDataFactory.donorRow(
            'Ana',
            'Ramirez',
            'ana@example.org',
            null
        );
        row.put('Street', '12 Alder Street');
        row.put('Zip', '97201');
        row.put('Email Opt Out', 'Yes');
        row.put('Do Not Call', 'Yes');
        row.put('Birthdate', '1980-04-02');
        row.put('Title', title);
        return row;
    }

    private static void given(String rule, Map<String, String> row) {
        template = ImportTestDataFactory.template(mapping(), rule);
        template.Person_Mode__c = ImportTemplateService.PERSON_MODE_PERSON_ACCOUNTS;
        update template;
        batch = ImportTestDataFactory.batch(template);
        ImportTestDataFactory.rows(batch, new List<Map<String, String>>{ row });
    }

    private static ImportRowProcessor.Outcome run(Boolean dryRun) {
        return ImportRowProcessor.process(
            batch,
            template,
            ImportMapping.parse(template.Column_Mapping_JSON__c),
            ImportTestDataFactory.reload(batch.Id),
            dryRun
        );
    }

    private static List<SObject> people() {
        Set<Id> personTypes = OrgShapeDetector.detect().personAccountRecordTypeIds;
        return Database.queryWithBinds(
            'SELECT Id, PersonEmail, PersonMailingStreet, PersonMailingCity, ' +
                'PersonMailingPostalCode, PersonHasOptedOutOfEmail, PersonDoNotCall, ' +
                'PersonBirthdate, PersonTitle FROM Account WHERE RecordTypeId IN :personTypes',
            new Map<String, Object>{ 'personTypes' => personTypes },
            AccessLevel.SYSTEM_MODE
        );
    }

    @IsTest
    static void aPersonAccountGetsTheEmailAddressAndOptOuts() {
        System.runAs(TestUsers.admin()) {
            if (!orgHasPersonAccounts()) {
                // No person fields to write: the reason is checked and logged by PersonAccountTestShape.
                return;
            }
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            given(ImportTemplateService.RULE_EMAIL, anasRow('Treasurer'));

            Test.startTest();
            ImportRowProcessor.Outcome outcome = run(false);
            Test.stopTest();

            Assert.areEqual(1, outcome.created, 'The row created a person: ' + outcome.notes);
            List<SObject> people = people();
            Assert.areEqual(1, people.size(), 'One person account.');
            SObject ana = people[0];
            Assert.areEqual('ana@example.org', ana.get('PersonEmail'), 'The email stuck.');
            Assert.areEqual(
                '12 Alder Street',
                ana.get('PersonMailingStreet'),
                'So did the street.'
            );
            Assert.areEqual('Portland', ana.get('PersonMailingCity'), 'The city.');
            Assert.areEqual('97201', ana.get('PersonMailingPostalCode'), 'The postal code.');
            Assert.areEqual(true, ana.get('PersonHasOptedOutOfEmail'), 'The email opt-out.');
            Assert.areEqual(true, ana.get('PersonDoNotCall'), 'Do Not Call.');
            Assert.areEqual(Date.newInstance(1980, 4, 2), ana.get('PersonBirthdate'), 'Birthdate.');
            Assert.areEqual('Treasurer', ana.get('PersonTitle'), 'And the title.');
            for (String note : outcome.notes) {
                Assert.isFalse(
                    note.contains('which this org does not have'),
                    'No contact attribute was reported unknown to the account: ' + note
                );
            }
        }
    }

    /**
     * Where none of the org's person types is given to the person running the import, nobody
     * is created with a type the platform would refuse row by row: the run log says why once.
     */
    @IsTest
    static void noPersonTypeGivenToTheUserCreatesNobodyAndSaysWhy() {
        System.runAs(TestUsers.admin()) {
            if (!personFieldsExist()) {
                Assert.areEqual(
                    PersonAccountTestShape.NO_PERSON_ACCOUNTS,
                    PersonAccountTestShape.skipReason(),
                    'Only an org that does not store people as accounts lacks the person fields'
                );
                return;
            }
            OrgShapeDetector.OrgShape shape = OrgShapeDetector.detect();
            // A person type the describe does not know, so none is available to the user.
            shape.personAccountRecordTypeIds = new Set<Id>{ Id.valueOf('012000000000999') };
            OrgShapeDetector.overrideShape = shape;
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            given(ImportTemplateService.RULE_EMAIL, anasRow('Treasurer'));

            Test.startTest();
            ImportRowProcessor.Outcome outcome = run(false);
            Test.stopTest();

            Assert.areEqual(0, outcome.created, 'Nobody is created: ' + outcome.notes);
            Assert.isTrue(
                outcome.notes.contains(Label.Core_Import_LogPersonRecordTypeMissing),
                'The run log says why: ' + outcome.notes
            );
        }
    }

    @IsTest
    static void loadingTheFileAgainMatchesThePersonByEmail() {
        System.runAs(TestUsers.admin()) {
            if (!orgHasPersonAccounts()) {
                // No person accounts to match: the reason is checked and logged by PersonAccountTestShape.
                return;
            }
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            given(ImportTemplateService.RULE_EMAIL, anasRow('Treasurer'));
            run(false);
            Id first = people()[0].Id;

            given(ImportTemplateService.RULE_EMAIL, anasRow('Board Chair'));
            Test.startTest();
            ImportRowProcessor.Outcome preview = run(true);
            ImportRowProcessor.Outcome outcome = run(false);
            Test.stopTest();

            Assert.areEqual(0, preview.created, 'The dry run finds her rather than creating her.');
            Assert.areEqual(1, preview.updated, 'And says the new title would update her.');
            Assert.areEqual(0, outcome.created, 'So does the commit.');
            Assert.areEqual(1, outcome.updated, 'Which updates her.');
            List<SObject> people = people();
            Assert.areEqual(1, people.size(), 'Still one person account.');
            Assert.areEqual('Board Chair', people[0].get('PersonTitle'), 'With the new title.');
            Assert.areEqual(
                first,
                ImportTestDataFactory.reload(batch.Id)[0].Person_1_Account__c,
                'The row points at the person the first load made.'
            );
        }
    }

    @IsTest
    static void loadingTheFileAgainMatchesThePersonByNameAndPostalCode() {
        System.runAs(TestUsers.admin()) {
            if (!orgHasPersonAccounts()) {
                // No person accounts to match: the reason is checked and logged by PersonAccountTestShape.
                return;
            }
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            given(ImportTemplateService.RULE_NAME_POSTAL, anasRow('Treasurer'));
            run(false);

            given(ImportTemplateService.RULE_NAME_POSTAL, anasRow('Treasurer'));
            Test.startTest();
            ImportRowProcessor.Outcome outcome = run(false);
            Test.stopTest();

            Assert.areEqual(0, outcome.created, 'The person made by the first load is found.');
            Assert.areEqual(1, people().size(), 'Still one person account.');
        }
    }

    /**
     * The dry run remembers a person account it would create, because the commit now writes
     * the email the matcher reads: a later chunk counts them once (R-IB12).
     */
    @IsTest
    static void aDryRunRemembersAPersonAccountItWouldCreate() {
        System.runAs(TestUsers.admin()) {
            if (!orgHasPersonAccounts()) {
                // No person account to create: the reason is checked and logged by PersonAccountTestShape.
                return;
            }
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            given(ImportTemplateService.RULE_EMAIL, anasRow('Treasurer'));

            Test.startTest();
            run(true);
            Test.stopTest();

            // Read in system mode: the key is the package's own bookkeeping, never shown, and
            // the running user need not be granted it.
            List<Import_Row__c> rows = Database.queryWithBinds(
                'SELECT Person_1_Key__c FROM Import_Row__c WHERE Import_Batch__c = :batchId',
                new Map<String, Object>{ 'batchId' => batch.Id },
                AccessLevel.SYSTEM_MODE
            );
            Assert.isNotNull(
                rows[0].Person_1_Key__c,
                'The row carries the key a later chunk finds her by.'
            );
        }
    }

    /**
     * A person account another tool loaded often holds its postal code only in the billing
     * address. Name plus postal code still finds them there rather than creating them again.
     */
    @IsTest
    static void aPersonAccountWithOnlyABillingPostalCodeIsFound() {
        System.runAs(TestUsers.admin()) {
            if (!orgHasPersonAccounts()) {
                // No person accounts to match: the reason is checked and logged by PersonAccountTestShape.
                return;
            }
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            Account existing = new Account(
                RecordTypeId = OrgShapeDetector.creatablePersonRecordTypeId(),
                BillingPostalCode = '97201'
            );
            existing.put('FirstName', 'Ana');
            existing.put('LastName', 'Ramirez');
            insert existing;
            Map<String, String> row = anasRow('Treasurer');
            row.remove('Street');
            given(ImportTemplateService.RULE_NAME_POSTAL, row);

            Test.startTest();
            ImportRowProcessor.Outcome outcome = run(false);
            Test.stopTest();

            Assert.areEqual(
                0,
                outcome.created,
                'She is found, not created again: ' + outcome.notes
            );
            Assert.areEqual(1, people().size(), 'Still one person account.');
            Assert.areEqual(
                existing.Id,
                ImportTestDataFactory.reload(batch.Id)[0].Person_1_Account__c,
                'The row points at the person another tool loaded.'
            );
        }
    }

    /**
     * A full chunk of 200 person accounts: every one carries its own email and opt-outs, none
     * is made twice, and a dry run of the same file afterwards finds all 200 by email, which is
     * the promise a person accounts org's second monthly import depends on.
     */
    @IsTest
    static void aChunkOfTwoHundredPersonAccountsLoadsAndIsFoundAgain() {
        System.runAs(TestUsers.admin()) {
            if (!orgHasPersonAccounts()) {
                // No person accounts to create: the reason is checked and logged by PersonAccountTestShape.
                return;
            }
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            List<Map<String, String>> values = new List<Map<String, String>>();
            for (Integer i = 0; i < 200; i++) {
                Map<String, String> row = anasRow('Treasurer');
                row.put('First Name', 'Donor' + i);
                row.put('Last Name', 'Surname' + i);
                row.put('Email', 'donor' + i + '@example.org');
                row.put('Do Not Call', Math.mod(i, 2) == 0 ? 'Yes' : 'No');
                values.add(row);
            }
            template = ImportTestDataFactory.template(mapping(), ImportTemplateService.RULE_EMAIL);
            template.Person_Mode__c = ImportTemplateService.PERSON_MODE_PERSON_ACCOUNTS;
            update template;
            batch = ImportTestDataFactory.batch(template);
            ImportTestDataFactory.rows(batch, values);

            Test.startTest();
            ImportRowProcessor.Outcome outcome = run(false);
            Test.stopTest();

            Assert.areEqual(200, outcome.created, 'Every row created its person: ' + outcome.notes);
            Assert.areEqual(0, outcome.rejected, 'None was rejected.');
            Map<String, SObject> byEmail = new Map<String, SObject>();
            for (SObject person : people()) {
                byEmail.put((String) person.get('PersonEmail'), person);
            }
            Assert.areEqual(200, byEmail.size(), 'Two hundred people, each with their own email.');
            for (Integer i = 0; i < 200; i++) {
                SObject person = byEmail.get('donor' + i + '@example.org');
                Assert.isNotNull(person, 'Donor ' + i + ' is there under their own email.');
                Assert.areEqual(true, person.get('PersonHasOptedOutOfEmail'), 'With the opt-out.');
                Assert.areEqual(
                    Math.mod(i, 2) == 0,
                    person.get('PersonDoNotCall'),
                    'And their own Do Not Call, not a neighbour\'s.'
                );
            }

            ImportRowProcessor.Outcome again = run(true);
            Assert.areEqual(0, again.created, 'A dry run of the same file creates nobody.');
            Assert.areEqual(200, again.matched + again.updated, 'It finds all 200.');
        }
    }

    /**
     * A user who may read a person's mailing postal code but not the billing one is still
     * matched on the mailing one, and the run log names the billing one it could not use.
     * The user holds only a permission set made here: read on accounts and contacts, and on
     * the contact mailing address, which person account mailing fields follow.
     */
    @IsTest
    static void aPostalCodeTheUserCannotReadIsNamedWhileTheOtherStillMatches() {
        System.runAs(TestUsers.admin()) {
            if (!orgHasPersonAccounts()) {
                // No person accounts to match: the reason is checked and logged by PersonAccountTestShape.
                return;
            }
            User reader = new User(
                ProfileId = [
                    SELECT Id
                    FROM Profile
                    WHERE Name = 'Minimum Access - Salesforce'
                    LIMIT 1
                ]
                .Id,
                LastName = 'Mailonly',
                Email = 'mailonly@barncrm.test.invalid',
                Username = 'mailonly' + DateTime.now().getTime() + '@barncrm.test.invalid',
                Alias = 'mailonly',
                TimeZoneSidKey = 'America/Los_Angeles',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US'
            );
            System.runAs(new User(Id = UserInfo.getUserId())) {
                insert reader;
                PermissionSet access = new PermissionSet(
                    Name = 'Import_Mail_Only_' +
                        String.valueOf(Math.abs(Crypto.getRandomInteger())),
                    Label = 'Import mail only'
                );
                insert access;
                insert new List<ObjectPermissions>{
                    new ObjectPermissions(
                        ParentId = access.Id,
                        SobjectType = 'Account',
                        PermissionsRead = true
                    ),
                    new ObjectPermissions(
                        ParentId = access.Id,
                        SobjectType = 'Contact',
                        PermissionsRead = true
                    )
                };
                insert new FieldPermissions(
                    ParentId = access.Id,
                    SobjectType = 'Contact',
                    Field = 'Contact.MailingAddress',
                    PermissionsRead = true
                );
                insert new PermissionSetAssignment(
                    AssigneeId = reader.Id,
                    PermissionSetId = access.Id
                );
            }

            Test.startTest();
            System.runAs(reader) {
                ImportMatcher.forgetHeldKeys();
                ImportMatcher.personAccountsByNameAndPostalCode(
                    new Set<String>{ ImportMatcher.nameAndPostalKey('Ramirez', '97201') },
                    OrgShapeDetector.detect().personAccountRecordTypeIds
                );
            }
            Test.stopTest();

            Assert.areEqual(
                new Set<String>{ Account.BillingPostalCode.getDescribe().getLabel() },
                ImportMatcher.unreadableFields(),
                'Only the billing postal code is named: the mailing one was readable and used.'
            );
        }
    }
}
