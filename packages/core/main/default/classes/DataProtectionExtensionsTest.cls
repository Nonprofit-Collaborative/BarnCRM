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

    /**
     * Registers Core's own fake classes by name, as a module registers its class, so the lookup
     * runs without any module installed. (A class nested in a test class cannot be found by
     * name, so the fakes are top level: ExtensionFakeWorks and its siblings.)
     */
    @IsTest
    static void aRegisteredClassIsFoundByNameAndAsked() {
        DataProtectionExtensions.EXTENSION_CLASSES.clear();
        DataProtectionExtensions.EXTENSION_CLASSES.add('ExtensionFakeWorks');

        Assert.areEqual(
            new Set<Schema.SObjectType>{ Relationship__c.SObjectType },
            DataProtectionExtensions.protectedObjects(),
            'The extension found by name answers'
        );
    }

    @IsTest
    static void aRegisteredClassThatIsNotAnExtensionOrCannotBeBuiltIsLoggedAndLeftOut() {
        DataProtectionExtensions.EXTENSION_CLASSES.clear();
        DataProtectionExtensions.EXTENSION_CLASSES.add('ExtensionFakeNotAnExtension');
        DataProtectionExtensions.EXTENSION_CLASSES.add('ExtensionFakeUnbuildable');
        DataProtectionExtensions.EXTENSION_CLASSES.add('ExtensionFakeWorks');
        DataProtectionExtensions.EXTENSION_CLASSES.add('NoSuchClassAnywhere');

        Set<Schema.SObjectType> objects = DataProtectionExtensions.protectedObjects();

        Assert.areEqual(
            new Set<Schema.SObjectType>{ Relationship__c.SObjectType },
            objects,
            'Only the working extension counts, and the broken ones do not stop it'
        );
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
