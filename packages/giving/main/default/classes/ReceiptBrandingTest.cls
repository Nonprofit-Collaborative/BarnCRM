/**
 * What a document is branded with, and what it is valid without (R-RC13).
 *
 * Two things are asserted here. The organization's name and address reach the document even when
 * the template does not ask for them, because an administrator who deleted the letterhead out of
 * their letter has not thereby issued a receipt with no organization on it. And the logo is
 * optional at every step: off, missing, or unresolvable all produce a document rather than an
 * error.
 *
 * **These tests have not been executed.** No Salesforce org was reachable while this feature was
 * built, so no Apex in this repository has been run. The logo tests are additionally the part of
 * ADR-0016's second spike that an Apex test cannot settle: they assert the markup this package
 * composes, not that the PDF rendering service fetches the image. Only a real org can say that.
 */
@IsTest
private class ReceiptBrandingTest {
    private static final Date GIFT_DATE = Date.newInstance(2026, 4, 12);

    /** A template that says nothing about the organization, which is the case the block exists for. */
    private static final String BARE_TEMPLATE = '<p>Dear {{DonorName}}, thank you for your gift of {{Amount}} received on {{GiftDate}}.</p>';

    @TestSetup
    static void setUp() {
        ReceiptTestDataFactory.setUpReceipting();
    }

    private static String receiptFrom(String templateBody) {
        Gift__c gift = ReceiptTestDataFactory.plainCashGift(null, 250, GIFT_DATE);
        return ReceiptContentBuilder.forGift(
            gift,
            'Sam Whitfield',
            'HFH-2026-000010',
            Date.newInstance(2027, 1, 15),
            templateBody
        );
    }

    private static Id insertLogoFile() {
        ContentVersion version = new ContentVersion(
            Title = 'Receipt logo',
            PathOnClient = 'logo.png',
            VersionData = Blob.valueOf('not really a png, and no test can say whether one renders')
        );
        insert version;
        Id documentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id]
        .ContentDocumentId;
        Giving_Settings__c giving = Giving_Settings__c.getOrgDefaults();
        giving.SetupOwnerId = UserInfo.getOrganizationId();
        giving.Receipt_Logo_Document_Id__c = documentId;
        upsert giving;
        ReceiptLogoSource.reset();
        return documentId;
    }

    private static void setLogoDelivery(String route, Boolean printLogo) {
        Giving_Settings__c giving = Giving_Settings__c.getOrgDefaults();
        giving.SetupOwnerId = UserInfo.getOrganizationId();
        giving.Receipt_Logo_Delivery__c = route;
        giving.Receipt_Print_Logo__c = printLogo;
        upsert giving;
        ReceiptLogoSource.reset();
    }

    @IsTest
    static void aTemplateThatNamesNoOrganizationStillProducesADocumentThatDoes() {
        Test.startTest();
        String html = receiptFrom(BARE_TEMPLATE);
        Test.stopTest();

        Assert.isTrue(
            html.contains('<p class="orgname">Hope For Homes</p>'),
            'The legal name is printed above the letter: ' + html
        );
        Assert.isTrue(html.contains('14 Bridge Street, Springfield'), 'So is the address: ' + html);
        Assert.isTrue(
            html.contains('12-3456789'),
            'The tax identification number is on it, as it always was: ' + html
        );
    }

    @IsTest
    static void aTemplateThatNamesTheOrganizationIsNotGivenASecondCopyOfIt() {
        Test.startTest();
        String html = receiptFrom(ReceiptTestDataFactory.perGiftTemplateBody());
        Test.stopTest();

        Assert.isFalse(
            html.contains('class="orgname"'),
            'The package does not print a name the letter already printed: ' + html
        );
        Assert.isTrue(html.contains('Hope For Homes'), 'The letter still prints it: ' + html);
    }

    @IsTest
    static void anOrganizationWithNoLogoGetsADocumentWithNoImage() {
        Test.startTest();
        String html = receiptFrom(BARE_TEMPLATE);
        Test.stopTest();

        Assert.isFalse(html.contains('<img'), 'No logo uploaded means no image: ' + html);
    }

    @IsTest
    static void theShippedRouteAddressesTheFileByItsDownloadUrl() {
        System.runAs(ReceiptTestDataFactory.issuer()) {
            insertLogoFile();
            setLogoDelivery(null, true);

            Test.startTest();
            String html = receiptFrom(BARE_TEMPLATE);
            Test.stopTest();

            Assert.isTrue(
                html.contains('/sfc/servlet.shepherd/version/download/'),
                'The shipped route is the file download URL (ADR-0016): ' + html
            );
            Assert.isTrue(html.contains('width: 40mm'), 'The shipped width is used: ' + html);
        }
    }

    @IsTest
    static void theEmbeddedRouteInlinesTheBytes() {
        System.runAs(ReceiptTestDataFactory.issuer()) {
            insertLogoFile();
            setLogoDelivery(ReceiptLogoSource.ROUTE_EMBEDDED_IMAGE, true);

            Test.startTest();
            String html = receiptFrom(BARE_TEMPLATE);
            Test.stopTest();

            Assert.isTrue(
                html.contains('data:image/png;base64,'),
                'The second route ADR-0016 names inlines the image: ' + html
            );
        }
    }

    @IsTest
    static void theDocumentServerRouteAddressesTheImageServer() {
        System.runAs(ReceiptTestDataFactory.issuer()) {
            insertLogoFile();
            setLogoDelivery(ReceiptLogoSource.ROUTE_DOCUMENT_SERVER, true);

            Test.startTest();
            String html = receiptFrom(BARE_TEMPLATE);
            Test.stopTest();

            Assert.isTrue(
                html.contains('servlet.ImageServer'),
                'The third route ADR-0016 names is the image server: ' + html
            );
        }
    }

    @IsTest
    static void turningTheLogoOffProducesADocumentWithoutIt() {
        System.runAs(ReceiptTestDataFactory.issuer()) {
            insertLogoFile();
            setLogoDelivery(null, false);

            Test.startTest();
            String html = receiptFrom(BARE_TEMPLATE);
            Test.stopTest();

            Assert.isFalse(html.contains('<img'), 'Off means off: ' + html);
            Assert.isTrue(
                html.contains('Hope For Homes'),
                'A receipt with no images is still a receipt: ' + html
            );
        }
    }

    /**
     * A logo that cannot be found is a log entry, never a failed document. This is the case an
     * organization will actually hit if the file is not shared with the person issuing receipts.
     */
    @IsTest
    static void aLogoThatCannotBeFoundStillProducesADocument() {
        Giving_Settings__c giving = Giving_Settings__c.getOrgDefaults();
        giving.SetupOwnerId = UserInfo.getOrganizationId();
        giving.Receipt_Logo_Document_Id__c = '069000000000000AAA';
        upsert giving;
        ReceiptLogoSource.reset();

        Test.startTest();
        String html = receiptFrom(BARE_TEMPLATE);
        Test.stopTest();

        Assert.isFalse(html.contains('<img'), 'Nothing is printed for a file that is not there.');
        Assert.isTrue(html.contains('Hope For Homes'), 'The document is produced anyway: ' + html);
    }
}
