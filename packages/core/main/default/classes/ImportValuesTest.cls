/**
 * The value helpers every import path shares: one comparison, one digest, one slicing.
 */
@IsTest
private class ImportValuesTest {
    @IsTest
    static void comparesValuesAsTheSaveWouldWriteThem() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            Assert.isTrue(ImportValues.same(100.00, 100), 'A number is a number, whatever scale.');
            Assert.isTrue(ImportValues.same(Decimal.valueOf('1.50'), Decimal.valueOf('1.5')));
            Assert.isFalse(ImportValues.same(100, 101));
            Assert.isTrue(
                ImportValues.same(Date.newInstance(2026, 1, 5), Date.newInstance(2026, 1, 5)),
                'Dates by value.'
            );
            Assert.isTrue(ImportValues.same(true, true));
            Assert.isFalse(ImportValues.same('ana', 'Ana'), 'A correction of capitals counts.');
            Assert.isTrue(ImportValues.same('Ana', 'Ana'));
            Assert.isTrue(ImportValues.same(null, null));
            Assert.isFalse(ImportValues.same(null, 'Ana'));
            Assert.isFalse(ImportValues.same('text', 5), 'Text is no number.');
            Id userId = UserInfo.getUserId();
            Assert.isTrue(
                ImportValues.same(String.valueOf(userId).left(15), userId),
                'An ID in either length.'
            );
            Test.stopTest();
        }
    }

    @IsTest
    static void slicesDigestsAndReadsIds() {
        System.runAs(TestUsers.admin()) {
            Set<String> keys = new Set<String>{ 'a', 'b', '', 'c', null, 'd', 'e' };
            Test.startTest();
            List<List<String>> slices = ImportValues.slices(keys, 2);
            Test.stopTest();

            Assert.areEqual(3, slices.size(), 'Five keys in twos, blanks dropped.');
            Assert.areEqual(new List<String>{ 'e' }, slices[2]);
            Assert.isTrue(ImportValues.slices(null, 2).isEmpty());
            Assert.areEqual(16, ImportValues.digest('P', 'key').length(), 'Sixteen hex digits.');
            Assert.areEqual(ImportValues.digest('P', 'key'), ImportValues.digest('P', 'key'));
            Assert.areNotEqual(ImportValues.digest('P', 'key'), ImportValues.digest('O', 'key'));
            Assert.isNull(ImportValues.idOrNull('not an id'));
            Assert.isNull(ImportValues.idOrNull(' '));
            Assert.areEqual(
                UserInfo.getUserId(),
                ImportValues.idOrNull(' ' + UserInfo.getUserId() + ' ')
            );
            Assert.areEqual(7, ImportValues.rowNumber(new Import_Row__c(Row_Number__c = 7)));
            Assert.isNull(ImportValues.rowNumber(null));
        }
    }

    /** Decimals compared by value, so 1250 and 1250.00 agree. */
    private static void reads(Decimal expected, Decimal actual) {
        reads(expected, actual, '');
    }

    private static void reads(Decimal expected, Decimal actual, String why) {
        Assert.isTrue(
            actual != null && actual == expected,
            'Expected ' + expected + ', read ' + actual + '. ' + why
        );
    }

    @IsTest
    static void readsNumbersAsSpreadsheetsExportThem() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            // United States: point for decimals, comma for groups.
            reads(1250.00, ImportValues.number('$1,250.00', '.', ','));
            reads(100, ImportValues.number('€100', '.', ','));
            reads(-45.00, ImportValues.number('(45.00)', '.', ','));
            reads(-45, ImportValues.number('-45', '.', ','));
            reads(-45, ImportValues.number('45-', '.', ','));
            reads(1250, ImportValues.number('USD 1,250', '.', ','));
            reads(1250000, ImportValues.number('1,250,000', '.', ','));
            reads(12.5, ImportValues.number('12.5%', '.', ','));
            reads(0.5, ImportValues.number('.5', '.', ','));
            reads(
                1234.5,
                ImportValues.number('1.234,5', '.', ','),
                'Both marks: the later is the decimal.'
            );
            // Germany: comma for decimals, point for groups.
            reads(1250.5, ImportValues.number('1.250,50 €', ',', '.'));
            reads(1.5, ImportValues.number('1,5', ',', '.'));
            reads(1250, ImportValues.number('1.250', ',', '.'));
            // France: comma for decimals, a space for groups.
            reads(1250.5, ImportValues.number('1 250,50', ',', ''));
            reads(1250.5, ImportValues.number('1\u202F250,50', ',', ''));
            reads(1.5, ImportValues.number('1.5', ',', ''), 'A point with no group of three.');
            // Switzerland: apostrophes group.
            reads(1250.5, ImportValues.number('1\'250.50', '.', '\u2019'));

            // Anything that would be a guess is refused.
            Assert.isNull(ImportValues.number('1,25', '.', ','), 'A comma that groups nothing.');
            Assert.isNull(
                ImportValues.number('1.250', ',', ''),
                'A thousand or one and a quarter.'
            );
            Assert.isNull(ImportValues.number('1.2.3,4', '.', ','));
            Assert.isNull(ImportValues.number('1,234,5.6', '.', ','));
            Assert.isNull(ImportValues.number('(-45)', '.', ','), 'Negative twice.');
            Assert.isNull(ImportValues.number('12abc', '.', ','));
            Assert.isNull(ImportValues.number('', '.', ','));
            Assert.isNull(ImportValues.number(null, '.', ','));
            Test.stopTest();
        }
    }

    @IsTest
    static void readsNumbersInTheRunningUsersLocale() {
        System.runAs(TestUsers.admin()) {
            Decimal amount = Decimal.valueOf('1234567.89');
            Test.startTest();
            Decimal read = ImportValues.number(amount.format());
            Decimal grouped = ImportValues.number('$' + Decimal.valueOf('1250').format());
            Test.stopTest();

            reads(amount, read);
            reads(1250, grouped);
        }
    }
}
