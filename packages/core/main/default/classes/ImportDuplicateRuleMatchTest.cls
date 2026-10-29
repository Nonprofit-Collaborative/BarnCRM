/**
 * Matching through the org's own duplicate rules (canonical model R-IT16): asked only about
 * whom the template's rule found nobody for, a match is loaded into and ticked, several follow
 * Several Matches, only records of the entity's kind are taken, and with no rule to ask the
 * rule alone decides and the run log says so. Which records an org's rules call duplicates is
 * the org's business, so the answer is stubbed; one test asks the platform itself. The 200-row
 * case runs as a minimal-profile user holding only BarnCRM Admin.
 */
@IsTest(testFor='ApexClass:ImportDuplicateRuleMatcher')
private class ImportDuplicateRuleMatchTest {
    private static final Integer MANY = 200;

    private static Import_Template__c template;
    private static Import_Batch__c batch;

    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
            AccountKindsTestData.useRecordTypeTheUserCanUse();
        }
    }

    private static User admin() {
        return TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
    }

    private static Id organizationType() {
        return AccountKindsTestData.organizationRecordTypeId();
    }

    /** A people template asking the duplicate rules, and a batch of these rows. */
    private static void given(List<Map<String, String>> values, Boolean useRules) {
        ImportMapping mapping = new ImportMapping();
        mapping.columns.add(new ImportMapping.Column('Last', 'Contact1.LastName'));
        mapping.columns.add(new ImportMapping.Column('Email', 'Contact1.Email'));
        mapping.columns.add(new ImportMapping.Column('Partner', 'Contact2.LastName'));
        mapping.columns.add(new ImportMapping.Column('Organization', 'Organization.Name'));
        template = ImportTestDataFactory.template(
            mapping.serialize(),
            ImportTemplateService.RULE_EMAIL
        );
        template.Use_Duplicate_Rules__c = useRules;
        update template;
        template = ImportTemplateSelector.selectById(template.Id);
        batch = ImportTestDataFactory.batch(template);
        ImportTestDataFactory.rows(batch, values);
    }

    private static ImportRowProcessor.Outcome run(Boolean dryRun) {
        ImportBatchService.beginPass(batch.Id);
        return ImportRowProcessor.process(
            ImportBatchSelector.selectById(batch.Id),
            template,
            ImportMapping.parse(template.Column_Mapping_JSON__c, template.Default_Values_JSON__c),
            ImportTestDataFactory.reload(batch.Id),
            dryRun
        );
    }

    private static List<Import_Row__c> rows() {
        return [
            SELECT
                Status__c,
                Error_Message__c,
                Contact_1__c,
                Organization__c,
                Several_Matches__c,
                Duplicate_Rule_Match__c
            FROM Import_Row__c
            WHERE Import_Batch__c = :batch.Id
            WITH SYSTEM_MODE
            ORDER BY Row_Number__c
        ];
    }

    private static Map<String, String> row(String last, String email) {
        return new Map<String, String>{ 'Last' => last, 'Email' => email };
    }

    @IsTest
    static void twoHundredPeopleTheRuleMissedAreMatchedByTheDuplicateRules() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                List<Contact> existing = new List<Contact>();
                for (Integer i = 0; i < MANY; i++) {
                    existing.add(
                        new Contact(LastName = 'Dup' + i, Email = 'old' + i + '@example.org')
                    );
                }
                insert existing;
                ImportDuplicateRuleMatcher.stubMatches = new Map<String, List<Id>>();
                List<Map<String, String>> values = new List<Map<String, String>>();
                for (Integer i = 0; i < MANY; i++) {
                    ImportDuplicateRuleMatcher.stubMatches.put(
                        'dup' + i,
                        new List<Id>{ existing[i].Id }
                    );
                    values.add(row('Dup' + i, 'new' + i + '@example.org'));
                }
                given(values, true);

                Test.startTest();
                ImportRowProcessor.Outcome preview = run(true);
                ImportRowProcessor.Outcome committed = run(false);
                Test.stopTest();

                Assert.areEqual(0, preview.created, 'Nobody would be created.');
                Assert.areEqual(0, committed.created, 'Nobody was: ' + committed.notes);
                Assert.areEqual(MANY, [SELECT COUNT() FROM Contact], 'Still two hundred people.');
                Assert.isTrue(committed.notes.contains(Label.Core_Import_LogDuplicateRuleMatches));
                List<Import_Row__c> loaded = rows();
                Assert.areEqual(existing[0].Id, loaded[0].Contact_1__c, 'Loaded into the match.');
                for (Import_Row__c each : loaded) {
                    Assert.isTrue(each.Duplicate_Rule_Match__c, 'Every such row is ticked.');
                }
                Assert.areEqual(
                    'new0@example.org',
                    [SELECT Email FROM Contact WHERE Id = :existing[0].Id].Email,
                    'The row was loaded into the matched person.'
                );
            }

        }
    }

    @IsTest
    static void aPersonTheRuleFindsIsNeverAskedAbout() {
        System.runAs(TestUsers.admin()) {
            Contact byEmail = new Contact(LastName = 'Exact', Email = 'exact@example.org');
            Contact other = new Contact(LastName = 'Other');
            insert new List<Contact>{ byEmail, other };
            ImportDuplicateRuleMatcher.stubMatches = new Map<String, List<Id>>{
                'exact' => new List<Id>{ other.Id }
            };
            given(new List<Map<String, String>>{ row('Exact', 'exact@example.org') }, true);

            run(false);

            Import_Row__c loaded = rows()[0];
            Assert.areEqual(byEmail.Id, loaded.Contact_1__c, 'The exact rule wins.');
            Assert.isFalse(loaded.Duplicate_Rule_Match__c);
        }
    }

    @IsTest
    static void severalMatchesAreRejectedByDefault() {
        System.runAs(TestUsers.admin()) {
            Contact one = new Contact(LastName = 'Twin');
            Contact two = new Contact(LastName = 'Twin');
            insert new List<Contact>{ one, two };
            ImportDuplicateRuleMatcher.stubMatches = new Map<String, List<Id>>{
                'twin' => new List<Id>{ one.Id, two.Id }
            };
            given(new List<Map<String, String>>{ row('Twin', 'twin@example.org') }, true);

            ImportRowProcessor.Outcome preview = run(true);

            Import_Row__c rejected = rows()[0];
            Assert.areEqual(1, preview.rejected);
            Assert.areEqual(Label.Core_Import_ErrorSeveralPeopleMatch, rejected.Error_Message__c);
            Assert.isTrue(rejected.Several_Matches__c, 'Listed as a several-matches row.');
            Assert.isFalse(rejected.Duplicate_Rule_Match__c, 'Not loaded into either.');
        }
    }

    @IsTest
    static void severalMatchesCanTakeTheMostRecentlyChanged() {
        System.runAs(TestUsers.admin()) {
            Contact older = new Contact(LastName = 'Twin');
            Contact newer = new Contact(LastName = 'Twin');
            insert new List<Contact>{ older, newer };
            Test.setCreatedDate(older.Id, Datetime.now().addDays(-10));
            ImportDuplicateRuleMatcher.stubMatches = new Map<String, List<Id>>{
                'twin' => new List<Id>{ older.Id, newer.Id }
            };
            given(new List<Map<String, String>>{ row('Twin', 'twin@example.org') }, true);
            template.Several_Matches__c = ImportTemplateService.SEVERAL_MOST_RECENT;
            update template;
            template = ImportTemplateSelector.selectById(template.Id);

            run(false);

            Import_Row__c loaded = rows()[0];
            Assert.areEqual(newer.Id, loaded.Contact_1__c, 'The later of two equally changed.');
            Assert.isTrue(loaded.Several_Matches__c);
            Assert.isTrue(loaded.Duplicate_Rule_Match__c);
        }
    }

    @IsTest
    static void bothPeopleMatchedToOneRecordRejectTheRow() {
        System.runAs(TestUsers.admin()) {
            Contact shared = new Contact(LastName = 'Rivera');
            insert shared;
            ImportDuplicateRuleMatcher.stubMatches = new Map<String, List<Id>>{
                'rivera' => new List<Id>{ shared.Id }
            };
            Map<String, String> couple = row('Rivera', null);
            couple.put('Partner', 'Rivera');
            given(new List<Map<String, String>>{ couple }, true);

            run(true);

            Assert.areEqual(
                Label.Core_Import_ErrorDuplicateRuleOnePerson,
                rows()[0].Error_Message__c
            );
        }
    }

    @IsTest
    static void anOrganizationTheRulesMatchIsUsedAndAHouseholdNeverIs() {
        System.runAs(TestUsers.admin()) {
            Account church = new Account(
                Name = 'First Baptist Church',
                RecordTypeId = organizationType()
            );
            insert church;
            Contact member = new Contact(LastName = 'Okafor');
            insert member;
            Id household = [SELECT AccountId FROM Contact WHERE Id = :member.Id].AccountId;
            ImportDuplicateRuleMatcher.stubMatches = new Map<String, List<Id>>{
                'first baptist' => new List<Id>{ church.Id },
                'okafor charity' => new List<Id>{ household }
            };
            Map<String, String> first = row('Ruiz', 'ruiz@example.org');
            first.put('Organization', 'First Baptist');
            Map<String, String> second = row('Lee', 'lee@example.org');
            second.put('Organization', 'Okafor Charity');
            given(new List<Map<String, String>>{ first, second }, true);

            run(false);

            List<Import_Row__c> loaded = rows();
            Assert.areEqual(church.Id, loaded[0].Organization__c, 'Matched by the rules.');
            Assert.isTrue(loaded[0].Duplicate_Rule_Match__c);
            Assert.areNotEqual(
                household,
                loaded[1].Organization__c,
                'A household is no organization.'
            );
            Assert.isNotNull(loaded[1].Organization__c, 'The organization was created instead.');
            Assert.isFalse(loaded[1].Duplicate_Rule_Match__c);
        }
    }

    @IsTest
    static void withNoRuleToAskTheRuleAloneDecidesAndTheRunLogSaysSo() {
        System.runAs(TestUsers.admin()) {
            ImportDuplicateRuleMatcher.stubUnavailable = true;
            Map<String, String> one = row('Nobody', 'nobody@example.org');
            one.put('Organization', 'New Org');
            given(new List<Map<String, String>>{ one }, true);

            ImportRowProcessor.Outcome committed = run(false);

            Assert.areEqual(1, committed.created, 'Nothing is rejected for want of a rule.');
            Assert.isTrue(committed.notes.contains(Label.Core_Import_LogNoDuplicateRulePeople));
            Assert.isTrue(
                committed.notes.contains(Label.Core_Import_LogNoDuplicateRuleOrganizations)
            );
        }
    }

    @IsTest
    static void aTemplateNotUsingTheRulesNeverAsksThem() {
        System.runAs(TestUsers.admin()) {
            Contact other = new Contact(LastName = 'Asked');
            insert other;
            ImportDuplicateRuleMatcher.stubMatches = new Map<String, List<Id>>{
                'asked' => new List<Id>{ other.Id }
            };
            given(new List<Map<String, String>>{ row('Asked', 'asked@example.org') }, false);

            ImportRowProcessor.Outcome committed = run(false);

            Assert.areEqual(1, committed.created);
            Assert.areNotEqual(other.Id, rows()[0].Contact_1__c);
        }
    }

    @IsTest
    static void theChoiceIsSavedWithTheMatchingChoices() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                given(new List<Map<String, String>>(), false);
                ImportTemplateService.MatchingChoices choices = new ImportTemplateService.MatchingChoices();
                choices.useDuplicateRules = true;

                ImportTemplateService.saveMatching(template.Id, choices);

                Assert.isTrue(
                    ImportTemplateSelector.selectById(template.Id).Use_Duplicate_Rules__c
                );
                choices.useDuplicateRules = null;
                ImportTemplateService.saveMatching(template.Id, choices);
                Assert.isFalse(
                    ImportTemplateSelector.selectById(template.Id).Use_Duplicate_Rules__c
                );
            }

        }
    }

    private static DuplicateRule rule(String objectName, String subtype, Boolean active) {
        Map<String, Object> fields = new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'type' => 'DuplicateRule' },
            'SobjectType' => objectName,
            'IsActive' => active
        };
        if (subtype != null) {
            fields.put('SobjectSubtype', subtype);
        }
        return (DuplicateRule) JSON.deserialize(JSON.serialize(fields), DuplicateRule.class);
    }

    /**
     * A person account rule is a rule on Account with the person account subtype: it answers for
     * person accounts only, so an organization with only that rule switched on is not asked
     * about, and no error is logged for every chunk.
     */
    @IsTest
    static void aPersonAccountRuleIsNoAnswerForAnOrganization() {
        System.runAs(TestUsers.admin()) {
            DuplicateSelector.rulesOverride = new List<DuplicateRule>{
                rule('Account', DuplicateSelector.PERSON_ACCOUNT_SUBTYPE, true),
                rule('Contact', null, false)
            };
            Assert.isFalse(
                ImportDuplicateRuleMatcher.hasActiveRule(Account.SObjectType),
                'No rule for organizations and households'
            );
            Assert.isTrue(
                ImportDuplicateRuleMatcher.hasActiveRule(Account.SObjectType, true),
                'The person account rule answers for person accounts'
            );
            Assert.isFalse(
                ImportDuplicateRuleMatcher.hasActiveRule(Contact.SObjectType),
                'An inactive rule is no rule'
            );
            List<SObject> organizations = new List<SObject>();
            for (Integer index = 0; index < MANY; index++) {
                organizations.add(
                    ImportDuplicateRuleMatcher.probe(
                        Account.SObjectType,
                        new Map<String, String>{ 'Name' => 'Springfield Club ' + index },
                        organizationType()
                    )
                );
            }
            Assert.isNull(
                ImportDuplicateRuleMatcher.matchesFor(organizations, null),
                'The rule alone decides'
            );
            Assert.areEqual(0, ImportDuplicateRuleMatcher.calls, 'The matcher is not asked');
            Assert.areEqual(0, [SELECT COUNT() FROM Error_Log__c], 'Nothing is logged');

            DuplicateSelector.rulesOverride.add(rule('Account', 'None', true));
            Assert.isTrue(
                ImportDuplicateRuleMatcher.hasActiveRule(Account.SObjectType),
                'An Account rule with no subtype answers for organizations'
            );
            Assert.isFalse(
                ImportDuplicateRuleMatcher.hasActiveRule(Contact.SObjectType, true),
                'Only Account has person accounts'
            );
        }
    }

    /**
     * The scan's households pass starts only for a rule that compares organizations and
     * households; a person account rule alone gives it nothing to ask.
     */
    @IsTest
    static void aPersonAccountRuleAloneStartsNoHouseholdsPass() {
        System.runAs(TestUsers.admin()) {
            DuplicateSelector.rulesOverride = new List<DuplicateRule>{
                rule('Account', DuplicateSelector.PERSON_ACCOUNT_SUBTYPE, true),
                rule('Contact', null, true)
            };
            Set<String> both = new Set<String>{ 'Account', 'Contact' };
            Assert.areEqual(
                new Set<String>{ 'Contact' },
                DuplicateSelector.objectsWithActiveRules(both),
                'Only the people pass has a rule to run'
            );

            DuplicateSelector.rulesOverride.add(rule('Account', 'None', true));
            Assert.areEqual(
                both,
                DuplicateSelector.objectsWithActiveRules(both),
                'An Account rule with no subtype starts the households pass'
            );
        }
    }

    /**
     * In an org with person accounts a contact the rules match may be the contact half of a
     * person account, which a contact import never takes as its person. The filter is added
     * only there, for contacts only.
     */
    @IsTest
    static void aContactMatchIsNeverThePersonHalfOfAnAccount() {
        System.runAs(TestUsers.admin()) {
            String plain = ImportDuplicateRuleMatcher.visibleQuery(
                Contact.SObjectType,
                false,
                false
            );
            String withPeople = ImportDuplicateRuleMatcher.visibleQuery(
                Contact.SObjectType,
                false,
                true
            );
            Assert.isTrue(
                withPeople.startsWith(plain + ' AND '),
                'Contacts are filtered where person accounts exist: ' + withPeople
            );
            Assert.areEqual(
                ImportDuplicateRuleMatcher.visibleQuery(Account.SObjectType, true, false),
                ImportDuplicateRuleMatcher.visibleQuery(Account.SObjectType, true, true),
                'Accounts are filtered by record type, as before'
            );
        }
    }

    /**
     * Canary: the platform's own matcher finds a person already there through the standard
     * contact rule, which every new org has switched on. Skipped, and says so in the debug
     * log, where that rule is off. The debug line records what one chunk of 200 probes costs
     * (ADR-0081): matcher calls, queries and CPU time.
     */
    @IsTest
    static void theStandardContactRuleFindsThePersonAlreadyThere() {
        System.runAs(TestUsers.admin()) {
            if (
                !DuplicateSelector.activeRuleIdsByName(new Set<String>{ 'Contact' })
                    .containsKey('Standard_Contact_Duplicate_Rule')
            ) {
                System.debug(
                    LoggingLevel.WARN,
                    'Canary skipped: the standard contact rule is off.'
                );
                return;
            }
            Contact existing = new Contact(
                FirstName = 'Canary',
                LastName = 'Matchtest',
                Email = 'canary.matchtest@example.org'
            );
            insert existing;
            List<SObject> probes = new List<SObject>();
            probes.add(
                ImportDuplicateRuleMatcher.probe(
                    Contact.SObjectType,
                    new Map<String, String>{
                        'FirstName' => 'Canary',
                        'LastName' => 'Matchtest',
                        'Email' => 'canary.matchtest@example.org'
                    },
                    null
                )
            );
            for (Integer index = 1; index < MANY; index++) {
                probes.add(
                    ImportDuplicateRuleMatcher.probe(
                        Contact.SObjectType,
                        new Map<String, String>{
                            'FirstName' => 'Nobody',
                            'LastName' => 'Unmatched ' + index,
                            'Email' => 'unmatched' +
                            index +
                            '@example.org'
                        },
                        null
                    )
                );
            }

            Test.startTest();
            Integer queriesBefore = Limits.getQueries();
            Integer cpuBefore = Limits.getCpuTime();
            List<List<SObject>> found = ImportDuplicateRuleMatcher.matchesFor(probes, null);
            String cost =
                'ADR-0081 cost for ' +
                MANY +
                ' probes: matcher calls ' +
                ImportDuplicateRuleMatcher.calls +
                ', queries ' +
                (Limits.getQueries() - queriesBefore) +
                ', CPU ms ' +
                (Limits.getCpuTime() - cpuBefore);
            System.debug(LoggingLevel.WARN, cost);
            Test.stopTest();

            Assert.isNotNull(found, 'The rules were asked: ' + cost);
            Assert.areEqual(MANY, found.size(), 'One answer per probe');
            Assert.areEqual(1, found[0].size(), 'The person already there: ' + cost);
            Assert.areEqual(existing.Id, found[0][0].Id);
            Assert.isTrue(found[1].isEmpty(), 'Nobody else matched');
            Assert.areEqual(
                MANY / ImportDuplicateRuleMatcher.MAX_RECORDS_PER_CALL,
                ImportDuplicateRuleMatcher.calls,
                '50 probes a call'
            );
        }
    }

    @IsTest
    static void thePlatformIsAskedWhenNothingIsStubbed() {
        System.runAs(TestUsers.admin()) {
            Contact probe = (Contact) ImportDuplicateRuleMatcher.probe(
                Contact.SObjectType,
                new Map<String, String>{
                    'LastName' => 'Probe',
                    'Email' => 'probe@example.org',
                    'Birthdate' => '2000-01-01'
                },
                null
            );
            Assert.areEqual('Probe', probe.LastName);
            Assert.isNull(probe.Birthdate, 'Only text a rule compares is copied.');

            Test.startTest();
            List<List<SObject>> found = ImportDuplicateRuleMatcher.matchesFor(
                new List<SObject>{ probe },
                null
            );
            Test.stopTest();

            // Whether this org has an active rule for contacts is the org's business: either the
            // rules were asked and found nobody, or there was none to ask.
            Assert.isTrue(found == null || (found.size() == 1 && found[0].isEmpty()));
            Assert.isTrue(
                ImportDuplicateRuleMatcher.matchesFor(new List<SObject>(), null).isEmpty()
            );
        }
    }

    // ------------------------------------------------------------------ match sources

    /** The one source in use: addresses held on Address records, by person. */
    private static void addressSourceOnly() {
        MatchSourceSelector.sourcesOverride = new List<Match_Source__mdt>{
            (Match_Source__mdt) JSON.deserialize(
                JSON.serialize(
                    new Map<String, Object>{
                        'DeveloperName' => 'Address_Person',
                        'MasterLabel' => 'Address (person)',
                        NamespaceUtil.qualify('Object_Name__c') => 'Address__c',
                        NamespaceUtil.qualify('Value_Field__c') => 'Street__c',
                        NamespaceUtil.qualify('Postal_Code_Field__c') => 'Postal_Code__c',
                        NamespaceUtil.qualify('Parent_Field__c') => 'Contact__c',
                        NamespaceUtil.qualify('Normalization__c') => 'Address'
                    }
                ),
                Match_Source__mdt.class
            )
        };
    }

    /** A people template matching by email, its rows giving a name and an address. */
    private static void givenAddresses(List<Map<String, String>> values, Boolean useRules) {
        ImportMapping mapping = new ImportMapping();
        mapping.columns.add(new ImportMapping.Column('First', 'Contact1.FirstName'));
        mapping.columns.add(new ImportMapping.Column('Last', 'Contact1.LastName'));
        mapping.columns.add(new ImportMapping.Column('Street', 'Contact1.MailingStreet'));
        mapping.columns.add(new ImportMapping.Column('Zip', 'Contact1.MailingPostalCode'));
        template = ImportTestDataFactory.template(
            mapping.serialize(),
            ImportTemplateService.RULE_EMAIL
        );
        template.Use_Duplicate_Rules__c = useRules;
        update template;
        template = ImportTemplateSelector.selectById(template.Id);
        batch = ImportTestDataFactory.batch(template);
        ImportTestDataFactory.rows(batch, values);
    }

    /** One existing person, Okonkwo, whose address is held only on an Address record. */
    private static Contact okonkwoAtHarborRoad() {
        addressSourceOnly();
        ImportDuplicateRuleMatcher.stubMatches = new Map<String, List<Id>>();
        Contact existing = new Contact(LastName = 'Okonkwo');
        insert existing;
        insert new Address__c(
            Contact__c = existing.Id,
            Street__c = '7 Harbor Road',
            Postal_Code__c = '04101'
        );
        return existing;
    }

    @IsTest
    static void aPersonTheRulesMissIsMatchedThroughARelatedRecord() {
        System.runAs(TestUsers.admin()) {
            Contact existing = okonkwoAtHarborRoad();
            givenAddresses(
                new List<Map<String, String>>{
                    new Map<String, String>{
                        'Last' => ' OKONKWO ',
                        'Street' => '7 harbor rd.',
                        'Zip' => '04101-2200'
                    }
                },
                true
            );

            Test.startTest();
            ImportRowProcessor.Outcome committed = run(false);
            Test.stopTest();

            Import_Row__c loaded = rows()[0];
            Assert.areEqual(existing.Id, loaded.Contact_1__c, 'Loaded into the person: ' + loaded);
            Assert.isTrue(loaded.Duplicate_Rule_Match__c, 'Ticked as a looser match.');
            Assert.areEqual(0, committed.created, 'Nobody created.');
            Assert.areEqual(1, [SELECT COUNT() FROM Contact], 'Still one person.');
        }
    }

    @IsTest
    static void aRelatedRecordMatchWithAnotherLastNameIsNotUsed() {
        System.runAs(TestUsers.admin()) {
            Contact existing = okonkwoAtHarborRoad();
            givenAddresses(
                new List<Map<String, String>>{
                    new Map<String, String>{
                        'Last' => 'Okonkwo-Bell',
                        'Street' => '7 harbor rd.',
                        'Zip' => '04101-2200'
                    }
                },
                true
            );

            Test.startTest();
            ImportRowProcessor.Outcome committed = run(false);
            Test.stopTest();

            Import_Row__c loaded = rows()[0];
            Assert.areNotEqual(
                existing.Id,
                loaded.Contact_1__c,
                'Same address, another last name: not loaded into Okonkwo: ' + loaded
            );
            Assert.isFalse(loaded.Duplicate_Rule_Match__c, 'No looser match.');
            Assert.areEqual(1, committed.created, 'Handled as unmatched: a new person.');
            Assert.areEqual(2, [SELECT COUNT() FROM Contact], 'Okonkwo is untouched.');
        }
    }

    @IsTest
    static void janeSmithAtJohnSmithsAddressIsNotLoadedIntoJohn() {
        System.runAs(TestUsers.admin()) {
            addressSourceOnly();
            ImportDuplicateRuleMatcher.stubMatches = new Map<String, List<Id>>();
            Contact john = new Contact(FirstName = 'John', LastName = 'Smith');
            insert john;
            insert new Address__c(
                Contact__c = john.Id,
                Street__c = '12 Elm Street',
                Postal_Code__c = '60601'
            );
            givenAddresses(
                new List<Map<String, String>>{
                    new Map<String, String>{
                        'First' => 'Jane',
                        'Last' => 'Smith',
                        'Street' => '12 Elm St',
                        'Zip' => '60601'
                    },
                    new Map<String, String>{
                        'First' => ' john ',
                        'Last' => 'SMITH',
                        'Street' => '12 Elm St',
                        'Zip' => '60601'
                    }
                },
                true
            );

            Test.startTest();
            run(false);
            Test.stopTest();

            List<Import_Row__c> loaded = rows();
            Assert.areNotEqual(john.Id, loaded[0].Contact_1__c, 'Jane is not John: ' + loaded[0]);
            Assert.isFalse(loaded[0].Duplicate_Rule_Match__c, 'No looser match for Jane.');
            Assert.areEqual(john.Id, loaded[1].Contact_1__c, 'John still loads: ' + loaded[1]);
            Assert.isTrue(loaded[1].Duplicate_Rule_Match__c, 'Ticked as a looser match.');
        }
    }

    @IsTest
    static void janeSmithWithJohnSmithsPhoneIsNotLoadedIntoJohn() {
        System.runAs(TestUsers.admin()) {
            Schema.SObjectType individual = Schema.getGlobalDescribe().get('Individual');
            if (
                individual == null ||
                !Schema.SObjectType.Contact.fields.getMap().containsKey('individualid')
            ) {
                // Skipped: this org has no Individual for a phone source to point through.
                return;
            }
            SObject ivy = individual.newSObject();
            ivy.put('LastName', 'Smith');
            insert ivy;
            MatchSourceSelector.sourcesOverride = new List<Match_Source__mdt>{
                (Match_Source__mdt) JSON.deserialize(
                    JSON.serialize(
                        new Map<String, Object>{
                            'DeveloperName' => 'Phone_By_Individual',
                            'MasterLabel' => 'Phone',
                            NamespaceUtil.qualify('Object_Name__c') => 'Contact',
                            NamespaceUtil.qualify('Value_Field__c') => 'Phone',
                            NamespaceUtil.qualify('Parent_Field__c') => 'IndividualId',
                            NamespaceUtil.qualify('Normalization__c') => 'Phone'
                        }
                    ),
                    Match_Source__mdt.class
                )
            };
            Contact john = new Contact(
                FirstName = 'John',
                LastName = 'Smith',
                Phone = '(555) 201-3344'
            );
            john.put('IndividualId', ivy.Id);
            insert john;

            Test.startTest();
            List<List<SObject>> found = ImportDuplicateRuleMatcher.matchesBySources(
                Contact.SObjectType,
                new List<Map<String, String>>{
                    new Map<String, String>{
                        'FirstName' => 'Jane',
                        'LastName' => 'Smith',
                        'HomePhone' => '555.201.3344'
                    },
                    new Map<String, String>{ 'LastName' => 'Smith', 'Phone' => '5552013344' },
                    new Map<String, String>{
                        'FirstName' => 'John',
                        'LastName' => 'Smith',
                        'MobilePhone' => '+1 555 201 3344'
                    }
                },
                null
            );
            Test.stopTest();

            Assert.isTrue(found[0].isEmpty(), 'Jane is never John: ' + found[0]);
            Assert.isTrue(found[1].isEmpty(), 'No first name is not John: ' + found[1]);
            Assert.areEqual(1, found[2].size(), 'John is John: ' + found[2]);
            Assert.areEqual(john.Id, found[2][0].Id);
        }
    }

    @IsTest
    static void twoHundredPeopleAreMatchedThroughRelatedRecordsInOneChunk() {
        System.runAs(TestUsers.admin()) {
            addressSourceOnly();
            ImportDuplicateRuleMatcher.stubMatches = new Map<String, List<Id>>();
            Integer count = 200;
            List<Contact> existing = new List<Contact>();
            for (Integer index = 0; index < count; index++) {
                existing.add(new Contact(LastName = 'Bulkperson' + index));
            }
            insert existing;
            List<Address__c> addresses = new List<Address__c>();
            List<Map<String, String>> incoming = new List<Map<String, String>>();
            for (Integer index = 0; index < count; index++) {
                String zip = String.valueOf(10000 + index);
                addresses.add(
                    new Address__c(
                        Contact__c = existing[index].Id,
                        Street__c = (index + 1) + ' Harbor Road',
                        Postal_Code__c = zip
                    )
                );
                incoming.add(
                    new Map<String, String>{
                        'Last' => 'Bulkperson' + index,
                        'Street' => (index + 1) + ' harbor rd',
                        'Zip' => zip
                    }
                );
            }
            insert addresses;
            givenAddresses(incoming, true);

            Test.startTest();
            ImportRowProcessor.Outcome committed = run(false);
            Test.stopTest();

            List<Import_Row__c> loaded = rows();
            Assert.areEqual(count, loaded.size());
            for (Integer index = 0; index < count; index++) {
                Assert.areEqual(
                    existing[index].Id,
                    loaded[index].Contact_1__c,
                    'Row ' + index + ' loaded into its person: ' + loaded[index]
                );
            }
            Assert.areEqual(0, committed.created, 'Nobody created.');
        }
    }

    @IsTest
    static void withoutLooserMatchingTheSourcesAreNotAsked() {
        System.runAs(TestUsers.admin()) {
            addressSourceOnly();
            Contact existing = new Contact(LastName = 'Okonkwo');
            insert existing;
            insert new Address__c(
                Contact__c = existing.Id,
                Street__c = '7 Harbor Road',
                Postal_Code__c = '04101'
            );
            givenAddresses(
                new List<Map<String, String>>{
                    new Map<String, String>{
                        'Last' => 'Okonkwo-Bell',
                        'Street' => '7 Harbor Road',
                        'Zip' => '04101'
                    }
                },
                false
            );

            Test.startTest();
            run(false);
            Test.stopTest();

            Assert.areNotEqual(existing.Id, rows()[0].Contact_1__c, 'A new person, as before.');
        }
    }
}
