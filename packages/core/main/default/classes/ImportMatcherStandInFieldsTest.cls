/**
 * The person account lookups, run in any org shape. Their real fields (PersonEmail, LastName,
 * the person mailing postal code) exist only where Person Accounts are enabled, so these tests
 * point the matcher at standard Account fields that every org has (Website for the email,
 * Name for the last name, the shipping postal code for the person one) and prove the
 * lookup, keying, held-by-many and row cap logic on organization accounts. The Person Account
 * orgs' own tests (ImportPersonAccountTest) prove the real fields.
 */
@IsTest(testFor='ApexClass:ImportMatcher')
private class ImportMatcherStandInFieldsTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static Id organizationType() {
        return Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
            .getRecordTypeInfosByDeveloperName()
            .get('Organization')
            .getRecordTypeId();
    }

    private static void standInFields() {
        ImportMatcher.ACCOUNT_EMAIL_FIELD = 'Website';
        ImportMatcher.ACCOUNT_LAST_NAME_FIELD = 'Name';
        ImportMatcher.ACCOUNT_POSTAL_CODE_FIELD = 'ShippingPostalCode';
        ImportMatcher.ACCOUNT_BILLING_POSTAL_CODE_FIELD = 'BillingPostalCode';
    }

    private static Account account(String name, String site, String shipping, String billing) {
        return new Account(
            Name = name,
            Website = site,
            ShippingPostalCode = shipping,
            BillingPostalCode = billing,
            RecordTypeId = organizationType()
        );
    }

    @IsTest
    static void personAccountsAreFoundByEmailInTheGivenRecordTypes() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            insert new List<Account>{
                account('Ramirez', 'ana@example.org', null, null),
                account('Okafor', 'ben@example.org', null, null)
            };
            standInFields();

            Test.startTest();
            Map<String, Id> found = ImportMatcher.personAccountsByEmail(
                new Set<String>{ 'ana@example.org', 'nobody@example.org' },
                new Set<Id>{ organizationType() }
            );
            Test.stopTest();

            Assert.isNotNull(found.get('ana@example.org'), 'Ana is found by her email');
            Assert.isNull(found.get('ben@example.org'), 'Ben was not asked for');
            Assert.isNull(found.get('nobody@example.org'), 'Nobody matches nobody');
            Assert.isFalse(ImportMatcher.isHeldByMany('ana@example.org'), 'One holder');
        }
    }

    @IsTest
    static void twoPersonAccountsSharingAnEmailAreHeldByManyAndTheKeptOneFollowsTheRule() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            Account first = account('Ramirez', 'family@example.org', null, null);
            insert first;
            Account second = account('Ramirez', 'family@example.org', null, null);
            insert second;
            standInFields();
            ImportMatcher.forgetHeldKeys();

            Test.startTest();
            ImportMatcher.keepMostRecent(false);
            Map<String, Id> oldest = ImportMatcher.personAccountsByEmail(
                new Set<String>{ 'family@example.org' },
                new Set<Id>{ organizationType() }
            );
            ImportMatcher.keepMostRecent(true);
            Map<String, Id> newest = ImportMatcher.personAccountsByEmail(
                new Set<String>{ 'family@example.org' },
                new Set<Id>{ organizationType() }
            );
            Test.stopTest();

            Assert.isTrue(ImportMatcher.isHeldByMany('family@example.org'), 'Two hold the email');
            Assert.areEqual(first.Id, oldest.get('family@example.org'), 'The first created');
            Assert.areEqual(second.Id, newest.get('family@example.org'), 'The most recent');
        }
    }

    @IsTest
    static void emailLookupsAnswerNothingWithoutKeysOrRecordTypes() {
        System.runAs(TestUsers.admin()) {
            standInFields();
            Set<Id> types = new Set<Id>{ organizationType() };
            Set<String> emails = new Set<String>{ 'ana@example.org' };

            Assert.isTrue(ImportMatcher.personAccountsByEmail(emails, null).isEmpty(), 'No types');
            Assert.isTrue(
                ImportMatcher.personAccountsByEmail(emails, new Set<Id>()).isEmpty(),
                'Empty types'
            );
            Assert.isTrue(ImportMatcher.personAccountsByEmail(null, types).isEmpty(), 'No emails');
            Assert.isTrue(
                ImportMatcher.personAccountsByEmail(new Set<String>(), types).isEmpty(),
                'Empty emails'
            );
            Assert.isTrue(
                ImportMatcher.personAccountsByNameAndPostalCode(null, types).isEmpty(),
                'No keys'
            );
            Assert.isTrue(
                ImportMatcher.personAccountsByNameAndPostalCode(
                        new Set<String>{ ImportMatcher.nameAndPostalKey('Ramirez', '97201') },
                        null
                    )
                    .isEmpty(),
                'No types'
            );
        }
    }

    @IsTest
    static void aFieldTheOrgLacksIsAnsweredWithNothingNotAFailure() {
        System.runAs(TestUsers.admin()) {
            ImportMatcher.ACCOUNT_EMAIL_FIELD = 'NoSuchPersonField__x';
            ImportMatcher.ACCOUNT_LAST_NAME_FIELD = 'NoSuchPersonField__x';

            Assert.isTrue(
                ImportMatcher.personAccountsByEmail(
                        new Set<String>{ 'ana@example.org' },
                        new Set<Id>{ organizationType() }
                    )
                    .isEmpty(),
                'No email field, no match'
            );
            Assert.isTrue(
                ImportMatcher.personAccountsByNameAndPostalCode(
                        new Set<String>{ ImportMatcher.nameAndPostalKey('Ramirez', '97201') },
                        new Set<Id>{ organizationType() }
                    )
                    .isEmpty(),
                'No last name field, no match'
            );
        }
    }

    @IsTest
    static void personAccountsAreFoundByNameAndEitherPostalCode() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            Account byShipping = account('Ramirez', null, '97201', null);
            Account byBilling = account('Ramirez', null, null, '97202');
            Account elsewhere = account('Ramirez', null, '10001', '10002');
            insert new List<Account>{ byShipping, byBilling, elsewhere };
            standInFields();
            String shippingKey = ImportMatcher.nameAndPostalKey('Ramirez', '97201');
            String billingKey = ImportMatcher.nameAndPostalKey('Ramirez', '97202');

            Test.startTest();
            Map<String, Id> found = ImportMatcher.personAccountsByNameAndPostalCode(
                new Set<String>{ shippingKey, billingKey },
                new Set<Id>{ organizationType() }
            );
            Test.stopTest();

            Assert.areEqual(
                byShipping.Id,
                found.get(shippingKey),
                'Found by the person postal code'
            );
            Assert.areEqual(
                byBilling.Id,
                found.get(billingKey),
                'Found by the billing postal code'
            );
            Assert.isFalse(found.values().contains(elsewhere.Id), 'Another address is not matched');
        }
    }

    @IsTest
    static void aLookupThatReadsAsManyRecordsAsItMayIsMarkedCutOffAndLogged() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            insert new List<Account>{
                account('Ramirez', null, '97201', null),
                account('Ramirez', null, '97201', null)
            };
            standInFields();
            ImportMatcher.forgetHeldKeys();
            ImportMatcher.rowCap = 1;
            String key = ImportMatcher.nameAndPostalKey('Ramirez', '97201');

            Test.startTest();
            ImportMatcher.personAccountsByNameAndPostalCode(
                new Set<String>{ key },
                new Set<Id>{ organizationType() }
            );
            Test.stopTest();

            Assert.isTrue(ImportMatcher.wasCutOff(key), 'Another holder may exist unseen');
            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Error_Log__c
                    WHERE
                        Severity__c = :ErrorLogger.SEVERITY_WARNING
                        AND Context__c = 'ImportMatcher'
                ],
                'The cut off is logged once'
            );
        }
    }
}
