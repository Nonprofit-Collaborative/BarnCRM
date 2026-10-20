/**
 * The Erase person action's controller: a refusal reaches the screen as its own message, and a
 * preview and an erasure pass straight through to `PersonErasure`.
 */
@IsTest(testFor='ApexClass:PersonErasureController')
private class PersonErasureControllerTest {
    @TestSetup
    static void createTestUsers() {
        TestUsers.withPermissionSets(
            new List<String>{ TestUsers.CORE_ADMIN, 'BarnCRM_Erase_People' }
        );
        TestUsers.admin();
    }

    /** An installed extension that fails in a way the erasure does not translate itself. */
    private class BrokenExtension implements PersonErasureExtension {
        public Set<Schema.SObjectField> fieldsToKeep(Schema.SObjectType personType) {
            throw new NullPointerException();
        }

        public List<PersonErasure.Change> erase(Id personId) {
            return new List<PersonErasure.Change>();
        }
    }

    @IsTest
    static void anUnexpectedFailureReachesTheScreenAsTheGenericMessageAndIsLogged() {
        System.runAs(TestUsers.withPermissionSets(
            new List<String>{ TestUsers.CORE_ADMIN, 'BarnCRM_Erase_People' }
        )) {
            Contact person = jordan();
            PersonErasureExtensions.overrides = new List<PersonErasureExtension>{
                new BrokenExtension()
            };

            Test.startTest();
            for (Boolean erasing : new List<Boolean>{ false, true }) {
                try {
                    if (erasing) {
                        PersonErasureController.erase(person.Id, 'Jordan Lee', 'PR-2');
                    } else {
                        PersonErasureController.preview(person.Id);
                    }
                    Assert.fail('A broken extension stops the action');
                } catch (AuraHandledException failed) {
                    Assert.areEqual(
                        Label.Core_Households_ErrorUnexpected,
                        failed.getMessage(),
                        'The screen is not given a stack trace'
                    );
                }
            }

            Test.stopTest();

            Assert.areEqual(
                2,
                [SELECT COUNT() FROM Error_Log__c WHERE Context__c = 'PersonErasureController'],
                'Each failure is in the Error Log for the administrator'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Erasure__c],
                'And nothing was recorded as erased'
            );
        }
    }

    @IsTest
    static void somethingThatIsNotAPersonIsRefusedInItsOwnWords() {
        System.runAs(TestUsers.withPermissionSets(
            new List<String>{ TestUsers.CORE_ADMIN, 'BarnCRM_Erase_People' }
        )) {
            PersonErasureExtensions.noneForTest = true;
            Contact person = jordan();
            try {
                PersonErasureController.preview(UserInfo.getUserId());
                Assert.fail('A user is not a person to erase');
            } catch (AuraHandledException refused) {
                Assert.areEqual(Label.Core_Erase_NotAPerson, refused.getMessage(), 'Its own words');
            }
        }
    }

    private static Contact jordan() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Contact person = new Contact(FirstName = 'Jordan', LastName = 'Lee');
        insert person;
        return person;
    }

    @IsTest
    static void previewsThenErases() {
        System.runAs(TestUsers.withPermissionSets(
            new List<String>{ TestUsers.CORE_ADMIN, 'BarnCRM_Erase_People' }
        )) {
            PersonErasureExtensions.noneForTest = true;
            Contact person = jordan();

            PersonErasure.Result preview = PersonErasureController.preview(person.Id);
            PersonErasure.Result done = PersonErasureController.erase(
                person.Id,
                'Jordan Lee',
                'PR-1'
            );

            Assert.areEqual(
                'Jordan Lee',
                preview.personName,
                'The preview names the person to type'
            );
            Assert.isFalse(preview.erased, 'The preview erased nothing');
            Assert.isTrue(done.erased, 'Erased');
            Assert.isNotNull(done.erasureId, 'With its audit record');
        }
    }

    @IsTest
    static void aRefusalReachesTheScreenAsItsOwnMessage() {
        System.runAs(TestUsers.admin()) {
            PersonErasureExtensions.noneForTest = true;
            Contact person = jordan();
            try {
                PersonErasureController.erase(person.Id, 'Jordan Lee', null);
                Assert.fail('Refused without the permission');
            } catch (AuraHandledException refused) {
                Assert.areEqual(
                    Label.Core_Erase_NoPermission,
                    refused.getMessage(),
                    'Its own words'
                );
            }
        }
    }
}
