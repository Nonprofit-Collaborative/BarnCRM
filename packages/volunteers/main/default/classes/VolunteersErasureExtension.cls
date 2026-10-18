/**
 * What erasing a person does to the Volunteers module's own records (canonical model R-ER8,
 * R-VQ4; ADR-0110 `0110-erase-a-person-anonymizes-in-place.md`). Core finds this class by name
 * in `PersonErasureExtensions.EXTENSION_CLASSES` and calls it inside the erasure's own
 * transaction, so a refusal here takes the whole erasure back.
 *
 * The person's onboarding requirements are deleted, because the result of a background check
 * lives nowhere else and must leave with the person. Core empties them from the Recycle Bin
 * once the erasure commits and the Erasure record lists them by Id only. The records are read
 * in system mode, so a requirement is found whoever may see it, and deleted as the user (R-ER5):
 * a person erasing without access to requirements is refused rather than leaving them behind.
 * No volunteer attribute on the person is kept: they are anonymized with the rest.
 *
 * `@NamespaceAccessible`, public, with a public no-argument constructor, because Core resolves
 * it with `Type.forName` under ADR-0017.
 */
@NamespaceAccessible
public with sharing class VolunteersErasureExtension implements PersonErasureExtension {
    @NamespaceAccessible
    public VolunteersErasureExtension() {
        return;
    }

    public Set<Schema.SObjectField> fieldsToKeep(Schema.SObjectType personType) {
        return new Set<Schema.SObjectField>();
    }

    public List<PersonErasure.Change> erase(Id personId) {
        Boolean isContact = personId.getSObjectType() == Contact.SObjectType;
        Set<Id> contacts = isContact ? new Set<Id>{ personId } : new Set<Id>();
        Set<Id> accounts = isContact ? new Set<Id>() : new Set<Id>{ personId };
        List<Volunteer_Requirement__c> requirements = [
            SELECT Id
            FROM Volunteer_Requirement__c
            WHERE Contact__c IN :contacts OR Account__c IN :accounts
            WITH SYSTEM_MODE
            LIMIT 10000
        ];
        if (requirements.isEmpty()) {
            return new List<PersonErasure.Change>();
        }
        Database.delete(requirements, true, AccessLevel.USER_MODE);
        return new List<PersonErasure.Change>{
            new PersonErasure.Change(
                PersonErasure.DELETED,
                Volunteer_Requirement__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                    .getLabelPlural(),
                new List<Id>(new Map<Id, Volunteer_Requirement__c>(requirements).keySet()),
                null
            )
        };
    }
}
