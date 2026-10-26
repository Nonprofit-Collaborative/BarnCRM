/**
 * How Core finds the entity processor a dependent package installed (R-IR6). A class that is
 * not in the org is the ordinary case and says nothing; a class of the wrong shape is left out
 * and written to the Error Log, because it means a package shipped a broken processor.
 */
@IsTest(testFor='ApexClass:ImportEntityProcessors')
private class ImportEntityProcessorsTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static Integer logged() {
        Test.getEventBus().deliver();
        return [
            SELECT COUNT()
            FROM Error_Log__c
            WHERE Context__c = 'ImportEntityProcessors.resolve'
            WITH SYSTEM_MODE
        ];
    }

    @IsTest
    static void aClassThatIsNotInTheOrgIsNoProcessorAndNoError() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            ImportEntityProcessor found = ImportEntityProcessors.resolve(
                'NoSuchImportProcessorFu3'
            );
            Test.stopTest();

            Assert.isNull(found, 'A package that is not installed contributes nothing');
            Assert.areEqual(0, logged(), 'An org without the package is not an error');
        }
    }

    @IsTest
    static void aClassOfTheWrongShapeIsLeftOutAndLogged() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            // A real class with a no-argument constructor that does not implement the interface.
            ImportEntityProcessor found = ImportEntityProcessors.resolve('ImportEntityProcessors');
            Test.stopTest();

            Assert.isNull(found, 'Only a class that implements the interface is used');
            Assert.areEqual(1, logged(), 'The wrong shape is written to the Error Log');
        }
    }
}
