/**
 * A stand-in for a module's extension class, found by name the way Core finds a module's: it
 * protects the relationship object and credits no household. Registered in the extension
 * class lists by Core's tests, which have no module to resolve. Test only.
 */
@IsTest
public class ExtensionFakeWorks implements DataProtectionExtension, HouseholdDependentsExtension {
    public Set<Schema.SObjectType> protectedObjects() {
        return new Set<Schema.SObjectType>{ Relationship__c.SObjectType };
    }

    public Set<Id> householdsWithDependents(Set<Id> householdIds) {
        return null;
    }
}
