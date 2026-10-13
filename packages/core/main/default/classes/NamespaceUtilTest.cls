/**
 * Tests for NamespaceUtil (feature C-07 and C-11, used by every packaged component that has
 * to name a tab, page, or page state parameter).
 *
 * The namespace is deferred, so the tests assert the shape of the answer rather than a
 * literal prefix: they have to keep passing on the day the namespace is registered.
 */
// runs-as: deploying user (pure logic: reads a class name, no DML or SOQL)
@IsTest
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
}
