/**
 * RC-01 (D-224): an organization in Canada issues no receipt while Receipt place of issue is
 * blank, as Canada Revenue Agency requires the place of issue; elsewhere a blank is allowed, and
 * the EIN stays optional everywhere.
 */
@IsTest(testFor='ApexClass:ReceiptContentBuilder')
private class ReceiptPlaceOfIssueTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static void organizationWithoutPlaceOrEin() {
		ReceiptTestDataFactory.useOrganization();
		ReceiptTestDataFactory.useReceiptSettings();
		ModuleSettings.setForTest('Giving_Receipt_Place_Of_Issue', '');
		ModuleSettings.setForTest('Giving_Organization_EIN', '');
	}

	@IsTest
	static void aCanadianOrganizationNeedsThePlaceOfIssue() {
		System.runAs(TestUsers.admin()) {
			organizationWithoutPlaceOrEin();
			ReceiptContentBuilder.canadianForTest = true;
			try {
				ReceiptContentBuilder.organizationDetails();
				Assert.fail('A Canadian receipt without a place of issue is refused');
			} catch (ReceiptContentBuilder.ReceiptContentException expected) {
				Assert.areEqual(
					BarnHelp.text('Giving', 'Giving_Receipt_PlaceOfIssueRequired'),
					expected.getMessage(),
					'The message says what to fill in'
				);
			}

			ModuleSettings.setForTest('Giving_Receipt_Place_Of_Issue', 'Toronto, ON');
			Assert.areEqual(
				'Toronto, ON',
				ReceiptContentBuilder.organizationDetails().placeOfIssue,
				'Filled in, the receipt is issued'
			);
		}
	}

	@IsTest
	static void elsewhereABlankPlaceAndEinAreAllowed() {
		System.runAs(TestUsers.admin()) {
			organizationWithoutPlaceOrEin();
			ReceiptContentBuilder.canadianForTest = false;
			ReceiptContentBuilder.OrganizationDetails details = ReceiptContentBuilder.organizationDetails();
			Assert.isTrue(String.isBlank(details.placeOfIssue), 'No place of issue');
			Assert.isTrue(String.isBlank(details.taxId), 'No EIN: US law does not require it');
		}
	}

	@IsTest
	static void theCountryIsReadFromCompanyInformation() {
		System.runAs(TestUsers.admin()) {
			String country = [SELECT Country FROM Organization WITH SYSTEM_MODE LIMIT 1].Country;
			Boolean expected =
				country != null && new Set<String>{ 'canada', 'ca' }.contains(country.trim().toLowerCase());
			Assert.areEqual(expected, ReceiptContentBuilder.issuesCanadianReceipts(), 'Read once');
			Assert.areEqual(expected, ReceiptContentBuilder.issuesCanadianReceipts(), 'And again from the cache');
		}
	}
}
