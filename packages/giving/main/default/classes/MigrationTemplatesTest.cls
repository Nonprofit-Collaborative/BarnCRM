/**
 * The shipped migration templates (plan Section 4.9, "Templates ship for"; admin guide pages
 * "Migrating from Nonprofit Cloud" and "Migrating from NPSP"): each one is copied into the org
 * like every shipped template, and each one loads its sample file through the dry run and the
 * commit.
 *
 * The sample rows are the ones in `docs/admin-guide/samples/`, written here by the target each
 * column loads into rather than by the column's heading. The headings are the other system's
 * field paths, which this package must not spell out in Apex (scripts/ci/check-standard-objects.sh),
 * and reading them from the shipped mapping is also what proves the mapping is the one tested.
 *
 * People are stored as contacts here. That is the shape these mappings write in full; how an org
 * that stores people as accounts reads the same columns is Core's importer's business and is
 * tested there.
 */
@IsTest(testFor='ApexClass:ImportTemplateService, ApexClass:ImportRowProcessor')
private class MigrationTemplatesTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Giving_Admin');
    }

    /** The shipped migration templates: the people ones ship from Core, the gift ones from Giving. */
    private static final List<String> MIGRATION_KEYS = new List<String>{
        'npc_gift_transactions',
        'npc_undesignated_gifts',
        'npc_organization_gifts',
        'npc_person_accounts',
        'npsp_contacts',
        'npsp_payments',
        'npsp_organization_payments'
    };

    private static Import_Template__c template;
    private static Import_Batch__c batch;
    /** Who ran the import, so a test can ask what that user was allowed to write. */
    private static User importer;
    /** How the copied template stores people; a test in a person accounts org changes it. */
    private static String personMode = ImportTemplateService.PERSON_MODE_CONTACTS;

    private static User maria() {
        return TestDataFactory.createUser(
            'Maria',
            new List<String>{ 'BarnCRM_Admin', 'Giving_Admin' }
        );
    }

    private static Fund__c fund(String name, Boolean isDefault) {
        Fund__c fund = new Fund__c(Name = name, Active__c = true, Is_Default__c = isDefault);
        insert fund;
        return fund;
    }

    /** The shipped template with this key, copied into the org, storing people as personMode says. */
    private static Import_Template__c shipped(String key) {
        ImportTemplateService.materializeDefaults();
        Import_Template__c found = [
            SELECT
                Id,
                Name,
                Template_Key__c,
                Column_Mapping_JSON__c,
                Default_Values_JSON__c,
                Matching_Rule__c,
                Person_Mode__c,
                Payment_Matching__c,
                Match_Date_Window_Days__c,
                Match_Amount_Tolerance__c
            FROM Import_Template__c
            WHERE Template_Key__c = :key
        ];
        found.Person_Mode__c = personMode;
        update found;
        // Read back the way the import batch reads it, so every field the run uses is there.
        return ImportTemplateSelector.selectById(found.Id);
    }

    /**
     * Stages the sample file on a new batch: each row is written by target, and the shipped
     * mapping says which column heading carries it. A target the mapping does not load fails
     * the test, because then the sample is not the file the mapping reads.
     */
    private static void given(String key, List<Map<String, String>> rowsByTarget) {
        template = shipped(key);
        Map<String, String> sourceByTarget = new Map<String, String>();
        for (
            ImportMapping.Column column : ImportMapping.parse(template.Column_Mapping_JSON__c)
                .getColumns()
        ) {
            sourceByTarget.put(column.getTarget(), column.getSource());
        }
        List<Map<String, String>> file = new List<Map<String, String>>();
        for (Map<String, String> byTarget : rowsByTarget) {
            Map<String, String> row = new Map<String, String>();
            for (String target : byTarget.keySet()) {
                Assert.isTrue(
                    sourceByTarget.containsKey(target),
                    key + ' loads no column into ' + target
                );
                row.put(sourceByTarget.get(target), byTarget.get(target));
            }
            file.add(row);
        }
        batch = ImportTestDataFactory.batch(template);
        ImportTestDataFactory.rows(batch, file);
    }

    private static ImportRowProcessor.Outcome run(Boolean dryRun) {
        return ImportRowProcessor.process(
            batch,
            template,
            ImportMapping.parse(template.Column_Mapping_JSON__c, template.Default_Values_JSON__c),
            ImportTestDataFactory.reload(batch.Id),
            dryRun
        );
    }

    /**
     * The dry run, then the commit, as the import batch runs them: each pass clears and
     * stamps the rows it processes (R-IB13), and the processor's carried state starts empty.
     */
    private static List<Import_Row__c> dryRunThenCommit() {
        List<Import_Row__c> preview;
        importer = maria();
        System.runAs(importer) {
            Test.startTest();
            run(true);
            preview = ImportTestDataFactory.reload(batch.Id);
            ImportEntityProcessors.carriedState = null;
            run(false);
            Test.stopTest();
        }
        return preview;
    }

    /**
     * Whether the user who ran the import may edit this field. The importer skips a field its
     * user cannot write and says so in the run log; BarnCRM Admin grants the consent fields,
     * so the tests assert that Maria may write them and that their values arrive.
     */
    private static Boolean importerMayEdit(Schema.SObjectField field) {
        Boolean result;
        System.runAs(importer) {
            result = field.getDescribe().isUpdateable();
        }
        return result;
    }

    private static List<String> statuses(List<Import_Row__c> rows) {
        List<String> result = new List<String>();
        for (Import_Row__c row : rows) {
            result.add(
                row.Status__c + (row.Error_Message__c == null ? '' : ': ' + row.Error_Message__c)
            );
        }
        return result;
    }

    /**
     * A row's status and error, for an assertion message. Assert refuses a null message, and
     * a row that loaded has no error.
     */
    private static String why(Import_Row__c row) {
        return 'Row ' + row.Row_Number__c + ': ' + row.Status__c + ' ' + row.Error_Message__c;
    }

    private static Map<String, Gift__c> giftsByExternalId() {
        Map<String, Gift__c> result = new Map<String, Gift__c>();
        for (Gift__c gift : [
            SELECT
                External_Id__c,
                Amount__c,
                Gift_Date__c,
                Type__c,
                Payment_Reference__c,
                Appeal__c,
                Donor_Contact__c,
                Donor_Account__c,
                Created_By_Import_Batch__c,
                (SELECT Fund__r.Name, Amount__c FROM Gift_Allocations__r ORDER BY Fund__r.Name)
            FROM Gift__c
        ]) {
            result.put(gift.External_Id__c, gift);
        }
        return result;
    }

    // -------------------------------------------------------------------------------------
    // Copied in like every shipped template
    // -------------------------------------------------------------------------------------

    /**
     * An org that already has the generic templates (every org that has opened the Import tab)
     * gets the migration templates from the same copy, Restore defaults and the Health Check
     * fix, and its own templates are left as they are (R-IT4).
     */
    @IsTest
    static void theMigrationTemplatesAreCopiedIntoAnOrgThatHasTheGenericOnes() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            TestDataFactory.defaultSettings();
            Import_Template__c generic = ImportTestDataFactory.template(
                ImportTestDataFactory.donorMapping(),
                ImportTemplateService.RULE_EMAIL
            );
            generic.Template_Key__c = 'generic_contact_list';
            generic.Name = 'Maria renamed this';
            update generic;

            Test.startTest();
            List<String> missing = ImportTemplateService.missingDefaultNames();
            ImportTemplateService.materializeDefaults();
            Test.stopTest();

            Map<String, Import_Template_Default__mdt> shippedByKey = new Map<String, Import_Template_Default__mdt>();
            for (
                Import_Template_Default__mdt row : ImportTemplateSelector.selectShippedDefaults()
            ) {
                shippedByKey.put(row.Template_Key__c, row);
            }
            Map<String, Import_Template__c> copiedByKey = new Map<String, Import_Template__c>();
            for (Import_Template__c copied : [
                SELECT
                    Name,
                    Template_Key__c,
                    Column_Mapping_JSON__c,
                    Matching_Rule__c,
                    Is_Package_Default__c,
                    Active__c
                FROM Import_Template__c
            ]) {
                copiedByKey.put(copied.Template_Key__c, copied);
            }
            for (String key : MIGRATION_KEYS) {
                Import_Template_Default__mdt row = shippedByKey.get(key);
                Assert.isNotNull(row, 'The package ships ' + key);
                Assert.isTrue(missing.contains(row.MasterLabel), 'Health Check would name ' + key);
                Import_Template__c copied = copiedByKey.get(key);
                Assert.isNotNull(copied, 'And the copy creates it: ' + key);
                Assert.areEqual(row.MasterLabel, copied.Name, 'Named as shipped: ' + key);
                Assert.areEqual(
                    row.Column_Mapping_JSON__c,
                    copied.Column_Mapping_JSON__c,
                    'With the shipped mapping: ' + key
                );
                Assert.areEqual(
                    ImportTemplateService.RULE_EMAIL,
                    copied.Matching_Rule__c,
                    'Matching people by email: ' + key
                );
                Assert.isTrue(copied.Is_Package_Default__c, 'Marked as shipped: ' + key);
                Assert.isTrue(copied.Active__c, 'And offered in the wizard: ' + key);
                Assert.isTrue(
                    ImportMapping.parse(copied.Column_Mapping_JSON__c).identifiesSomebody(),
                    'A mapping the wizard will run: ' + key
                );
            }
            Assert.areEqual(
                'Maria renamed this',
                [SELECT Name FROM Import_Template__c WHERE Id = :generic.Id].Name,
                'The template the org already had is not touched.'
            );
        }
    }

    // -------------------------------------------------------------------------------------
    // Nonprofit Cloud
    // -------------------------------------------------------------------------------------

    private static Map<String, String> designatedGift(
        String externalId,
        String amount,
        String transactionDate,
        String method,
        String designation,
        String designationAmount
    ) {
        return new Map<String, String>{
            'Gift.External_Id__c' => externalId,
            'Gift.Amount__c' => amount,
            'Gift.Gift_Date__c' => transactionDate,
            'Gift.Type__c' => method,
            'Allocation.Fund1' => designation,
            'Allocation.Amount1' => designationAmount
        };
    }

    private static Map<String, String> fromAna(Map<String, String> row) {
        row.put('Contact1.FirstName', 'Ana');
        row.put('Contact1.LastName', 'Okafor');
        row.put('Contact1.Email', 'ana.okafor@example.org');
        row.put('Contact1.MailingPostalCode', '97201');
        return row;
    }

    /**
     * Sample file npc-gift-transactions.csv: a gift with an appeal and a processor
     * reference, a second gift from the same donor, and a gift split across two designations,
     * which comes back as two lines. The donor is already here, loaded first as the admin guide
     * says, which is also the case of a gift file loaded in the Nonprofit Cloud org itself.
     */
    @IsTest
    static void giftTransactionsLoadWithTheirDesignations() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            TestDataFactory.defaultSettings();
            Contact ana = new Contact(
                FirstName = 'Ana',
                LastName = 'Okafor',
                Email = 'ana.okafor@example.org'
            );
            insert ana;
            fund('General Fund', true);
            fund('Scholarships', false);
            Appeal__c spring = new Appeal__c(Name = 'Spring Appeal', Active__c = true);
            insert spring;
            Map<String, String> first = fromAna(
                designatedGift(
                    '6gt-1001',
                    '250.00',
                    '2025-03-15',
                    'Credit Card',
                    'Scholarships',
                    '250.00'
                )
            );
            first.put('Gift.Payment_Reference__c', 'ch_3PqR1001');
            first.put('Gift.Appeal', 'Spring Appeal');
            given(
                'npc_gift_transactions',
                new List<Map<String, String>>{
                    first,
                    fromAna(
                        designatedGift(
                            '6gt-1002',
                            '100.00',
                            '2025-04-01',
                            'Check',
                            'General Fund',
                            '100.00'
                        )
                    ),
                    fromAna(
                        designatedGift(
                            '6gt-1003',
                            '500.00',
                            '2025-05-20',
                            'Check',
                            'Scholarships',
                            '300.00'
                        )
                    ),
                    fromAna(
                        designatedGift(
                            '6gt-1003',
                            '500.00',
                            '2025-05-20',
                            'Check',
                            'General Fund',
                            '200.00'
                        )
                    )
                }
            );

            List<Import_Row__c> preview = dryRunThenCommit();

            List<Import_Row__c> committed = ImportTestDataFactory.reload(batch.Id);
            Assert.areEqual(
                statuses(preview),
                statuses(committed),
                'The commit does what the dry run said.'
            );
            Assert.areEqual(
                ImportRowProcessor.STATUS_CREATED,
                committed[0].Status__c,
                why(committed[0])
            );
            Assert.areEqual(
                ImportRowProcessor.STATUS_CREATED,
                committed[1].Status__c,
                why(committed[1])
            );
            for (Integer index = 2; index < 4; index++) {
                Assert.areEqual(
                    ImportRowProcessor.STATUS_REJECTED,
                    committed[index].Status__c,
                    'One line of a split gift is refused rather than loaded as the whole gift.'
                );
                Assert.isTrue(
                    committed[index].Error_Message__c.contains('500'),
                    'Saying the split does not add up to the gift: ' +
                    committed[index].Error_Message__c
                );
            }

            Map<String, Gift__c> gifts = giftsByExternalId();
            Assert.areEqual(
                new Set<String>{ '6gt-1001', '6gt-1002' },
                gifts.keySet(),
                'Two gifts, the split one not yet.'
            );
            Gift__c card = gifts.get('6gt-1001');
            Assert.areEqual(250, card.Amount__c, 'The original amount.');
            Assert.areEqual(
                Date.newInstance(2025, 3, 15),
                card.Gift_Date__c,
                'The transaction date.'
            );
            Assert.areEqual('Card', card.Type__c, 'Credit Card is Card.');
            Assert.areEqual('ch_3PqR1001', card.Payment_Reference__c, 'The payment identifier.');
            Assert.areEqual(spring.Id, card.Appeal__c, 'The campaign is the appeal of that name.');
            Assert.areEqual(batch.Id, card.Created_By_Import_Batch__c, 'Tagged for undo.');
            Assert.areEqual(1, card.Gift_Allocations__r.size(), 'One designation, one allocation.');
            Assert.areEqual(
                'Scholarships',
                card.Gift_Allocations__r[0].Fund__r.Name,
                'To the designated fund.'
            );
            Assert.areEqual(250, card.Gift_Allocations__r[0].Amount__c, 'For the whole gift.');
            Assert.areEqual(
                'General Fund',
                gifts.get('6gt-1002').Gift_Allocations__r[0].Fund__r.Name,
                'The second gift to its own designation.'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Contact],
                'The donor is found by email, not made again.'
            );
            Assert.areEqual(ana.Id, card.Donor_Contact__c, 'Who gave the first gift.');
            Assert.areEqual(ana.Id, gifts.get('6gt-1002').Donor_Contact__c, 'And the second.');
        }
    }

    /** Sample file npc-undesignated-gifts.csv: gifts with no designation. */
    @IsTest
    static void undesignatedGiftsGoToTheDefaultFund() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            TestDataFactory.defaultSettings();
            fund('General Fund', true);
            given(
                'npc_undesignated_gifts',
                new List<Map<String, String>>{
                    fromAna(
                        new Map<String, String>{
                            'Gift.External_Id__c' => '6gt-2001',
                            'Gift.Amount__c' => '75.00',
                            'Gift.Gift_Date__c' => '2025-06-02',
                            'Gift.Type__c' => 'Cash'
                        }
                    ),
                    new Map<String, String>{
                        'Gift.External_Id__c' => '6gt-2002',
                        'Gift.Amount__c' => '40.00',
                        'Gift.Gift_Date__c' => '2025-06-09',
                        'Gift.Type__c' => 'Credit Card',
                        'Gift.Payment_Reference__c' => 'ch_3PqR2002',
                        'Contact1.FirstName' => 'Wei',
                        'Contact1.LastName' => 'Lee',
                        'Contact1.Email' => 'wei.lee@example.org',
                        'Contact1.MailingPostalCode' => '97202'
                    }
                }
            );

            List<Import_Row__c> preview = dryRunThenCommit();

            List<Import_Row__c> committed = ImportTestDataFactory.reload(batch.Id);
            Assert.areEqual(
                new List<String>{
                    ImportRowProcessor.STATUS_CREATED,
                    ImportRowProcessor.STATUS_CREATED
                },
                statuses(committed),
                'Both gifts load.'
            );
            Assert.areEqual(statuses(preview), statuses(committed), 'As the dry run said.');
            Map<String, Gift__c> gifts = giftsByExternalId();
            Assert.areEqual(2, gifts.size(), 'Two gifts.');
            for (Gift__c gift : gifts.values()) {
                Assert.areEqual(1, gift.Gift_Allocations__r.size(), 'Each allocated once.');
                Assert.areEqual(
                    'General Fund',
                    gift.Gift_Allocations__r[0].Fund__r.Name,
                    'To the default fund.'
                );
            }
            Assert.areEqual('Cash', gifts.get('6gt-2001').Type__c, 'Payment method as exported.');
            Assert.areEqual(2, [SELECT COUNT() FROM Contact], 'One donor each.');
        }
    }

    /** Sample file npc-organization-gifts.csv: a foundation's gift, split in one line. */
    @IsTest
    static void organizationGiftsAreGivenByTheOrganization() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            TestDataFactory.defaultSettings();
            fund('General Fund', true);
            fund('Scholarships', false);
            Map<String, String> split = designatedGift(
                '6gt-3001',
                '1000.00',
                '2025-02-28',
                'Check',
                'Scholarships',
                '600.00'
            );
            split.put('Organization.Name', 'Riverside Foundation');
            split.put('Gift.Payment_Reference__c', '20417');
            // Combined by hand from two lines, as the admin guide describes.
            split.put('Allocation.Fund2', 'General Fund');
            split.put('Allocation.Amount2', '400.00');
            given('npc_organization_gifts', new List<Map<String, String>>{ split });

            dryRunThenCommit();

            Import_Row__c row = ImportTestDataFactory.reload(batch.Id)[0];
            Assert.areEqual(ImportRowProcessor.STATUS_CREATED, row.Status__c, why(row));
            Account foundation = [
                SELECT Id, RecordType.DeveloperName
                FROM Account
                WHERE Name = 'Riverside Foundation'
            ];
            Assert.areEqual(
                'Organization',
                foundation.RecordType.DeveloperName,
                'Created as an organization.'
            );
            Gift__c gift = giftsByExternalId().get('6gt-3001');
            Assert.areEqual(foundation.Id, gift.Donor_Account__c, 'Which gave the gift.');
            Assert.isNull(gift.Donor_Contact__c, 'Nobody else did.');
            Assert.areEqual(0, [SELECT COUNT() FROM Contact], 'No person was made from the file.');
            Assert.areEqual(2, gift.Gift_Allocations__r.size(), 'The split, from one line.');
            Assert.areEqual(400, gift.Gift_Allocations__r[0].Amount__c, 'General Fund part.');
            Assert.areEqual(600, gift.Gift_Allocations__r[1].Amount__c, 'Scholarships part.');
        }
    }

    /** Sample file npc-person-accounts.csv: two people, each with a household. */
    @IsTest
    static void personAccountsBecomePeopleWithTheirDetails() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            TestDataFactory.defaultSettings();
            given(
                'npc_person_accounts',
                new List<Map<String, String>>{
                    new Map<String, String>{
                        'Contact1.Salutation' => 'Ms.',
                        'Contact1.FirstName' => 'Ana',
                        'Contact1.LastName' => 'Okafor',
                        'Contact1.Email' => 'ana.okafor@example.org',
                        'Contact1.Phone' => '503-555-0101',
                        'Contact1.MobilePhone' => '503-555-0102',
                        'Contact1.HomePhone' => '503-555-0103',
                        'Contact1.Birthdate' => '1980-06-01',
                        'Contact1.MailingStreet' => '12 Alder St',
                        'Contact1.MailingCity' => 'Portland',
                        'Contact1.MailingState' => 'OR',
                        'Contact1.MailingPostalCode' => '97201',
                        'Contact1.MailingCountry' => 'United States',
                        'Contact1.HasOptedOutOfEmail' => 'true',
                        'Contact1.DoNotCall' => 'false'
                    },
                    new Map<String, String>{
                        'Contact1.FirstName' => 'Wei',
                        'Contact1.LastName' => 'Lee',
                        'Contact1.Email' => 'wei.lee@example.org',
                        'Contact1.DoNotCall' => 'true'
                    }
                }
            );

            List<Import_Row__c> preview = dryRunThenCommit();

            Assert.areEqual(0, [SELECT COUNT() FROM Gift__c], 'People only.');
            List<Import_Row__c> committed = ImportTestDataFactory.reload(batch.Id);
            Assert.areEqual(statuses(preview), statuses(committed), 'As the dry run said.');
            for (Import_Row__c row : committed) {
                Assert.areEqual(ImportRowProcessor.STATUS_CREATED, row.Status__c, why(row));
                Assert.isNotNull(row.Household__c, 'Each person has a household.');
            }
            Assert.areNotEqual(
                committed[0].Household__c,
                committed[1].Household__c,
                'Of their own.'
            );
            Contact ana = [
                SELECT
                    Salutation,
                    Email,
                    Phone,
                    MobilePhone,
                    HomePhone,
                    Birthdate,
                    MailingCity,
                    MailingPostalCode,
                    HasOptedOutOfEmail,
                    DoNotCall
                FROM Contact
                WHERE LastName = 'Okafor'
            ];
            Assert.areEqual('Ms.', ana.Salutation, 'Salutation.');
            Assert.areEqual('ana.okafor@example.org', ana.Email, 'Email.');
            Assert.areEqual('503-555-0102', ana.MobilePhone, 'Mobile.');
            Assert.areEqual('503-555-0103', ana.HomePhone, 'Home phone.');
            Assert.areEqual(Date.newInstance(1980, 6, 1), ana.Birthdate, 'Birthdate.');
            Assert.areEqual('Portland', ana.MailingCity, 'Mailing address.');
            // BarnCRM Admin grants the consent fields, so an opt-out in the file is never
            // dropped: the grant is asserted, then the value.
            Assert.isTrue(
                importerMayEdit(Contact.HasOptedOutOfEmail),
                'BarnCRM Admin may write the email opt-out.'
            );
            Assert.isTrue(ana.HasOptedOutOfEmail, 'Her email opt-out comes with her.');
            Assert.isFalse(ana.DoNotCall, 'And her phone preference.');
            Assert.isTrue(
                importerMayEdit(Contact.DoNotCall),
                'BarnCRM Admin may write do not call.'
            );
            Assert.isTrue(
                [SELECT DoNotCall FROM Contact WHERE LastName = 'Lee'].DoNotCall,
                'His do not call comes with him.'
            );
        }
    }

    /**
     * Gifts loaded into the Nonprofit Cloud org itself, where the donors are already there as
     * person accounts: the gift file finds the donor by email and the gift is given by that
     * person account.
     *
     * ONLY IN A PERSON ACCOUNTS ORG (oi-pa). In an org without person accounts this test
     * returns at once and asserts nothing, on purpose: a Platform only org has no person
     * account to make (ADR-0013), and the contact shape is covered by the tests above.
     */
    @IsTest
    static void giftTransactionsFindDonorsAlreadyHeldAsPersonAccounts() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Id personType = OrgShapeDetector.creatablePersonRecordTypeId();
            if (OrgShapeDetector.hasPersonAccounts() != true || personType == null) {
                // Not a person accounts org, or none of its person types is given to the
                // running user: nothing to test here (see the comment above).
                return;
            }
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            Account ana = new Account();
            ana.put('RecordTypeId', personType);
            ana.put('FirstName', 'Ana');
            ana.put('LastName', 'Okafor');
            ana.put('PersonEmail', 'ana.okafor@example.org');
            insert ana;
            fund('General Fund', true);
            fund('Scholarships', false);
            personMode = ImportTemplateService.PERSON_MODE_PERSON_ACCOUNTS;
            given(
                'npc_gift_transactions',
                new List<Map<String, String>>{
                    fromAna(
                        designatedGift(
                            '6gt-1001',
                            '250.00',
                            '2025-03-15',
                            'Credit Card',
                            'Scholarships',
                            '250.00'
                        )
                    )
                }
            );
            Integer accountsBefore = [SELECT COUNT() FROM Account];

            List<Import_Row__c> preview = dryRunThenCommit();

            List<Import_Row__c> committed = ImportTestDataFactory.reload(batch.Id);
            Assert.areEqual(statuses(preview), statuses(committed), 'As the dry run said.');
            Assert.areEqual(
                ImportRowProcessor.STATUS_CREATED,
                committed[0].Status__c,
                why(committed[0])
            );
            Gift__c gift = giftsByExternalId().get('6gt-1001');
            Assert.areEqual(ana.Id, gift.Donor_Account__c, 'Given by the person account found.');
            Assert.areEqual(
                accountsBefore,
                [SELECT COUNT() FROM Account],
                'Nobody was created: the donor was found by email.'
            );
            Assert.areEqual(
                'Scholarships',
                gift.Gift_Allocations__r[0].Fund__r.Name,
                'To the designated fund.'
            );
        }
    }

    // -------------------------------------------------------------------------------------
    // NPSP
    // -------------------------------------------------------------------------------------

    /** Sample file npsp-contacts.csv: the email addresses, the preferred one, and deceased. */
    @IsTest
    static void npspContactsBecomePeopleWithTheirEmailAddresses() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            TestDataFactory.defaultSettings();
            given(
                'npsp_contacts',
                new List<Map<String, String>>{
                    new Map<String, String>{
                        'Contact1.Salutation' => 'Ms.',
                        'Contact1.FirstName' => 'Ana',
                        'Contact1.LastName' => 'Okafor',
                        'Contact1.Title' => 'Engineer',
                        'Contact1.Birthdate' => '1980-06-01',
                        'Contact1.Email' => 'ana.okafor@example.org',
                        'Contact1.Personal_Email__c' => 'ana.okafor@example.org',
                        'Contact1.Work_Email__c' => 'aokafor@example.com',
                        'Contact1.Preferred_Email__c' => 'Personal',
                        'Contact1.MailingCity' => 'Portland',
                        'Contact1.MailingPostalCode' => '97201',
                        'Contact1.Deceased__c' => 'false',
                        'Contact1.HasOptedOutOfEmail' => 'false'
                    },
                    new Map<String, String>{
                        'Contact1.FirstName' => 'Robert',
                        'Contact1.LastName' => 'Hale',
                        'Contact1.Deceased__c' => 'true',
                        'Contact1.DoNotCall' => 'true'
                    }
                }
            );

            List<Import_Row__c> preview = dryRunThenCommit();

            List<Import_Row__c> committed = ImportTestDataFactory.reload(batch.Id);
            Assert.areEqual(statuses(preview), statuses(committed), 'As the dry run said.');
            for (Import_Row__c row : committed) {
                Assert.areEqual(ImportRowProcessor.STATUS_CREATED, row.Status__c, why(row));
                Assert.isNotNull(row.Household__c, 'Each person has a household.');
            }
            Contact ana = [
                SELECT Title, Birthdate, Email, Personal_Email__c, Work_Email__c, Preferred_Email__c
                FROM Contact
                WHERE LastName = 'Okafor'
            ];
            Assert.areEqual('Engineer', ana.Title, 'Title.');
            Assert.areEqual(Date.newInstance(1980, 6, 1), ana.Birthdate, 'Birthdate.');
            Assert.areEqual(
                'ana.okafor@example.org',
                ana.Personal_Email__c,
                'Home email is personal.'
            );
            Assert.areEqual('aokafor@example.com', ana.Work_Email__c, 'Work email.');
            Assert.areEqual(
                'Personal',
                ana.Preferred_Email__c,
                'The preferred one, by the same name.'
            );
            Assert.areEqual('ana.okafor@example.org', ana.Email, 'And the email to use.');
            Contact robert = [SELECT Deceased__c, DoNotCall FROM Contact WHERE LastName = 'Hale'];
            Assert.isTrue(robert.Deceased__c, 'Deceased comes across.');
            Assert.isTrue(
                importerMayEdit(Contact.DoNotCall),
                'BarnCRM Admin may write do not call.'
            );
            Assert.isTrue(robert.DoNotCall, 'So does do not call.');
        }
    }

    private static Map<String, String> payment(
        String externalId,
        String amount,
        String paymentDate,
        String method
    ) {
        return new Map<String, String>{
            'Gift.External_Id__c' => externalId,
            'Gift.Amount__c' => amount,
            'Gift.Gift_Date__c' => paymentDate,
            'Gift.Type__c' => method
        };
    }

    /**
     * Sample file npsp-payments.csv: paid payments from a donor already loaded, one with the
     * opportunity's campaign, one with a tribute, and one whose tribute type is still NPSP's own
     * word, which the dry run refuses naming the words BarnCRM uses.
     */
    @IsTest
    static void npspPaymentsBecomeGiftsWithTheirTributes() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            TestDataFactory.defaultSettings();
            insert new Contact(
                FirstName = 'Ana',
                LastName = 'Okafor',
                Email = 'ana.okafor@example.org'
            );
            fund('General Fund', true);
            Appeal__c yearEnd = new Appeal__c(Name = 'Year End 2024', Active__c = true);
            insert yearEnd;
            Map<String, String> first = fromAna(
                payment('a0B-0001', '150.00', '2024-12-10', 'Credit Card')
            );
            first.put('Gift.Appeal', 'Year End 2024');
            Map<String, String> memorial = fromAna(
                payment('a0B-0002', '50.00', '2025-01-15', 'Check')
            );
            memorial.put('Gift.Payment_Reference__c', '3312');
            memorial.put('Tribute.Type__c', 'In memory of');
            memorial.put('Tribute.Honoree_Name__c', 'Grace Okafor');
            memorial.put('Tribute.Notification_Recipient_Name__c', 'Ben Okafor');
            memorial.put('Tribute.Message__c', 'With love from Ana');
            Map<String, String> unconverted = fromAna(
                payment('a0B-0003', '25.00', '2025-02-01', 'Cash')
            );
            unconverted.put('Tribute.Type__c', 'Honor');
            unconverted.put('Tribute.Honoree_Name__c', 'Grace Okafor');
            given('npsp_payments', new List<Map<String, String>>{ first, memorial, unconverted });

            List<Import_Row__c> preview = dryRunThenCommit();

            List<Import_Row__c> committed = ImportTestDataFactory.reload(batch.Id);
            Assert.areEqual(statuses(preview), statuses(committed), 'As the dry run said.');
            Assert.areEqual(
                ImportRowProcessor.STATUS_CREATED,
                committed[0].Status__c,
                why(committed[0])
            );
            Assert.areEqual(
                ImportRowProcessor.STATUS_CREATED,
                committed[1].Status__c,
                why(committed[1])
            );
            Assert.areEqual(
                ImportRowProcessor.STATUS_REJECTED,
                committed[2].Status__c,
                'Honor is not a tribute type here.'
            );
            Assert.isTrue(
                committed[2].Error_Message__c.contains('Honor') &&
                committed[2].Error_Message__c.contains('In honor of'),
                'The message names the word to use instead: ' + committed[2].Error_Message__c
            );

            Map<String, Gift__c> gifts = giftsByExternalId();
            Assert.areEqual(
                new Set<String>{ 'a0B-0001', 'a0B-0002' },
                gifts.keySet(),
                'A gift per paid payment.'
            );
            Gift__c card = gifts.get('a0B-0001');
            Assert.areEqual(150, card.Amount__c, 'The payment amount.');
            Assert.areEqual(Date.newInstance(2024, 12, 10), card.Gift_Date__c, 'The payment date.');
            Assert.areEqual('Card', card.Type__c, 'Credit Card is Card.');
            Assert.areEqual(yearEnd.Id, card.Appeal__c, 'The campaign is the appeal of that name.');
            Assert.areEqual(
                'General Fund',
                card.Gift_Allocations__r[0].Fund__r.Name,
                'Default fund.'
            );
            Tribute__c tribute = [
                SELECT Type__c, Honoree_Name__c, Notification_Recipient_Name__c, Message__c
                FROM Tribute__c
                WHERE Gift__r.External_Id__c = 'a0B-0002'
            ];
            Assert.areEqual('In memory of', tribute.Type__c, 'Tribute type.');
            Assert.areEqual('Grace Okafor', tribute.Honoree_Name__c, 'Honoree.');
            Assert.areEqual('Ben Okafor', tribute.Notification_Recipient_Name__c, 'Who to tell.');
            Assert.areEqual('With love from Ana', tribute.Message__c, 'And what to say.');
            Assert.areEqual(
                '3312',
                gifts.get('a0B-0002').Payment_Reference__c,
                'The check number.'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Contact],
                'The donor was found, not made again.'
            );
        }
    }

    /** Sample file npsp-organization-payments.csv: a club's payment. */
    @IsTest
    static void npspOrganizationPaymentsAreGivenByTheOrganization() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            TestDataFactory.defaultSettings();
            fund('General Fund', true);
            Map<String, String> club = payment('a0B-0101', '500.00', '2025-03-03', 'Check');
            club.put('Organization.Name', 'Hillside Rotary Club');
            club.put('Gift.Payment_Reference__c', '8841');
            given('npsp_organization_payments', new List<Map<String, String>>{ club });

            dryRunThenCommit();

            Import_Row__c row = ImportTestDataFactory.reload(batch.Id)[0];
            Assert.areEqual(ImportRowProcessor.STATUS_CREATED, row.Status__c, why(row));
            Account organization = [
                SELECT Id, RecordType.DeveloperName
                FROM Account
                WHERE Name = 'Hillside Rotary Club'
            ];
            Assert.areEqual(
                'Organization',
                organization.RecordType.DeveloperName,
                'An organization.'
            );
            Gift__c gift = giftsByExternalId().get('a0B-0101');
            Assert.areEqual(organization.Id, gift.Donor_Account__c, 'Which gave the gift.');
            Assert.isNull(gift.Donor_Contact__c, 'Nobody else did.');
            Assert.areEqual(500, gift.Amount__c, 'The payment amount.');
        }
    }
}
