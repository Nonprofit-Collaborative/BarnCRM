/**
 * Giving receipts and Volunteers letters print the organization's address, and the address may
 * be left blank or written in six parts. These tests pin how the parts become printable lines,
 * and which half-filled addresses are refused (R-OA1).
 */
@IsTest(testFor='ApexClass:OrganizationAddress')
private class OrganizationAddressTest {
    @TestSetup
    static void makeUsers() {
        TestUsers.admin();
    }

    private static BarnCRM_Settings__c full() {
        return new BarnCRM_Settings__c(
            Organization_Street__c = '14 Bridge Street',
            Organization_Street_2__c = 'Suite 3',
            Organization_City__c = 'Springfield',
            Organization_State__c = 'IL',
            Organization_Postal_Code__c = '62701',
            Organization_Country__c = 'USA'
        );
    }

    @IsTest
    static void aFullAddressPrintsAsFourLinesWithCityStateAndZipTogether() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            List<String> lines = OrganizationAddress.lines(full());
            Test.stopTest();

            Assert.areEqual(
                new List<String>{ '14 Bridge Street', 'Suite 3', 'Springfield, IL 62701', 'USA' },
                lines,
                'Street, Street 2, then City, State Zip, then the country last'
            );
        }
    }

    @IsTest
    static void blankPartsAreLeftOutOfTheLines() {
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c noOptionalParts = full();
            noOptionalParts.Organization_Street_2__c = '  ';
            noOptionalParts.Organization_Country__c = null;

            Test.startTest();
            List<String> lines = OrganizationAddress.lines(noOptionalParts);
            Test.stopTest();

            Assert.areEqual(
                new List<String>{ '14 Bridge Street', 'Springfield, IL 62701' },
                lines,
                'Street 2 and Country are optional, so nothing prints for them'
            );
        }
    }

    @IsTest
    static void theOneLineFormJoinsTheLinesWithCommas() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            String line = OrganizationAddress.oneLine(full());
            Test.stopTest();

            Assert.areEqual(
                '14 Bridge Street, Suite 3, Springfield, IL 62701, USA',
                line,
                'The same lines, on one line'
            );
        }
    }

    @IsTest
    static void aBlankAddressPrintsNothing() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            List<String> lines = OrganizationAddress.lines(new BarnCRM_Settings__c());
            String line = OrganizationAddress.oneLine(new BarnCRM_Settings__c());
            List<String> noSettings = OrganizationAddress.lines(null);
            Test.stopTest();

            Assert.isTrue(lines.isEmpty(), 'No parts, no lines');
            Assert.areEqual('', line, 'And an empty one-line form');
            Assert.isTrue(noSettings.isEmpty(), 'A missing settings record is the same as blank');
        }
    }

    @IsTest
    static void aLocalityLineKeepsOnlyWhatIsPresent() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            List<String> cityOnly = OrganizationAddress.lines(
                new BarnCRM_Settings__c(Organization_City__c = 'Springfield')
            );
            List<String> stateAndZip = OrganizationAddress.lines(
                new BarnCRM_Settings__c(
                    Organization_State__c = 'IL',
                    Organization_Postal_Code__c = '62701'
                )
            );
            Test.stopTest();

            Assert.areEqual(new List<String>{ 'Springfield' }, cityOnly, 'No stray comma');
            Assert.areEqual(new List<String>{ 'IL 62701' }, stateAndZip, 'No leading comma');
        }
    }

    @IsTest
    static void theSavedAddressIsReadFromSettings() {
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c saved = TestDataFactory.defaultSettings();
            BarnCRM_Settings__c address = full();
            for (Schema.SObjectField part : OrganizationAddress.partFields()) {
                saved.put(part, address.get(part));
            }
            TestDataFactory.saveSettings(saved);

            Test.startTest();
            List<String> lines = OrganizationAddress.lines();
            String line = OrganizationAddress.oneLine();
            Map<String, String> parts = OrganizationAddress.savedParts();
            Test.stopTest();

            Assert.areEqual(4, lines.size(), 'The saved address prints as four lines');
            Assert.areEqual(
                '14 Bridge Street, Suite 3, Springfield, IL 62701, USA',
                line,
                'And as one line'
            );
            Assert.areEqual(6, parts.size(), 'One entry per part');
            Assert.areEqual('Springfield', parts.get('Organization_City__c'), 'Keyed by field');
        }
    }

    @IsTest
    static void aBlankSavedAddressGivesEmptyParts() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            Map<String, String> parts = OrganizationAddress.savedParts();
            Test.stopTest();

            Assert.areEqual('', parts.get('Organization_Street__c'), 'Empty, never null');
            Assert.areEqual('', parts.get('Organization_Country__c'), 'Empty, never null');
        }
    }

    @IsTest
    static void aBlankAddressAndAFullAddressAreBothAccepted() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            String blank = OrganizationAddress.refusal(new BarnCRM_Settings__c());
            String complete = OrganizationAddress.refusal(full());
            Test.stopTest();

            Assert.isNull(blank, 'The whole address may be left blank');
            Assert.isNull(complete, 'A complete address is accepted');
        }
    }

    @IsTest
    static void streetCityStateAndZipAreRequiredOnceAnyPartIsFilled() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            String refusal = OrganizationAddress.refusal(
                new BarnCRM_Settings__c(Organization_City__c = 'Springfield')
            );
            Test.stopTest();

            String missing =
                System.Label.Core_OrganizationAddress_Street +
                ', ' +
                System.Label.Core_OrganizationAddress_State +
                ', ' +
                System.Label.Core_OrganizationAddress_PostalCode;
            Assert.areEqual(
                String.format(
                    System.Label.Core_OrganizationAddress_IncompleteError,
                    new List<Object>{ missing }
                ),
                refusal,
                'The message names exactly what is missing'
            );
        }
    }

    @IsTest
    static void streetTwoAndCountryAloneAreNotEnough() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            String refusal = OrganizationAddress.refusal(
                new BarnCRM_Settings__c(
                    Organization_Street_2__c = 'Suite 3',
                    Organization_Country__c = 'USA'
                )
            );
            Test.stopTest();

            Assert.isNotNull(refusal, 'The optional parts do not make an address');
            Assert.isTrue(
                refusal.contains(System.Label.Core_OrganizationAddress_City),
                'And City is among the missing parts'
            );
        }
    }
}
