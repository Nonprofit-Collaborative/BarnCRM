/**
 * Match sources: which ones an org can use, and how their values are made comparable
 * (ADR-0133, `0133-related-record-matching.md`).
 */
@IsTest(testFor='ApexClass:MatchSourceService')
private class MatchSourceServiceTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static Match_Source__mdt row(
        String developerName,
        String objectName,
        String valueField,
        String postalField,
        String parentField,
        String normalization
    ) {
        // DeveloperName cannot be set on an in-memory row, so the row is read from JSON.
        Map<String, Object> fields = new Map<String, Object>{
            'DeveloperName' => developerName,
            'MasterLabel' => developerName,
            NamespaceUtil.qualify('Object_Name__c') => objectName,
            NamespaceUtil.qualify('Value_Field__c') => valueField,
            NamespaceUtil.qualify('Postal_Code_Field__c') => postalField,
            NamespaceUtil.qualify('Parent_Field__c') => parentField,
            NamespaceUtil.qualify('Normalization__c') => normalization
        };
        return (Match_Source__mdt) JSON.deserialize(
            JSON.serialize(fields),
            Match_Source__mdt.class
        );
    }

    @IsTest
    static void emailsCompareTrimmedAndInLowerCase() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual('maria@example.org', MatchSourceService.email('  Maria@Example.ORG '));
            Assert.isNull(MatchSourceService.email('not an email'), 'No @, nothing to compare');
            Assert.isNull(MatchSourceService.email(null), 'Blank');
            Assert.areEqual(
                MatchSourceService.email('maria@example.org'),
                MatchSourceService.key(MatchSourceService.EMAIL, 'MARIA@example.org', null),
                'key() applies the source normalization'
            );
        }
    }

    @IsTest
    static void phonesCompareByDigitsWithoutTheNorthAmericanOne() {
        System.runAs(TestUsers.admin()) {
            String expected = '5551234567';
            Assert.areEqual(expected, MatchSourceService.phone('(555) 123-4567'));
            Assert.areEqual(expected, MatchSourceService.phone('555.123.4567'));
            Assert.areEqual(expected, MatchSourceService.phone('+1 555 123 4567'));
            Assert.areEqual(expected, MatchSourceService.phone('1-555-123-4567'));
            Assert.areEqual(
                '442079460958',
                MatchSourceService.phone('+44 20 7946 0958'),
                'Only an 11 digit number starting 1 loses its first digit'
            );
            Assert.isNull(MatchSourceService.phone('x1234'), 'Too short to say anything');
            Assert.isNull(MatchSourceService.phone(null), 'Blank');
        }
    }

    @IsTest
    static void addressesCompareFoldedStreetAndPostalCode() {
        System.runAs(TestUsers.admin()) {
            String expected = MatchSourceService.address('12 North Main Street, Apt. 4', '02139');
            Assert.areEqual('12 n main st apt 4|02139', expected);
            Assert.areEqual(
                expected,
                MatchSourceService.address('12  n. MAIN st   apartment 4', '02139-4307'),
                'Capitals, punctuation, abbreviations and ZIP+4 do not matter'
            );
            Assert.areEqual(
                '1 high st|SW1A1AA',
                MatchSourceService.address('1 High Street', 'sw1a 1aa'),
                'A postal code loses its spaces and is upper case'
            );
            Assert.isNull(MatchSourceService.address('1 High Street', null), 'No postal code');
            Assert.isNull(MatchSourceService.address(' , ', '02139'), 'No street');
            Assert.isNull(
                MatchSourceService.key('Fax', '1', null),
                'An unknown normalization compares nothing'
            );
        }
    }

    @IsTest
    static void onlySourcesTheOrgCanUseAreUsed() {
        System.runAs(TestUsers.admin()) {
            MatchSourceSelector.sourcesOverride = new List<Match_Source__mdt>{
                row('Usable', 'Address__c', 'Street__c', 'Postal_Code__c', 'Contact__c', 'Address'),
                row('NoObject', 'No_Such_Thing__c', 'Street__c', null, 'Contact__c', 'Email'),
                row('NoField', 'Address__c', 'No_Such_Field__c', null, 'Contact__c', 'Email'),
                row('NotLookup', 'Address__c', 'Street__c', null, 'City__c', 'Email'),
                row('NoPostal', 'Address__c', 'Street__c', null, 'Contact__c', 'Address'),
                row('NoNormalization', 'Address__c', 'Street__c', null, 'Contact__c', null)
            };

            Test.startTest();
            List<MatchSourceService.Source> sources = MatchSourceService.usableSources();
            Test.stopTest();

            Assert.areEqual(1, sources.size(), 'Only the usable source: ' + sources);
            MatchSourceService.Source source = sources[0];
            Assert.areEqual('Usable', source.developerName);
            Assert.areEqual(Address__c.SObjectType, source.objectType, 'Resolved by describe');
            Assert.areEqual(
                String.valueOf(Address__c.Street__c),
                source.valueField,
                'Full field names, prefix included'
            );
            Assert.areEqual(String.valueOf(Address__c.Postal_Code__c), source.postalField);
            Assert.areEqual(String.valueOf(Address__c.Contact__c), source.parentField);
        }
    }

    @IsTest
    static void theShippedAddressSourcesAreUsableEverywhere() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            List<MatchSourceService.Source> sources = MatchSourceService.usableSources();
            Test.stopTest();

            Set<String> names = new Set<String>();
            for (MatchSourceService.Source source : sources) {
                names.add(source.developerName);
            }
            Assert.isTrue(
                names.containsAll(
                    new Set<String>{
                        'Address_Person',
                        'Address_Household',
                        'Address_Person_Account'
                    }
                ),
                'Core\'s own address object is in every org: ' + names
            );
        }
    }

    /**
     * ADR-0013: Core runs on a Platform-only org and on one without the Data Protection and
     * Privacy objects (a real org sandbox was found without the contact point address,
     * individual and consent objects).
     * The shipped contact point sources name their objects only as metadata text, resolved by
     * describe, so where those objects are missing the sources are skipped and the scan runs
     * on what remains, with no error.
     */
    @IsTest
    static void theShippedContactPointSourcesAreSkippedWhereTheirObjectsAreMissing() {
        System.runAs(TestUsers.admin()) {
            MatchSourceService.objectsAbsentOverride = new Set<String>{
                'contactpointemail',
                'contactpointphone',
                'contactpointaddress',
                'individual',
                'contactpointconsent'
            };
            List<Contact> people = (List<Contact>) insertAllowingDuplicates(
                new List<Contact>{
                    new Contact(FirstName = 'Ana', LastName = 'Ruiz'),
                    new Contact(FirstName = 'Ben', LastName = 'Okafor')
                }
            );

            Test.startTest();
            List<MatchSourceService.Source> sources = MatchSourceService.usableSources();
            List<DuplicateService.Pair> pairs = MatchSourceService.pairsFor(
                new List<Id>{ people[0].Id, people[1].Id }
            );
            Test.stopTest();

            Set<String> names = new Set<String>();
            for (MatchSourceService.Source source : sources) {
                names.add(source.developerName);
            }
            for (
                String contactPoint : new List<String>{
                    'Contact_Point_Email',
                    'Contact_Point_Phone',
                    'Contact_Point_Address'
                }
            ) {
                Assert.isFalse(names.contains(contactPoint), contactPoint + ' is skipped');
            }
            Assert.isTrue(names.contains('Address_Person'), 'Core\'s own sources still run');
            Assert.isTrue(pairs.isEmpty(), 'The scan runs on what remains: ' + pairs);
        }
    }

    // ------------------------------------------------------------------ matching

    private static Set<String> keysOf(List<DuplicateService.Pair> pairs) {
        Set<String> keys = new Set<String>();
        for (DuplicateService.Pair pair : pairs) {
            keys.add(pair.key);
        }
        return keys;
    }

    private static List<SObject> insertAllowingDuplicates(List<SObject> records) {
        Database.DMLOptions options = new Database.DMLOptions();
        options.DuplicateRuleHeader.allowSave = true;
        // System mode: households are among these, and no user has their record type (ADR-0141).
        Database.insert(records, options, AccessLevel.SYSTEM_MODE);
        return records;
    }

    @IsTest
    static void peopleSharingAnAddressHeldOnlyOnAddressRecordsArePaired() {
        System.runAs(TestUsers.admin()) {
            MatchSourceSelector.sourcesOverride = new List<Match_Source__mdt>{
                row(
                    'Address_Person',
                    'Address__c',
                    'Street__c',
                    'Postal_Code__c',
                    'Contact__c',
                    'Address'
                )
            };
            List<Contact> people = (List<Contact>) insertAllowingDuplicates(
                new List<Contact>{
                    new Contact(FirstName = 'Ana', LastName = 'Ruiz'),
                    new Contact(FirstName = 'Anna', LastName = 'Ruiz-Lopez'),
                    new Contact(FirstName = 'Ben', LastName = 'Okafor')
                }
            );
            insert new List<Address__c>{
                new Address__c(
                    Contact__c = people[0].Id,
                    Street__c = '12 North Main Street',
                    Postal_Code__c = '02139'
                ),
                new Address__c(
                    Contact__c = people[1].Id,
                    Street__c = '12 n. MAIN st',
                    Postal_Code__c = '02139-4307'
                ),
                new Address__c(
                    Contact__c = people[2].Id,
                    Street__c = '99 Elm Road',
                    Postal_Code__c = '02139'
                )
            };

            Test.startTest();
            List<DuplicateService.Pair> pairs = MatchSourceService.pairsFor(
                new List<Id>{ people[0].Id, people[1].Id, people[2].Id }
            );
            Test.stopTest();

            Assert.areEqual(
                new Set<String>{ DuplicateService.pairKey(people[0].Id, people[1].Id) },
                keysOf(pairs),
                'Only the two people at the same address, written two ways'
            );
            Assert.areEqual('Same address on Address_Person', pairs[0].reason, 'Names the source');
            Assert.isNull(pairs[0].ruleName, 'No rule found it');
        }
    }

    @IsTest
    static void householdsWhosePeopleShareAPhoneArePairedWhateverItsFormat() {
        System.runAs(TestUsers.admin()) {
            MatchSourceSelector.sourcesOverride = new List<Match_Source__mdt>{
                row('Member_Phone', 'Contact', 'Phone', null, 'AccountId', 'Phone')
            };
            List<Account> homes = new List<Account>{
                AddressTestDataFactory.newHousehold('Lee Household'),
                AddressTestDataFactory.newHousehold('Li Household'),
                AddressTestDataFactory.newHousehold('Park Household')
            };
            insertAllowingDuplicates(homes);
            List<String> phones = new List<String>{
                '(555) 123-4567',
                '+1 555.123.4567',
                '555 999 0000'
            };
            List<Contact> people = new List<Contact>();
            for (Integer index = 0; index < homes.size(); index++) {
                Contact person = AddressTestDataFactory.newContact(
                    'Sam',
                    'Member' + index,
                    homes[index].Id
                );
                person.Phone = phones[index];
                people.add(person);
            }
            insertAllowingDuplicates(people);

            Test.startTest();
            List<DuplicateService.Pair> pairs = MatchSourceService.pairsFor(
                new List<Id>{ homes[0].Id, homes[1].Id, homes[2].Id }
            );
            Test.stopTest();

            Assert.areEqual(
                new Set<String>{ DuplicateService.pairKey(homes[0].Id, homes[1].Id) },
                keysOf(pairs),
                'The two households with the same number, however it is written'
            );
            Assert.areEqual('Same phone on Member_Phone', pairs[0].reason, 'Names the source');
        }
    }

    @IsTest
    static void aValueHeldByMoreThanTenIsNotUsed() {
        System.runAs(TestUsers.admin()) {
            MatchSourceSelector.sourcesOverride = new List<Match_Source__mdt>{
                row('Member_Email', 'Contact', 'Email', null, 'AccountId', 'Email')
            };
            List<Account> homes = new List<Account>();
            for (Integer index = 0; index <= MatchSourceService.MAX_OWNERS_PER_VALUE; index++) {
                homes.add(AddressTestDataFactory.newHousehold('Office ' + index));
            }
            insertAllowingDuplicates(homes);
            List<Contact> people = new List<Contact>();
            for (Account home : homes) {
                Contact person = AddressTestDataFactory.newContact('Front', 'Desk', home.Id);
                person.Email = 'info@shared-office.example.org';
                people.add(person);
            }
            insertAllowingDuplicates(people);

            Test.startTest();
            List<DuplicateService.Pair> pairs = MatchSourceService.pairsFor(
                new List<Id>{ homes[0].Id, homes[1].Id }
            );
            Test.stopTest();

            Assert.isTrue(pairs.isEmpty(), 'A shared mailbox pairs nobody: ' + pairs.size());
        }
    }

    @IsTest
    static void aSourceThatCannotPointAtTheRecordsIsNotAsked() {
        System.runAs(TestUsers.admin()) {
            MatchSourceSelector.sourcesOverride = new List<Match_Source__mdt>{
                row(
                    'Address_Household',
                    'Address__c',
                    'Street__c',
                    'Postal_Code__c',
                    'Account__c',
                    'Address'
                )
            };
            Contact person = new Contact(FirstName = 'Ida', LastName = 'Nobody');
            insert person;

            Test.startTest();
            List<DuplicateService.Pair> pairs = MatchSourceService.pairsFor(
                new List<Id>{ person.Id }
            );
            Integer queries = Limits.getQueries();
            Test.stopTest();

            Assert.isTrue(pairs.isEmpty(), 'A household source finds no people');
            Assert.isTrue(queries <= 2, 'Only the sources are read, never the rows: ' + queries);
        }
    }

    // ------------------------------------------------------------------ Individuals

    /** Individuals with these last names, or null in an org without them. */
    private static List<SObject> individuals(Integer count) {
        Schema.SObjectType type = Schema.getGlobalDescribe().get('Individual');
        if (
            type == null ||
            !type.getDescribe().isCreateable() ||
            MatchSourceService.individualFieldOf(Contact.SObjectType) == null
        ) {
            return null;
        }
        List<SObject> result = new List<SObject>();
        for (Integer index = 0; index < count; index++) {
            SObject individual = type.newSObject();
            individual.put('LastName', 'Ivy' + index);
            result.add(individual);
        }
        insert result;
        return result;
    }

    /** A source on Contact's own email, linked by the Individual the contact carries. */
    private static Match_Source__mdt emailByIndividual() {
        return row('Email_By_Individual', 'Contact', 'Email', null, 'IndividualId', 'Email');
    }

    @IsTest
    static void anIndividualStandsForTheContactsThatCarryIt() {
        System.runAs(TestUsers.admin()) {
            List<SObject> ivys = individuals(3);
            if (ivys == null) {
                // Skipped: this org has no Individual, so no source can resolve one.
                Assert.isNull(MatchSourceService.individualFieldOf(Contact.SObjectType));
                return;
            }
            MatchSourceSelector.sourcesOverride = new List<Match_Source__mdt>{
                emailByIndividual()
            };
            List<Contact> people = new List<Contact>{
                new Contact(LastName = 'Ivy', Email = 'ivy@example.org'),
                new Contact(LastName = 'Ivy-Lane', Email = 'IVY@example.org'),
                new Contact(LastName = 'Other', Email = 'other@example.org')
            };
            for (Integer index = 0; index < people.size(); index++) {
                people[index].put('IndividualId', ivys[index].Id);
            }
            insertAllowingDuplicates(people);

            Test.startTest();
            List<DuplicateService.Pair> pairs = MatchSourceService.pairsFor(
                new List<Id>{ people[0].Id, people[1].Id, people[2].Id }
            );
            Test.stopTest();

            Assert.areEqual(
                new Set<String>{ DuplicateService.pairKey(people[0].Id, people[1].Id) },
                keysOf(pairs),
                'Rows on two Individuals pair the contacts carrying them'
            );
        }
    }

    @IsTest
    static void anIndividualStandsForThePersonAccountsThatCarryIt() {
        System.runAs(TestUsers.admin()) {
            if (
                PersonAccountTestShape.skipReason() != null ||
                MatchSourceService.individualFieldOf(Account.SObjectType) == null
            ) {
                // Skipped: no person accounts here, or none carry an Individual.
                return;
            }
            List<SObject> ivys = individuals(2);
            if (ivys == null) {
                return;
            }
            MatchSourceSelector.sourcesOverride = new List<Match_Source__mdt>{
                emailByIndividual()
            };
            List<Account> people = new List<Account>();
            for (Integer index = 0; index < 2; index++) {
                Account person = new Account(
                    RecordTypeId = OrgShapeDetector.creatablePersonRecordTypeId()
                );
                person.put('LastName', 'Ivy' + index);
                person.put('PersonEmail', 'ivy.person@example.org');
                person.put('PersonIndividualId', ivys[index].Id);
                people.add(person);
            }
            insertAllowingDuplicates(people);

            Test.startTest();
            List<DuplicateService.Pair> pairs = MatchSourceService.pairsFor(
                new List<Id>{ people[0].Id, people[1].Id }
            );
            Test.stopTest();

            Assert.areEqual(
                new Set<String>{ DuplicateService.pairKey(people[0].Id, people[1].Id) },
                keysOf(pairs),
                'Rows on two Individuals pair the person accounts carrying them'
            );
        }
    }

    // ------------------------------------------------------------------ bounded lookups

    @IsTest
    static void anAddressIsLookedUpByPostalCodeAndAWordOfItsStreet() {
        // runs-as: deploying user (pure string building, no data or permission read)
        MatchSourceService.Source source = new MatchSourceService.Source();
        source.normalization = MatchSourceService.ADDRESS;
        source.valueField = 'Street__c';
        source.postalField = 'Postal_Code__c';

        Map<String, String> numbered = MatchSourceService.likeClause(
            source,
            MatchSourceService.address('12 North Main Street', '02139-4307')
        );
        Map<String, String> unnumbered = MatchSourceService.likeClause(
            source,
            MatchSourceService.address('North Main St.', '02139')
        );

        Assert.areEqual('0%2%1%3%9%', numbered.get('Postal_Code__c'), 'By postal code');
        Assert.areEqual('%12%', numbered.get('Street__c'), 'And the house number');
        Assert.areEqual(
            '%main%',
            unnumbered.get('Street__c'),
            'A word normalization shortened (n, st) is never used'
        );
    }

    @IsTest
    static void manyPhonesAreReadAHundredPatternsAtATime() {
        System.runAs(TestUsers.admin()) {
            MatchSourceSelector.sourcesOverride = new List<Match_Source__mdt>{
                row('Member_Phone', 'Contact', 'Phone', null, 'AccountId', 'Phone')
            };
            Account home = AddressTestDataFactory.newHousehold('Caller Household');
            insertAllowingDuplicates(new List<Account>{ home });
            Contact caller = AddressTestDataFactory.newContact('Cal', 'Caller', home.Id);
            caller.Phone = '(555) 010-0149';
            insertAllowingDuplicates(new List<Contact>{ caller });
            Set<String> keys = new Set<String>();
            for (Integer index = 0; index < 150; index++) {
                keys.add('55501' + String.valueOf(index).leftPad(5, '0'));
            }
            MatchSourceService.Source source = MatchSourceService.usableSources()[0];

            Test.startTest();
            Integer before = Limits.getQueries();
            Map<String, Set<Id>> found = MatchSourceService.ownersOf(
                source,
                Account.SObjectType,
                keys
            );
            Integer queries = Limits.getQueries() - before;
            Test.stopTest();

            Assert.areEqual(2, queries, '150 patterns in two queries of at most 100');
            Assert.areEqual(
                new Set<Id>{ home.Id },
                found.get('5550100149'),
                'The holder is found whichever query read it'
            );
        }
    }

    @IsTest
    static void aLookupThatReachesItsCapIsCountedAndLoggedOnce() {
        System.runAs(TestUsers.admin()) {
            MatchSourceSelector.sourcesOverride = new List<Match_Source__mdt>{
                row(
                    'Address_Person',
                    'Address__c',
                    'Street__c',
                    'Postal_Code__c',
                    'Contact__c',
                    'Address'
                )
            };
            List<Contact> people = (List<Contact>) insertAllowingDuplicates(
                new List<Contact>{
                    new Contact(LastName = 'Capped'),
                    new Contact(LastName = 'Capped-Too')
                }
            );
            insert new List<Address__c>{
                new Address__c(
                    Contact__c = people[0].Id,
                    Street__c = '3 Oak Lane',
                    Postal_Code__c = '30301'
                ),
                new Address__c(
                    Contact__c = people[1].Id,
                    Street__c = '3 Oak Ln',
                    Postal_Code__c = '30301'
                )
            };
            MatchSourceSelector.maxRows = 1;

            Test.startTest();
            MatchSourceService.pairsFor(new List<Id>{ people[0].Id, people[1].Id });
            Test.stopTest();
            Test.getEventBus().deliver();

            Assert.isTrue(
                MatchSourceSelector.cappedLookups >= 2,
                'Each capped lookup is counted: ' + MatchSourceSelector.cappedLookups
            );
            List<Error_Log__c> logged = [
                SELECT Severity__c, Message__c
                FROM Error_Log__c
                WHERE Context__c = 'Match sources'
            ];
            Assert.areEqual(1, logged.size(), 'One warning for the source: ' + logged);
            Assert.areEqual(ErrorLogger.SEVERITY_WARNING, logged[0].Severity__c);
            Assert.isTrue(logged[0].Message__c.contains('Address_Person'), 'Names the source');
        }
    }

    /** Households 0 to `count - 1`, each with one person holding this email. */
    private static List<Account> householdsSharing(String email, Integer count) {
        List<Account> homes = new List<Account>();
        for (Integer index = 0; index < count; index++) {
            homes.add(AddressTestDataFactory.newHousehold('Shared ' + index));
        }
        insertAllowingDuplicates(homes);
        List<Contact> people = new List<Contact>();
        for (Account home : homes) {
            Contact person = AddressTestDataFactory.newContact('Front', 'Desk', home.Id);
            person.Email = email;
            people.add(person);
        }
        insertAllowingDuplicates(people);
        return homes;
    }

    @IsTest
    static void aValueFromACutLookupCountsAsSharedByMoreThanTen() {
        System.runAs(TestUsers.admin()) {
            MatchSourceSelector.sourcesOverride = new List<Match_Source__mdt>{
                row('Member_Email', 'Contact', 'Email', null, 'AccountId', 'Email')
            };
            List<Account> homes = householdsSharing(
                'desk@shared-office.example.org',
                MatchSourceService.MAX_OWNERS_PER_VALUE + 1
            );
            // The lookup reads five of the eleven holders: few enough to look usable.
            MatchSourceSelector.maxRows = 5;

            Test.startTest();
            List<DuplicateService.Pair> pairs = MatchSourceService.pairsFor(
                new List<Id>{ homes[0].Id, homes[1].Id }
            );
            Test.stopTest();

            Assert.isTrue(pairs.isEmpty(), 'A cut lookup pairs nobody: ' + pairs.size());
        }
    }

    @IsTest
    static void aLookupReadsOnlyWhatTheTransactionHasLeft() {
        System.runAs(TestUsers.admin()) {
            MatchSourceSelector.sourcesOverride = new List<Match_Source__mdt>{
                row('Member_Email', 'Contact', 'Email', null, 'AccountId', 'Email')
            };
            List<Account> homes = householdsSharing('pair@example.org', 2);

            Test.startTest();
            // One row left above the reserve: the lookup is shrunk to it and so cut.
            MatchSourceSelector.rowReserve = Limits.getLimitQueryRows() - Limits.getQueryRows() - 1;
            Map<String, Set<Id>> holders = MatchSourceService.ownersOf(
                MatchSourceService.usableSources()[0],
                Account.SObjectType,
                new Set<String>{ 'pair@example.org' }
            );
            Test.stopTest();

            Assert.isTrue(holders.isEmpty(), 'A shrunk, cut lookup is not used: ' + holders);
            Assert.areEqual(1, MatchSourceSelector.cappedLookups, 'Counted once.');
        }
    }

    @IsTest
    static void aSpentTransactionSkipsTheSourcesAndSaysSo() {
        System.runAs(TestUsers.admin()) {
            MatchSourceSelector.sourcesOverride = new List<Match_Source__mdt>{
                row('Member_Email', 'Contact', 'Email', null, 'AccountId', 'Email')
            };
            List<Account> homes = householdsSharing('pair@example.org', 2);
            Contact incoming = new Contact(LastName = 'Desk', Email = 'pair@example.org');

            Test.startTest();
            MatchSourceSelector.queryReserve = Limits.getLimitQueries();
            Integer queriesBefore = Limits.getQueries();
            List<DuplicateService.Pair> pairs = MatchSourceService.pairsFor(
                new List<Id>{ homes[0].Id, homes[1].Id }
            );
            List<Set<Id>> found = MatchSourceService.holdersOfPeople(
                Account.SObjectType,
                new List<Map<String, String>>{
                    new Map<String, String>{ 'Email' => incoming.Email }
                }
            );
            Integer queriesRun = Limits.getQueries() - queriesBefore;
            Test.stopTest();
            Test.getEventBus().deliver();

            Assert.isTrue(pairs.isEmpty(), 'Nothing read, nothing paired: ' + pairs);
            Assert.isTrue(found[0].isEmpty(), 'Nothing read, nobody matched: ' + found);
            Assert.areEqual(0, queriesRun, 'No source query runs once the budget is spent.');
            List<Error_Log__c> logged = [
                SELECT Message__c
                FROM Error_Log__c
                WHERE Context__c = 'Match sources'
            ];
            // In a person account org the Individual lookup is skipped and logged too.
            Integer forTheSource = 0;
            for (Error_Log__c entry : logged) {
                if (entry.Message__c.contains('Member_Email')) {
                    forTheSource++;
                }
            }
            Assert.areEqual(1, forTheSource, 'One warning for the source: ' + logged);
        }
    }
}
