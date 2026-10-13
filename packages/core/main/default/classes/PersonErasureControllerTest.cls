/**
 * The Erase person action's controller: a refusal reaches the screen as its own message, and a
 * preview and an erasure pass straight through to `PersonErasure`.
 */
@IsTest
private class PersonErasureControllerTest {
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
