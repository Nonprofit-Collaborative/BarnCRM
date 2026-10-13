/**
 * Matching: each rule finds what it should, is bulk (one query per key set), and answers
 * "nothing" rather than throwing where the org cannot support the rule.
 */
@IsTest(testFor='ApexClass:ImportMatcher')
private class ImportMatcherTest {
    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
            insert new List<Contact>{
                new Contact(
                    FirstName = 'Ana',
                    LastName = 'Ramirez',
                    Email = 'ana@example.org',
                    MailingPostalCode = '97201'
                ),
                new Contact(
                    FirstName = 'Ben',
                    LastName = 'Okafor',
                    Email = 'ben@example.org',
                    MailingPostalCode = '97202'
                )
            };
        }
    }

    @IsTest
    static void findsContactsByEmailIgnoringCase() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            Map<String, Id> found = ImportMatcher.contactsByEmail(
                new Set<String>{ 'ana@example.org', 'BEN@EXAMPLE.ORG', 'nobody@example.org' }
            );
            Test.stopTest();
            Assert.areEqual(
                2,
                sharedKeys(found),
                'Both known emails match and the unknown one does not.'
            );
            Assert.isNotNull(
                found.get('ana@example.org'),
                'Keyed by the email folded to lower case.'
            );
            Assert.areEqual(
                found.get('ana@example.org'),
                found.get(ImportMatcher.firstNameKey('ana@example.org', 'Ana')),
                'And by the email narrowed to her first name (R-IB12).'
            );
        }
    }

    @IsTest
    static void findsContactsByLastNameAndPostalCode() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            Map<String, Id> found = ImportMatcher.contactsByNameAndPostalCode(
                new Set<String>{
                    ImportMatcher.nameAndPostalKey('Ramirez', '97201'),
                    ImportMatcher.nameAndPostalKey('Ramirez', '99999')
                }
            );
            Test.stopTest();
            Assert.areEqual(
                1,
                sharedKeys(found),
                'Only the name at the right postal code matches.'
            );
        }
    }

    @IsTest
    static void oneQueryPerKeySetNoMatterHowManyKeys() {
        System.runAs(TestUsers.admin()) {
            Set<String> emails = new Set<String>();
            for (Integer i = 0; i < 300; i++) {
                emails.add('person' + i + '@example.org');
            }
            Test.startTest();
            ImportMatcher.contactsByEmail(emails);
            Assert.areEqual(
                1,
                Limits.getQueries(),
                'Three hundred keys are one query, not three hundred: the matcher is bulk.'
            );
            Test.stopTest();
        }
    }

    @IsTest
    static void importOf250RowsStaysWellUnderTheQueryLimit() {
        System.runAs(TestUsers.admin()) {
            Set<String> emails = new Set<String>();
            Set<String> namePostalKeys = new Set<String>();
            Set<String> externalIds = new Set<String>();
            for (Integer i = 0; i < 250; i++) {
                emails.add('row' + i + '@example.org');
                namePostalKeys.add(
                    ImportMatcher.nameAndPostalKey('Row' + i, '9720' + Math.mod(i, 10))
                );
                externalIds.add('EXT-' + i);
            }

            Test.startTest();
            // One matching pass over a 250-row chunk, the way ImportRowProcessor drives it: every
            // rule the chunk needs is one query, never one query per row.
            ImportMatcher.contactsByEmail(emails);
            ImportMatcher.contactsByNameAndPostalCode(namePostalKeys);
            ImportMatcher.byExternalId(Contact.SObjectType, externalIds);
            Integer queriesUsed = Limits.getQueries();
            Test.stopTest();

            Assert.isTrue(
                queriesUsed < 20,
                'A 250-row import chunk across several rules stays far under the query limit, got ' +
                queriesUsed
            );
        }
    }

    @IsTest
    static void aCompositeKeyNeedsBothOfItsParts() {
        System.runAs(TestUsers.admin()) {
            Assert.isNull(
                ImportMatcher.nameAndPostalKey('Ramirez', null),
                'A row with no postal code cannot be matched on name plus postal code.'
            );
            Assert.isNull(ImportMatcher.nameAndPostalKey(null, '97201'), 'Nor one with no name.');
            Assert.isNotNull(
                ImportMatcher.nameAndPostalKey('Ramirez', '97201'),
                'Both parts, a key.'
            );
        }
    }

    @IsTest
    static void matchesOrganizationsByNameWithinTheirRecordType() {
        System.runAs(TestUsers.admin()) {
            Id organizationRecordType = Account.SObjectType.getDescribe(
                    SObjectDescribeOptions.DEFERRED
                )
                .getRecordTypeInfosByDeveloperName()
                .get('Organization')
                .getRecordTypeId();
            insert new Account(
                Name = 'Rose City Foundation',
                RecordTypeId = organizationRecordType
            );

            Test.startTest();
            Map<String, Id> found = ImportMatcher.accountsByName(
                new Set<String>{ 'rose city foundation' },
                organizationRecordType
            );
            Test.stopTest();
            Assert.areEqual(
                1,
                found.size(),
                'The organization is found by its name, ignoring case.'
            );
        }
    }

    @IsTest
    static void personAccountMatchingIsEmptyOnAnOrgWithoutThem() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            Map<String, Id> found = ImportMatcher.personAccountsByEmail(
                new Set<String>{ 'ana@example.org' },
                new Set<Id>()
            );
            Test.stopTest();
            Assert.isTrue(
                found.isEmpty(),
                'A platform-only org answers "nothing matched" rather than failing to compile.'
            );
        }
    }

    @IsTest
    static void anEmptyKeySetQueriesNothing() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            Map<String, Id> found = ImportMatcher.contactsByEmail(new Set<String>());
            Assert.areEqual(0, Limits.getQueries(), 'Nothing to look up, nothing queried.');
            Test.stopTest();
            Assert.isTrue(found.isEmpty(), 'And nothing found.');
        }
    }

    @IsTest
    static void blankKeysAreDroppedBeforeTheQuery() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            Map<String, Id> found = ImportMatcher.contactsByEmail(
                new Set<String>{ null, '', '   ', 'ana@example.org' }
            );
            Test.stopTest();
            Assert.areEqual(1, sharedKeys(found), 'Only the real key was looked up.');
        }
    }

    /**
     * A user who may not read the field a rule matches on is not matched on it: a user-mode
     * query naming it would fail the whole chunk. The lookup is skipped and the field is
     * named for the run log. The user here holds no permission set, so the Minimum Access
     * profile gives them no read access to a contact's email or postal code.
     */
    @IsTest
    static void aFieldTheUserCannotReadIsSkippedAndNamed() {
        System.runAs(TestUsers.admin()) {
            // Saved past a duplicate rule that only alerts: the org's own rules see its real data.
            Database.DMLOptions options = new Database.DMLOptions();
            options.DuplicateRuleHeader.AllowSave = true;
            Database.insert(
                new Contact(LastName = 'Noreadramirez', Email = 'noread.ana@example.org'),
                options
            );
            User reader = new User(
                ProfileId = [
                    SELECT Id
                    FROM Profile
                    WHERE Name = 'Minimum Access - Salesforce'
                    LIMIT 1
                ]
                .Id,
                LastName = 'Noread',
                Email = 'noread@barncrm.test.invalid',
                Username = 'noread' + DateTime.now().getTime() + '@barncrm.test.invalid',
                Alias = 'noread',
                TimeZoneSidKey = 'America/Los_Angeles',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US'
            );
            System.runAs(new User(Id = UserInfo.getUserId())) {
                insert reader;
            }
            Map<String, Id> byEmail;
            Map<String, Id> byPostal;
            Test.startTest();
            System.runAs(reader) {
                ImportMatcher.forgetHeldKeys();
                byEmail = ImportMatcher.contactsByEmail(
                    new Set<String>{ 'noread.ana@example.org' }
                );
                byPostal = ImportMatcher.contactsByNameAndPostalCode(
                    new Set<String>{ ImportMatcher.nameAndPostalKey('Noreadramirez', '97201') }
                );
            }
            Test.stopTest();
            Assert.isTrue(byEmail.isEmpty(), 'Nothing is matched on a field the user cannot read.');
            Assert.isTrue(byPostal.isEmpty(), 'Nor on a postal code they cannot read.');
            Assert.isTrue(
                ImportMatcher.unreadableFields().contains(Contact.Email.getDescribe().getLabel()),
                'The email field is named for the run log: ' + ImportMatcher.unreadableFields()
            );
            Assert.isTrue(
                ImportMatcher.unreadableFields()
                    .contains(Contact.MailingPostalCode.getDescribe().getLabel()),
                'So is the postal code.'
            );
        }
    }

    /**
     * `firstNameOf` asks this once per matched row, so the account describe is cached: every
     * row gets the same answer, case-insensitively, for a field that exists and one that does not.
     */
    @IsTest
    static void accountFieldPresenceIsAnsweredFromOneDescribe() {
        System.runAs(TestUsers.admin()) {
            for (Integer row = 0; row < 200; row++) {
                Assert.isTrue(ImportMatcher.accountHasField('Name'), 'Every account has a name');
                Assert.isTrue(ImportMatcher.accountHasField('NAME'), 'Field names ignore case');
                Assert.isFalse(
                    ImportMatcher.accountHasField('Not_A_Field__c'),
                    'A field the org lacks is absent on every row'
                );
            }
        }
    }

    /** The keys a lookup was asked for, leaving out each one narrowed to a first name. */
    private static Integer sharedKeys(Map<String, Id> found) {
        Integer count = 0;
        for (String key : found.keySet()) {
            if (ImportMatcher.baseKey(key) == key) {
                count++;
            }
        }
        return count;
    }
}
