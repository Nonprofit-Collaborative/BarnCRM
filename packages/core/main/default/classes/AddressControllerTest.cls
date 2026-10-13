/** The address panel's server side: reading a record's addresses and changing which one is used. */
@IsTest
private class AddressControllerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static final String HOME_STREET = '812 Willow Lane';
    private static final String WINTER_STREET = '4120 East Camelback Road';

    private static Account garciaHousehold() {
        Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
        garcia.BillingStreet = HOME_STREET;
        garcia.BillingCity = 'Springfield';
        insert garcia;
        return garcia;
    }

    @IsTest
    static void getAddressesReturnsTheAddressInUseFirst() {
        System.runAs(TestUsers.admin()) {
            Account garcia = garciaHousehold();
            insert new Address__c(
                Account__c = garcia.Id,
                Type__c = 'Seasonal',
                Street__c = WINTER_STREET,
                City__c = 'Phoenix',
                Seasonal_Start_Month__c = 1,
                Seasonal_Start_Day__c = 1,
                Seasonal_End_Month__c = 3,
                Seasonal_End_Day__c = 31
            );

            Test.startTest();
            List<AddressController.AddressView> views = AddressController.getAddresses(garcia.Id);
            Test.stopTest();

            Assert.areEqual(2, views.size(), 'The household has two addresses on file.');
            Assert.isTrue(views[0].isDefault, 'The address in use comes first.');
            Assert.areEqual(HOME_STREET, views[0].street, 'The home address is the one in use.');
            Assert.isTrue(views[1].isSeasonal, 'The second address is the seasonal one.');
            Assert.areEqual(
                'January 1',
                views[1].seasonalStart,
                'The range reads as a date, not two numbers.'
            );
            Assert.areEqual(
                'March 31',
                views[1].seasonalEnd,
                'The range reads as a date, not two numbers.'
            );
        }
    }

    @IsTest
    static void getAddressesRefusesToGuessWhoseAddressesToShow() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            try {
                AddressController.getAddresses(null);
                Assert.fail('Asking for nobody\'s addresses should be refused.');
            } catch (AuraHandledException e) {
                Assert.areEqual(
                    Label.Core_Address_OwnerRequired,
                    e.getMessage(),
                    'The panel should be told what is missing.'
                );
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void setDefaultMovesTheBadgeAndTheStandardFields() {
        System.runAs(TestUsers.admin()) {
            Account garcia = garciaHousehold();
            Address__c winter = new Address__c(
                Account__c = garcia.Id,
                Type__c = 'Other',
                Street__c = WINTER_STREET,
                City__c = 'Phoenix'
            );
            insert winter;

            Test.startTest();
            List<AddressController.AddressView> views = AddressController.setDefault(winter.Id);
            Test.stopTest();

            Assert.areEqual(2, views.size(), 'Both addresses come back.');
            Assert.areEqual(
                winter.Id,
                views[0].id,
                'The address just chosen is now the one in use.'
            );
            Assert.isTrue(views[0].isDefault, 'It carries the badge.');
            Assert.isFalse(views[1].isDefault, 'The other address lost the badge.');
            Account moved = [SELECT BillingStreet FROM Account WHERE Id = :garcia.Id];
            Assert.areEqual(WINTER_STREET, moved.BillingStreet, 'The standard fields followed.');
        }
    }

    @IsTest
    static void setDefaultSaysSoWhenTheAddressIsGone() {
        System.runAs(TestUsers.admin()) {
            Account garcia = garciaHousehold();
            Address__c only = [SELECT Id FROM Address__c WHERE Account__c = :garcia.Id LIMIT 1];
            Id goneId = only.Id;
            delete only;

            Test.startTest();
            try {
                AddressController.setDefault(goneId);
                Assert.fail('Setting a deleted address as the default should be refused.');
            } catch (AuraHandledException e) {
                Assert.areEqual(
                    Label.Core_Address_NotFound,
                    e.getMessage(),
                    'The panel should be told the address is gone.'
                );
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void setDefaultRefusesAnEmptyRequest() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            try {
                AddressController.setDefault(null);
                Assert.fail('Setting nothing as the default should be refused.');
            } catch (AuraHandledException e) {
                Assert.areEqual(
                    Label.Core_Address_NotFound,
                    e.getMessage(),
                    'The panel should be told what is missing.'
                );
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void aPersonsOwnAddressesAreReadableFromTheirRecord() {
        System.runAs(TestUsers.admin()) {
            Account garcia = garciaHousehold();
            Contact ana = AddressTestDataFactory.newContact('Ana', 'Garcia', garcia.Id);
            insert ana;
            insert new Address__c(
                Contact__c = ana.Id,
                Type__c = 'Other',
                Street__c = '19 College Green',
                City__c = 'Urbana',
                Is_Default__c = true
            );

            Test.startTest();
            List<AddressController.AddressView> views = AddressController.getAddresses(ana.Id);
            Test.stopTest();

            Assert.areEqual(1, views.size(), 'Ana has one address of her own.');
            Assert.areEqual(
                '19 College Green',
                views[0].street,
                'It is the address on her own record.'
            );
            Assert.isFalse(views[0].isSeasonal, 'It is not a seasonal address.');
            Assert.areEqual(null, views[0].seasonalStart, 'A plain address has no seasonal range.');
        }
    }

    @IsTest
    static void selectorReturnsNothingWhenAskedForNothing() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            Assert.areEqual(
                0,
                AddressSelector.selectByOwnerIds(null).size(),
                'No owners, no addresses.'
            );
            Assert.areEqual(
                0,
                AddressSelector.selectByOwnerIds(new Set<Id>()).size(),
                'No owners, no addresses.'
            );
            Assert.areEqual(
                0,
                AddressSelector.selectDefaultsByOwnerIds(null, null).size(),
                'No owners, no defaults.'
            );
            Assert.areEqual(0, AddressSelector.selectByIds(null).size(), 'No ids, no addresses.');
            Test.stopTest();
        }
    }
}
