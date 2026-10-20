/**
 * An extension class that is found by name but throws when built, for Core's tests of how a
 * broken module is handled. Test only.
 */
@IsTest
public class ExtensionFakeUnbuildable implements DataProtectionExtension, HouseholdDependentsExtension {
    public ExtensionFakeUnbuildable() {
        throw new System.TypeException('This extension cannot be built');
    }

    public Set<Schema.SObjectType> protectedObjects() {
        return new Set<Schema.SObjectType>();
    }

    public Set<Id> householdsWithDependents(Set<Id> householdIds) {
        return new Set<Id>();
    }
}
