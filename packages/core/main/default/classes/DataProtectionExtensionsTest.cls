/**
 * A module's protected objects reach Core's protected list through the extension seam, and a
 * broken extension is left out without stopping anything (canonical model R-IT14).
 */
// runs-as: deploying user (pure logic: resolves extension classes by name and reads describe, no DML or SOQL)
@IsTest(testFor='ApexClass:DataProtectionExtensions')
private class DataProtectionExtensionsTest {
    private class ProtectsRelationships implements DataProtectionExtension {
        public Set<Schema.SObjectType> protectedObjects() {
            return new Set<Schema.SObjectType>{ Relationship__c.SObjectType };
        }
    }

    private class Throws implements DataProtectionExtension {
        public Set<Schema.SObjectType> protectedObjects() {
            throw new System.TypeException('broken');
        }
    }

    private class ReturnsNull implements DataProtectionExtension {
        public Set<Schema.SObjectType> protectedObjects() {
            return null;
        }
    }

    @IsTest
    static void anObjectAnExtensionProtectsIsRefusedLikeCoresOwnBookkeeping() {
        DataProtectionExtensions.noneForTest = true;
        Assert.isNull(
            DataProtectedFields.objectRefusal(Relationship__c.SObjectType),
            'Without the extension a relationship may be loaded.'
        );

        DataProtectionExtensions.overrides.add(new ProtectsRelationships());
        DataProtectionExtensions.reset();

        Assert.areEqual(
            String.format(
                Label.Core_Data_ObjectBookkeeping,
                new List<String>{
                    Relationship__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                        .getLabelPlural()
                }
            ),
            DataProtectedFields.objectRefusal(Relationship__c.SObjectType),
            'With it, the object is refused.'
        );
    }

    @IsTest
    static void anExtensionThatThrowsOrAnswersNothingIsLeftOutAndTheOthersStillCount() {
        DataProtectionExtensions.noneForTest = true;
        DataProtectionExtensions.overrides.add(new Throws());
        DataProtectionExtensions.overrides.add(new ReturnsNull());
        DataProtectionExtensions.overrides.add(new ProtectsRelationships());

        Set<Schema.SObjectType> objects = DataProtectionExtensions.protectedObjects();

        Assert.areEqual(
            new Set<Schema.SObjectType>{ Relationship__c.SObjectType },
            objects,
            'Only what a working extension named.'
        );
    }

    @IsTest
    static void noExtensionMeansNothingMoreIsProtected() {
        DataProtectionExtensions.noneForTest = true;

        Assert.isTrue(DataProtectionExtensions.protectedObjects().isEmpty(), 'Nothing gathered.');
        Assert.isNull(DataProtectedFields.objectRefusal(Contact.SObjectType), 'People load.');
    }

    @IsTest
    static void anInstalledModuleIsFoundByNameOrAbsent() {
        // Core alone has no module to find; with Giving installed its extension answers.
        Set<Schema.SObjectType> objects = DataProtectionExtensions.protectedObjects();

        Assert.isNotNull(objects, 'Never null, with or without a module.');
        Assert.isFalse(objects.contains(null), 'Never holds a blank.');
    }
}
