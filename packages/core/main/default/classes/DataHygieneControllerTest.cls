/**
 * The Data Hygiene tab's controller (C-28, canonical model R-SQ6): the Find permission, every
 * check returned, and "Open in Find" saving one unshared saved query per check and person, put
 * back to the check's own query each time.
 *
 * No org has run these yet; they are written against the behaviour the class documents.
 */
@IsTest
private class DataHygieneControllerTest {
    private static User maria() {
        return TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
    }

    private static void contactMode() {
        BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
            HouseholdTestDataFactory.MODE_CONTACT
        );
        HouseholdTestDataFactory.save(settings);
        OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
        shape.hasNativeHouseholdGroups = false;
        OrgShapeDetector.overrideShape = shape;
    }

    @IsTest
    static void withoutTheFindPermissionTheConsoleSaysWhichOneIsMissing() {
        System.runAs(TestUsers.admin()) {
            User sam = TestDataFactory.createUser('Sam', new List<String>{ 'BarnCRM_Staff' });

            System.runAs(sam) {
                for (Integer attempt = 0; attempt < 2; attempt++) {
                    try {
                        if (attempt == 0) {
                            DataHygieneController.getChecks();
                        } else {
                            DataHygieneController.openInFind(
                                DataHygieneService.HOUSEHOLDS_WITHOUT_MEMBERS
                            );
                        }
                        Assert.fail('The console needs the Find permission.');
                    } catch (AuraHandledException refused) {
                        Assert.areEqual(
                            System.Label.Core_DataHygiene_ErrorNoPermission,
                            refused.getMessage(),
                            'The message names the permission.'
                        );
                    }
                }
            }

        }
    }

    @IsTest
    static void getChecksReturnsEveryCheck() {
        System.runAs(TestUsers.admin()) {
            contactMode();
            User maria = maria();

            List<DataHygieneService.CheckResult> results;
            System.runAs(maria) {
                results = DataHygieneController.getChecks();
            }

            Assert.areEqual(DataHygieneService.CHECK_KEYS.size(), results.size(), 'Every check.');
        }
    }

    @IsTest
    static void openInFindSavesOneUnsharedQueryOfHerOwnAndPutsItBack() {
        System.runAs(TestUsers.admin()) {
            contactMode();
            User maria = maria();
            String key = DataHygieneService.HOUSEHOLDS_WITHOUT_MEMBERS;

            DataHygieneController.OpenInFind first;
            DataHygieneController.OpenInFind second;
            Saved_Query__c saved;
            System.runAs(maria) {
                first = DataHygieneController.openInFind(key);
                String document = DataHygieneService.queryDocument(key);
                String edited = document.replace('"limit":200', '"limit":5');
                Assert.areNotEqual(document, edited, 'The test edits the saved copy.');
                update new Saved_Query__c(Id = first.savedQueryId, Query_JSON__c = edited);
                second = DataHygieneController.openInFind(key);
                saved = [
                    SELECT Name, OwnerId, Shared__c, Object_Name__c, Query_JSON__c
                    FROM Saved_Query__c
                    WHERE Id = :second.savedQueryId
                ];
            }

            Assert.isNotNull(first.savedQueryId, 'The saved query is returned for the Find tab.');
            Assert.areEqual(first.savedQueryId, second.savedQueryId, 'Opening again reuses it.');
            Assert.areEqual(saved.Name, second.savedQueryName, 'Its name, for the page to show.');
            Assert.areEqual(
                NamespaceUtil.qualify('Find'),
                second.findTabApiName,
                'The Find tab, with any namespace.'
            );
            Assert.areEqual(
                NamespaceUtil.stateKey('savedQueryId'),
                second.stateKey,
                'And the page state key Find will read.'
            );
            Assert.areEqual(
                DataHygieneService.savedQueryName(key),
                saved.Name,
                'Named for the check.'
            );
            Assert.areEqual(maria.Id, saved.OwnerId, 'Hers.');
            Assert.isFalse(saved.Shared__c, 'Not shared with anyone.');
            Assert.areEqual('Account', saved.Object_Name__c, 'Over households.');
            Assert.areEqual(
                DataHygieneService.queryDocument(key),
                saved.Query_JSON__c,
                'Put back to the check own query.'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Saved_Query__c WHERE OwnerId = :maria.Id],
                'One saved query, not one per press.'
            );
        }
    }

    /** With two of her own queries of the check's name, Find opens the one just put back. */
    @IsTest
    static void openInFindOpensTheQueryItSavedWhenTwoShareTheName() {
        System.runAs(TestUsers.admin()) {
            contactMode();
            User maria = maria();
            String key = DataHygieneService.HOUSEHOLDS_WITHOUT_MEMBERS;
            DataHygieneController.OpenInFind first;
            DataHygieneController.OpenInFind again;
            System.runAs(maria) {
                first = DataHygieneController.openInFind(key);
                insert new Saved_Query__c(
                    Name = first.savedQueryName,
                    Object_Name__c = 'Account',
                    Query_JSON__c = DataHygieneService.queryDocument(key)
                );
                again = DataHygieneController.openInFind(key);
            }
            Assert.areEqual(first.savedQueryId, again.savedQueryId, 'The query it updated.');
        }
    }

    @IsTest
    static void aCheckFindCannotListIsNotOpened() {
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
                HouseholdTestDataFactory.MODE_JUNCTION
            );
            HouseholdTestDataFactory.save(settings);
            User maria = maria();

            System.runAs(maria) {
                try {
                    DataHygieneController.openInFind(DataHygieneService.PEOPLE_WITHOUT_HOUSEHOLD);
                    Assert.fail('Junction mode people cannot be listed in Find yet.');
                } catch (AuraHandledException refused) {
                    Assert.areEqual(
                        System.Label.Core_DataHygiene_NotInFindYet,
                        refused.getMessage(),
                        'And the person is told so.'
                    );
                }
            }
            Assert.areEqual(0, [SELECT COUNT() FROM Saved_Query__c], 'Nothing is saved.');
        }
    }

    @IsTest
    static void anUnknownCheckIsRefusedInWords() {
        System.runAs(TestUsers.admin()) {
            User maria = maria();

            System.runAs(maria) {
                try {
                    DataHygieneController.openInFind('no_such_check');
                    Assert.fail('An unknown check is refused.');
                } catch (AuraHandledException refused) {
                    Assert.areEqual(
                        System.Label.Core_DataHygiene_UnknownCheck,
                        refused.getMessage(),
                        'With a message.'
                    );
                }
            }

        }
    }
}
