/**
 * Tests for NamespaceUtil (feature C-07 and C-11, used by every packaged component that has
 * to name a tab, page, or page state parameter).
 *
 * The namespace is deferred, so the tests assert the shape of the answer rather than a
 * literal prefix: they have to keep passing on the day the namespace is registered.
 */
// runs-as: deploying user (pure logic: reads a class name, no DML or SOQL)
@IsTest(testFor='ApexClass:NamespaceUtil')
private class NamespaceUtilTest {
    @IsTest
    static void prefixIsEmptyOrEndsInADoubleUnderscore() {
        NamespaceUtil.cachedPrefix = null;

        String prefix = NamespaceUtil.prefix();

        System.assertNotEquals(null, prefix, 'There is always an answer, even if it is empty.');
        System.assert(
            String.isBlank(prefix) || prefix.endsWith('__'),
            'A prefix is either absent or ready to be put in front of a name: ' + prefix
        );
    }

    @IsTest
    static void qualifyPutsThePrefixInFront() {
        NamespaceUtil.cachedPrefix = 'example__';

        System.assertEquals(
            'example__BarnCRM_Settings',
            NamespaceUtil.qualify('BarnCRM_Settings'),
            'A packaged tab carries the package prefix.'
        );
    }

    @IsTest
    static void qualifyLeavesNamesAloneWithoutANamespace() {
        NamespaceUtil.cachedPrefix = '';

        System.assertEquals(
            'BarnCRM_Settings',
            NamespaceUtil.qualify('BarnCRM_Settings'),
            'With no namespace registered the name stands on its own.'
        );
        System.assertEquals(null, NamespaceUtil.qualify(null), 'Nothing qualifies to nothing.');
    }

    @IsTest
    static void stateKeysUseTheDefaultPrefixWhenThereIsNoNamespace() {
        NamespaceUtil.cachedPrefix = '';

        System.assertEquals(
            'c__section',
            NamespaceUtil.stateKey('section'),
            'Lightning namespaces page state, and an unmanaged package uses c__.'
        );
    }

    @IsTest
    static void stateKeysUseThePackagePrefixWhenThereIsOne() {
        NamespaceUtil.cachedPrefix = 'example__';

        System.assertEquals(
            'example__section',
            NamespaceUtil.stateKey('section'),
            'A managed package uses its own prefix on page state.'
        );
        System.assertEquals(null, NamespaceUtil.stateKey(null), 'Nothing keys to nothing.');
    }

    /** This package's prefix and another package's, kept apart from the names they go on. */
    private static final String OWN = 'barn__';
    private static final String OTHER = 'npsp__';

    /** A describe map standing in for an org, keyed the way the resolver looks names up. */
    private static void stubDescribe(String prefix, Map<String, Schema.SObjectType> objects) {
        NamespaceUtil.cachedPrefix = prefix;
        NamespaceUtil.describeOverride = objects;
        NamespaceUtil.typesByName.clear();
    }

    @IsTest
    static void objectTypePrefersThisPackagesObjectOverEveryOther() {
        stubDescribe(
            OWN,
            new Map<String, Schema.SObjectType>{
                OTHER + 'address__c' => Contact.SObjectType,
                'address__c' => User.SObjectType,
                OWN + 'address__c' => Account.SObjectType
            }
        );

        Assert.areEqual(
            Account.SObjectType,
            NamespaceUtil.objectType('Address__c'),
            'The package\'s own object wins over the subscriber\'s and NPSP\'s'
        );
        Assert.areEqual(
            Account.SObjectType,
            NamespaceUtil.objectType(' ADDRESS__C '),
            'Capitals and spacing do not matter'
        );
    }

    @IsTest
    static void objectTypeNeverPicksAnotherPackagesObject() {
        stubDescribe(
            OWN,
            new Map<String, Schema.SObjectType>{ OTHER + 'address__c' => Contact.SObjectType }
        );
        Assert.isNull(
            NamespaceUtil.objectType('Address__c'),
            'Under a namespace, NPSP\'s Address__c is not BarnCRM\'s'
        );

        stubDescribe(
            '',
            new Map<String, Schema.SObjectType>{ OTHER + 'address__c' => Contact.SObjectType }
        );
        Assert.isNull(
            NamespaceUtil.objectType('Address__c'),
            'Without a namespace, NPSP\'s Address__c is not BarnCRM\'s either'
        );
    }

    @IsTest
    static void objectTypeFallsBackToTheNameAsWritten() {
        stubDescribe(
            OWN,
            new Map<String, Schema.SObjectType>{
                'account' => Account.SObjectType,
                OTHER + 'thing__c' => Contact.SObjectType
            }
        );

        Assert.areEqual(
            Account.SObjectType,
            NamespaceUtil.objectType('Account'),
            'A standard object resolves by its own name'
        );
        Assert.areEqual(
            Contact.SObjectType,
            NamespaceUtil.objectType(OTHER + 'Thing__c'),
            'A name that already carries a prefix resolves as written'
        );
        Assert.isNull(NamespaceUtil.objectType(' '), 'A blank name resolves to nothing');
        Assert.isNull(NamespaceUtil.objectType('Missing__c'), 'An absent object stays null');
    }

    @IsTest
    static void packagedObjectTypeIgnoresTheSubscribersAndOtherPackagesObjects() {
        stubDescribe(
            OWN,
            new Map<String, Schema.SObjectType>{
                'fund__c' => Account.SObjectType,
                OTHER + 'fund__c' => Contact.SObjectType
            }
        );
        Assert.isNull(
            NamespaceUtil.packagedObjectType('Fund__c'),
            'Neither the subscriber\'s Fund__c nor another package\'s is BarnCRM\'s'
        );

        NamespaceUtil.describeOverride.put(OWN + 'fund__c', User.SObjectType);
        Assert.areEqual(
            User.SObjectType,
            NamespaceUtil.packagedObjectType('Fund__c'),
            'The package\'s own object is found by its prefixed name'
        );
        Assert.isNull(NamespaceUtil.packagedObjectType(null), 'Nothing resolves to nothing');
    }

    @IsTest
    static void objectTypeFindsARealObjectWithoutAStub() {
        NamespaceUtil.cachedPrefix = null;
        NamespaceUtil.typesByName.clear();

        Assert.areEqual(
            Account.SObjectType,
            NamespaceUtil.objectType('Account'),
            'The org\'s own describe answers when no stub is set'
        );
    }
}
