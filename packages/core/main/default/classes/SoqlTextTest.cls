/**
 * The LIKE escaping every search box shares.
 */
@IsTest(testFor='ApexClass:SoqlText')
private class SoqlTextTest {
	@IsTest
	static void backslashPercentAndUnderscoreMatchThemselves() {
		// runs-as: deploying user (pure logic: escapes a string, no DML or SOQL)
		Assert.areEqual('a\\_b\\%c\\\\d', SoqlText.escapeLike('a_b%c\\d'), 'Each is escaped');
		Assert.areEqual('O\'Brien', SoqlText.escapeLike('O\'Brien'), 'Quotes are left alone');
	}
}
