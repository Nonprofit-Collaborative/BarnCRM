/**
 * Reading one import row's gift (R-GI1 to R-GI4): what is read, and every way a row is
 * refused before anything is looked up or saved.
 */
@IsTest(testFor='ApexClass:GiftImportRow')
private class GiftImportRowTest {
    private static GiftImportRow read(Map<String, Map<String, String>> entities) {
        return new GiftImportRow(new Import_Row__c(), entities);
    }

    private static Map<String, Map<String, String>> gift(String amount, String giftDate) {
        Map<String, String> values = new Map<String, String>{ 'Type__c' => 'Cash' };
        if (amount != null) {
            values.put('Amount__c', amount);
        }
        if (giftDate != null) {
            values.put('Gift_Date__c', giftDate);
        }
        return new Map<String, Map<String, String>>{ 'Gift' => values };
    }

    @IsTest
    static void aRowWithNoGiftColumnsCarriesNoGift() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GiftImportRow row = read(
                new Map<String, Map<String, String>>{
                    'Contact1' => new Map<String, String>{ 'LastName' => 'Ramirez' }
                }
            );
            Assert.isFalse(row.carriesGift, 'A donor list row is not a gift.');
            Assert.isNull(row.error, 'And is not refused for it.');
        }
    }

    @IsTest
    static void readsTheGiftValues() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Map<String, Map<String, String>> entities = gift('$1,250.50', '2026-03-15');
            entities.get('Gift').remove('Type__c');
            entities.get('Gift').put('type__c', 'credit card');
            entities.get('Gift').put('Payment_Reference__c', 'TX-9');
            entities.get('Gift').put('External_Id__c', 'stripe-1');
            entities.get('Gift').put('Appeal', 'Spring Appeal');
            entities.get('Gift').put('Donor', 'organization');

            GiftImportRow row = read(entities);

            Assert.isNull(row.error, 'Nothing to refuse: ' + row.error);
            Assert.isTrue(row.carriesGift, 'The row is a gift.');
            Assert.isTrue(row.amount == 1250.50, 'Currency sign and thousands separator ignored.');
            Assert.areEqual(Date.newInstance(2026, 3, 15), row.giftDate, 'ISO date read.');
            Assert.areEqual('Card', row.values.get(Gift__c.Type__c), 'A common word for Card.');
            Assert.areEqual('TX-9', row.values.get(Gift__c.Payment_Reference__c), 'Text as it is.');
            Assert.areEqual('stripe-1', row.externalId, 'The external ID is read for matching.');
            Assert.areEqual('Spring Appeal', row.appeal, 'The appeal by name.');
            Assert.areEqual(GiftImportRow.DONOR_ORGANIZATION, row.donorChoice, 'Any capitals.');
        }
    }

    @IsTest
    static void aWorkbookDateWithATimeReads() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Assert.areEqual(
                Date.newInstance(2026, 1, 2),
                GiftImportRowTest.read(gift('10', '2026-01-02 00:00')).giftDate,
                'The time a workbook cell carries is ignored.'
            );
        }
    }

    @IsTest
    static void refusesWhatItCannotRead() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Map<String, String> refusals = new Map<String, String>{
                'no amount' => read(gift(null, '2026-03-15')).error,
                'bad amount' => read(gift('ten', '2026-03-15')).error,
                'zero' => read(gift('0', '2026-03-15')).error,
                'no date' => read(gift('10', null)).error,
                'bad date' => read(gift('10', '2026-02-30')).error
            };
            Assert.areEqual(
                Label.Giving_Import_ErrorAmountMissing,
                refusals.get('no amount'),
                'Amount required.'
            );
            Assert.isTrue(
                refusals.get('bad amount').contains('ten'),
                'Names the unreadable amount.'
            );
            Assert.areEqual(
                Label.Giving_Import_ErrorAmountNotPositive,
                refusals.get('zero'),
                'More than zero.'
            );
            Assert.areEqual(
                Label.Giving_Import_ErrorDateMissing,
                refusals.get('no date'),
                'Date required.'
            );
            Assert.isTrue(
                refusals.get('bad date').contains('2026-02-30'),
                'A date that does not exist is refused, never moved to another day.'
            );

            Map<String, Map<String, String>> noType = gift('10', '2026-03-15');
            noType.get('Gift').remove('Type__c');
            Assert.areEqual(
                Label.Giving_Import_ErrorTypeMissing,
                read(noType).error,
                'A payment method is required, never guessed.'
            );

            Map<String, Map<String, String>> unknownType = gift('10', '2026-03-15');
            unknownType.get('Gift').put('Type__c', 'barter');
            String typeError = read(unknownType).error;
            Assert.isTrue(
                typeError.contains('barter') && typeError.contains('Card'),
                'Names the choices.'
            );

            Map<String, Map<String, String>> badDonor = gift('10', '2026-03-15');
            badDonor.get('Gift').put('Donor', 'Neighbor');
            Assert.isTrue(
                read(badDonor).error.contains('Neighbor'),
                'A donor choice is one of three.'
            );
        }
    }

    @IsTest
    static void aFundOrACreditWithoutAGiftIsRefused() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GiftImportRow row = read(
                new Map<String, Map<String, String>>{
                    'Allocation' => new Map<String, String>{ 'Fund' => 'General' }
                }
            );
            Assert.areEqual(
                Label.Giving_Import_ErrorPartsWithoutGift,
                row.error,
                'Nothing to allocate.'
            );
        }
    }

    @IsTest
    static void theFieldsThePackageWritesAreNotTakenFromAFile() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Map<String, Map<String, String>> entities = gift('10', '2026-03-15');
            entities.get('Gift').put('Status__c', 'Refunded');
            entities.get('Gift').put('Receipt_Number__c', 'R-1');
            entities.get('Gift').put('Not_A_Field__c', 'x');

            GiftImportRow row = read(entities);

            Assert.isNull(row.error, 'Not refused.');
            Assert.isFalse(row.values.containsKey(Gift__c.Status__c), 'Status is always Received.');
            Assert.isFalse(
                row.values.containsKey(Gift__c.Receipt_Number__c),
                'The sequence numbers.'
            );
            Assert.areEqual(3, row.notLoaded.size(), 'And the run log names all three.');
        }
    }

    @IsTest
    static void oneFundIsTheWholeGift() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Map<String, Map<String, String>> entities = gift('10', '2026-03-15');
            entities.put('Allocation', new Map<String, String>{ 'Fund' => 'General' });

            GiftImportRow row = read(entities);

            Assert.isFalse(row.isSplit(), 'Not a split.');
            Assert.areEqual('General', row.singleFund.fund, 'The fund named.');
        }
    }

    @IsTest
    static void aSplitIsReadInOrderAndMustAddUp() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Map<String, Map<String, String>> entities = gift('100', '2026-03-15');
            entities.put(
                'Allocation',
                new Map<String, String>{
                    'Fund1' => 'General',
                    'Amount1' => '60',
                    'Fund2' => 'Scholarships',
                    'Amount2' => '40'
                }
            );
            GiftImportRow row = read(entities);
            Assert.isNull(row.error, 'It adds up: ' + row.error);
            Assert.areEqual(2, row.parts.size(), 'Two parts.');
            Assert.areEqual('Scholarships', row.parts[1].fund, 'In order.');

            entities.get('Allocation').put('Amount2', '30');
            Assert.isTrue(read(entities).error.contains('90'), 'A short split names its total.');

            entities.put(
                'Allocation',
                new Map<String, String>{
                    'Fund1' => 'General',
                    'Percent1' => '50',
                    'Fund2' => 'Scholarships',
                    'Percent2' => '40'
                }
            );
            Assert.isTrue(read(entities).error.contains('90'), 'Percents must reach 100.');

            entities.get('Allocation').put('Amount2', '40');
            entities.get('Allocation').remove('Percent2');
            Assert.areEqual(
                Label.Giving_Import_ErrorSplitMixed,
                read(entities).error,
                'Not a mix.'
            );

            entities.put(
                'Allocation',
                new Map<String, String>{
                    'Fund1' => 'General',
                    'Amount1' => '60',
                    'Amount2' => '40'
                }
            );
            Assert.isTrue(read(entities).error.contains('2'), 'A part with no fund is named.');
        }
    }

    @IsTest
    static void valuesReadAsTheirFieldsTypes() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Map<String, Map<String, String>> entities = gift('10', '2026-03-15');
            entities.get('Gift').put('Fair_Market_Value__c', '8.00');
            GiftImportRow row = read(entities);
            Assert.isTrue((Decimal) row.values.get(Gift__c.Fair_Market_Value__c) == 8, 'A number.');

            entities.get('Gift').put('Fair_Market_Value__c', 'eight');
            Assert.isTrue(
                read(entities).error.contains('eight'),
                'An unreadable number is refused.'
            );
        }
    }
}
