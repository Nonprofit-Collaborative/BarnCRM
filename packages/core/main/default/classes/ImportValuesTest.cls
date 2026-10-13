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
}
