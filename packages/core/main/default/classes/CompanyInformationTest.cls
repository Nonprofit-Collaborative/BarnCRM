@IsTest(testFor='ApexClass:CompanyInformation, ApexClass:SettingsController')
private class CompanyInformationTest {
    @TestSetup
    static void createUsers() {
        TestUsers.admin();
    }

    private static void companyIs(String json) {
        CompanyInformation.companyOverride = (Organization) System.JSON.deserialize(
            json,
            Organization.class
        );
    }

    @IsTest
    static void aCompleteAddressBecomesTheSixPartsWithExtraStreetLinesAsStreet2() {
        System.runAs(TestUsers.admin()) {
            companyIs(
                '{"Name":" Barn Rescue Inc ","Street":"12 Mill Road\\r\\nUnit 4\\nBack Barn",' +
                '"City":"Springfield","State":"IL","PostalCode":"62701","Country":"USA"}'
            );

            Map<String, String> parts = CompanyInformation.addressParts();

            Assert.areEqual('Barn Rescue Inc', CompanyInformation.name(), 'Trimmed');
            Assert.areEqual('12 Mill Road', parts.get('Organization_Street__c'), 'First line');
            Assert.areEqual(
                'Unit 4, Back Barn',
                parts.get('Organization_Street_2__c'),
                'The other lines'
            );
            Assert.areEqual('Springfield', parts.get('Organization_City__c'), 'City');
            Assert.areEqual('IL', parts.get('Organization_State__c'), 'State');
            Assert.areEqual('62701', parts.get('Organization_Postal_Code__c'), 'Postal code');
            Assert.areEqual('USA', parts.get('Organization_Country__c'), 'Country');
            Assert.areEqual(
                parts,
                SettingsController.getCompanyAddress(),
                'The address panel is offered exactly these parts'
            );
            Assert.isNull(
                OrganizationAddress.refusal(
                    new BarnCRM_Settings__c(
                        Organization_Street__c = parts.get('Organization_Street__c'),
                        Organization_City__c = parts.get('Organization_City__c'),
                        Organization_State__c = parts.get('Organization_State__c'),
                        Organization_Postal_Code__c = parts.get('Organization_Postal_Code__c')
                    )
                ),
                'What is offered can be saved as it is (R-OA1)'
            );
        }
    }

    @IsTest
    static void anIncompleteAddressOrNoCompanyOffersNothing() {
        System.runAs(TestUsers.admin()) {
            companyIs('{"Name":"  ","Street":"12 Mill Road","City":"Springfield","State":"IL"}');
            Assert.isTrue(CompanyInformation.addressParts().isEmpty(), 'No postal code');
            Assert.isNull(CompanyInformation.name(), 'A blank name is no name');

            CompanyInformation.companyOverride = null;
            Assert.isTrue(CompanyInformation.addressParts().isEmpty(), 'Nothing to read');
            Assert.isNull(CompanyInformation.name(), 'Nothing to read');
        }
    }
}
