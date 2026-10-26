/**
 * Tests for OtherRollupTools: DLRS and Rollup Helper are reported when their namespaces are
 * installed and nothing is said when they are not (canonical model R-R16).
 */
@IsTest(testFor='ApexClass:OtherRollupTools')
private class OtherRollupToolsTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    @IsTest
    static void theRealOrgIsDetectedWithoutFailing() {
        System.runAs(TestUsers.admin()) {
            List<String> notices = OtherRollupTools.notices();

            Assert.areEqual(
                (OtherRollupTools.hasDlrs() ? 1 : 0) + (OtherRollupTools.hasRollupHelper() ? 1 : 0),
                notices.size(),
                'One notice per tool the describe found.'
            );
        }
    }

    @IsTest
    static void neitherToolMeansNoNotice() {
        System.runAs(TestUsers.admin()) {
            OtherRollupTools.overrideForTest(new Set<String>());

            Assert.isFalse(OtherRollupTools.hasDlrs(), 'No DLRS.');
            Assert.isFalse(OtherRollupTools.hasRollupHelper(), 'No Rollup Helper.');
            Assert.isTrue(OtherRollupTools.notices().isEmpty(), 'Nothing is said.');
        }
    }

    @IsTest
    static void bothToolsAreNamedDlrsFirst() {
        System.runAs(TestUsers.admin()) {
            OtherRollupTools.overrideForTest(
                new Set<String>{
                    OtherRollupTools.ROLLUP_HELPER_NAMESPACE,
                    OtherRollupTools.DLRS_NAMESPACE
                }
            );

            List<String> notices = OtherRollupTools.notices();

            Assert.areEqual(
                new List<String>{
                    System.Label.Core_OtherRollupTools_Dlrs,
                    System.Label.Core_OtherRollupTools_RollupHelper
                },
                notices,
                'DLRS, then Rollup Helper.'
            );
        }
    }

    @IsTest
    static void theNamespacesAreTheManagedOnes() {
        // runs-as: deploying user (pure logic: compares two constants, no DML or SOQL)
        Assert.areEqual('dlrs', OtherRollupTools.DLRS_NAMESPACE, 'DLRS is dlrs.');
        Assert.areEqual('rh2', OtherRollupTools.ROLLUP_HELPER_NAMESPACE, 'Rollup Helper is rh2.');
    }
}
