/**
 * The one-time rename of "Data hygiene: <check>" saved queries to "Data Quality: <check>"
 * (D-140), run by CorePostInstall on every install, upgrade and source deploy.
 */
@IsTest
private class DataHygieneSavedQueryRenameTest {
    private static final String CHECK = 'People with No Household';

    @TestSetup
    static void makeAdmin() {
        TestUsers.admin();
    }

    private static Saved_Query__c query(String name) {
        return new Saved_Query__c(Name = name, Object_Name__c = 'Contact', Query_JSON__c = '{}');
    }

    private static String nameOf(Id queryId) {
        return [SELECT Name FROM Saved_Query__c WHERE Id = :queryId WITH SYSTEM_MODE].Name;
    }

    @IsTest
    static void sourceDeployRenamesAnOldQueryAndLeavesOthersAlone() {
        System.runAs(TestUsers.admin()) {
            Saved_Query__c old = query('Data hygiene: ' + CHECK);
            Saved_Query__c own = query('My donors');
            insert new List<Saved_Query__c>{ old, own };

            Test.startTest();
            CorePostInstall.runAsSourceDeploy();
            Test.stopTest();

            Assert.areEqual('Data Quality: ' + CHECK, nameOf(old.Id), 'Renamed to the new name.');
            Assert.areEqual('My donors', nameOf(own.Id), 'Another query keeps its name.');
        }
    }

    @IsTest
    static void runningTwiceRenamesNothingMore() {
        System.runAs(TestUsers.admin()) {
            Saved_Query__c old = query('Data hygiene: ' + CHECK);
            insert old;

            Assert.areEqual(1, DataHygieneService.renameLegacySavedQueries(), 'First run renames.');
            Assert.areEqual(0, DataHygieneService.renameLegacySavedQueries(), 'Second finds none.');
            Assert.areEqual('Data Quality: ' + CHECK, nameOf(old.Id), 'Still the new name.');
        }
    }

    @IsTest
    static void keepsTheNewerQueryAndLeavesTheOldOneWhenBothExist() {
        System.runAs(TestUsers.admin()) {
            Saved_Query__c old = query('Data hygiene: ' + CHECK);
            Saved_Query__c newer = query('Data Quality: ' + CHECK);
            insert new List<Saved_Query__c>{ old, newer };

            Assert.areEqual(0, DataHygieneService.renameLegacySavedQueries(), 'Nothing renamed.');
            Assert.areEqual('Data hygiene: ' + CHECK, nameOf(old.Id), 'The old one is left alone.');
            Assert.areEqual('Data Quality: ' + CHECK, nameOf(newer.Id), 'The newer one is kept.');
            Assert.areEqual(
                2,
                [SELECT COUNT() FROM Saved_Query__c WITH SYSTEM_MODE],
                'Nothing is deleted.'
            );
        }
    }
}
