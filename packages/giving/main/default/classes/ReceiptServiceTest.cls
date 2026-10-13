/**
 * The receipting paths the three named tests do not reach: the letters, the console entry points,
 * and the refusals.
 */
@IsTest
private class ReceiptServiceTest {
    @IsTest
    static void issuingWithoutPermissionIsRefusedWithAMessageThatSaysWhatToAskFor() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            ReceiptTestDataFactory.setUpReceipting();
            ReceiptService.issuePermission = false;
            Contact donor = GivingTestDataFactory.insertHouseholdContact(
                'The Lin Family',
                'Wei',
                'Lin'
            );
            Gift__c gift = ReceiptTestDataFactory.plainCashGift(
                donor.Id,
                75,
                Date.newInstance(2026, 1, 5)
            );
            insert gift;

            Test.startTest();
            try {
                ReceiptService.issueForGift(gift.Id);
                Assert.fail('A user with no permission issued a receipt.');
            } catch (ReceiptService.ReceiptServiceException refused) {
                Assert.areEqual(
                    Label.Giving_Receipt_NoPermission,
                    refused.getMessage(),
                    'It names the role to ask for.'
                );
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void aGiftIsNotReceiptedTwice() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            System.runAs(ReceiptTestDataFactory.issuer()) {
                ReceiptTestDataFactory.setUpReceipting();
                Contact donor = GivingTestDataFactory.insertHouseholdContact(
                    'The Diallo Family',
                    'Awa',
                    'Diallo'
                );
                Gift__c gift = ReceiptTestDataFactory.plainCashGift(
                    donor.Id,
                    90,
                    Date.newInstance(2026, 1, 6)
                );
                insert gift;
                ReceiptService.issueForGift(gift.Id);

                Test.startTest();
                try {
                    ReceiptService.issueForGift(gift.Id);
                    Assert.fail('The same gift was receipted twice.');
                } catch (ReceiptService.ReceiptServiceException refused) {
                    Assert.areEqual(
                        Label.Giving_Receipt_GiftAlreadyReceipted,
                        refused.getMessage(),
                        'It points at void and reissue.'
                    );
                }
                Test.stopTest();
            }

        }
    }

    @IsTest
    static void aVoidWithoutAReasonIsRefused() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            System.runAs(ReceiptTestDataFactory.issuer()) {
                ReceiptTestDataFactory.setUpReceipting();
                Contact donor = GivingTestDataFactory.insertHouseholdContact(
                    'The Ferreira Family',
                    'Luis',
                    'Ferreira'
                );
                Gift__c gift = ReceiptTestDataFactory.plainCashGift(
                    donor.Id,
                    60,
                    Date.newInstance(2026, 1, 7)
                );
                insert gift;
                Receipt__c issued = ReceiptService.issueForGift(gift.Id);

                Test.startTest();
                try {
                    ReceiptService.voidReceipt(issued.Id, '   ');
                    Assert.fail('A receipt was voided with no reason.');
                } catch (ReceiptService.ReceiptServiceException refused) {
                    Assert.areEqual(
                        Label.Giving_Receipt_VoidNeedsReason,
                        refused.getMessage(),
                        'It asks for a reason.'
                    );
                }
                Test.stopTest();
            }

        }
    }

    @IsTest
    static void theShippedLettersAreInstalledOnceAndOnlyOneOfEachKindIsActive() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            ReceiptTemplateService.managePermission = true;
            Integer before = [SELECT COUNT() FROM Receipt_Template__c];

            Test.startTest();
            List<Receipt_Template__c> firstRun = ReceiptTemplateService.restoreDefaults();
            List<Receipt_Template__c> secondRun = ReceiptTemplateService.restoreDefaults();
            Test.stopTest();

            Assert.areEqual(
                0,
                before,
                'This org started with no letters, so the first run creates.'
            );
            Assert.areEqual(
                firstRun.size(),
                [SELECT COUNT() FROM Receipt_Template__c],
                'What the first run says it created is what the org actually has.'
            );
            Assert.isTrue(
                secondRun.isEmpty(),
                'Restoring defaults twice does not duplicate a letter.'
            );
            Map<String, Integer> activeByType = new Map<String, Integer>();
            for (Receipt_Template__c template : ReceiptSelector.allTemplates()) {
                if (template.Active__c) {
                    Integer count = activeByType.containsKey(template.Type__c)
                        ? activeByType.get(template.Type__c)
                        : 0;
                    activeByType.put(template.Type__c, count + 1);
                }
            }
            for (String type : activeByType.keySet()) {
                Assert.areEqual(
                    1,
                    activeByType.get(type),
                    'One letter of each kind is in use: ' + type
                );
            }
        }
    }

    @IsTest
    static void activatingALetterSwitchesOffTheOtherOfItsKind() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            ReceiptTestDataFactory.setUpReceipting();
            Receipt_Template__c second = new Receipt_Template__c(
                Name = 'Per gift receipt, shorter',
                Type__c = ReceiptNumberSequence.TYPE_PER_GIFT,
                Active__c = false,
                Body__c = '<p>{{OrganizationName}} thanks you for {{Amount}}.</p>'
            );
            insert second;

            Test.startTest();
            ReceiptTemplateService.activate(second.Id);
            Test.stopTest();

            Integer active = 0;
            for (Receipt_Template__c template : ReceiptSelector.allTemplates()) {
                if (template.Type__c == ReceiptNumberSequence.TYPE_PER_GIFT && template.Active__c) {
                    active++;
                    Assert.areEqual(
                        second.Id,
                        template.Id,
                        'The one in use is the one just chosen.'
                    );
                }
            }
            Assert.areEqual(1, active, 'Exactly one per gift letter is in use.');
        }
    }

    @IsTest
    static void theGiftPageKnowsWhetherItCanOfferToIssue() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            System.runAs(ReceiptTestDataFactory.issuer()) {
                ReceiptTestDataFactory.setUpReceipting();
                Contact donor = GivingTestDataFactory.insertHouseholdContact(
                    'The Haddad Family',
                    'Nour',
                    'Haddad'
                );
                Gift__c gift = ReceiptTestDataFactory.plainCashGift(
                    donor.Id,
                    300,
                    Date.newInstance(2026, 1, 8)
                );
                insert gift;

                Test.startTest();
                ReceiptController.GiftReceiptState before = ReceiptController.getGiftReceiptState(
                    gift.Id
                );
                ReceiptController.ReceiptView issued = ReceiptController.issue(gift.Id);
                ReceiptController.GiftReceiptState afterwards = ReceiptController.getGiftReceiptState(
                    gift.Id
                );
                Test.stopTest();

                Assert.isFalse(before.alreadyReceipted, 'A new gift has no receipt.');
                Assert.isNotNull(
                    issued.receiptNumber,
                    'Issuing returns the number that was printed.'
                );
                Assert.isTrue(afterwards.alreadyReceipted, 'Afterwards the gift is receipted.');
                Assert.areEqual(
                    1,
                    afterwards.receipts.size(),
                    'The gift lists the document it produced.'
                );
            }

        }
    }
}
