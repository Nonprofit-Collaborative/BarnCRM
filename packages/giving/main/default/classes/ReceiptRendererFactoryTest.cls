/**
 * Which renderer an org gets, and which ones it cannot get (ADR-0016).
 *
 * The setting that chooses a renderer is an ordinary editable custom setting until a namespace is
 * registered, so these tests are about a gate, not about a preference: a value that is not one of
 * the two keys ADR-0016 names must be refused **before** any class is resolved or constructed.
 */
@IsTest(testFor='ApexClass:ReceiptRendererFactory')
private class ReceiptRendererFactoryTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Giving_Admin');
    }

    private static final String PROBE_CLASS = 'ReceiptTestDataFactory.ConstructionProbe';

    /** The setting as an org default, written the way the settings console writes it. */
    private static void chooseRenderer(String value) {
        Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
        settings.SetupOwnerId = UserInfo.getOrganizationId();
        settings.Receipt_Renderer__c = value;
        upsert settings;
    }

    /** The stored value, read back rather than assumed, since that is what the factory reads. */
    private static String storedRenderer() {
        return [
            SELECT Receipt_Renderer__c
            FROM Giving_Settings__c
            WHERE SetupOwnerId = :UserInfo.getOrganizationId()
            WITH SYSTEM_MODE
            LIMIT 1
        ]
        .Receipt_Renderer__c;
    }

    /**
     * The shipped state. An empty setting means the renderer the package ships, and nothing about
     * that path touches reflection.
     */
    @IsTest
    static void anEmptySettingGivesTheShippedRenderer() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            chooseRenderer(null);
            Assert.isNull(storedRenderer(), 'The shipped state is an empty setting.');

            Test.startTest();
            ReceiptRenderer renderer = ReceiptRendererFactory.get();
            Test.stopTest();

            Assert.isInstanceOfType(
                renderer,
                BlobToPdfReceiptRenderer.class,
                'An org that has chosen nothing gets the Blob.toPdf renderer the package ships.'
            );
        }
    }

    /** The same renderer, chosen by name rather than by leaving the setting alone. */
    @IsTest
    static void theShippedKeyGivesTheShippedRenderer() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            chooseRenderer(ReceiptRendererFactory.KEY_BLOB_PDF);
            Assert.areEqual(
                'Blob PDF',
                storedRenderer(),
                'The setting holds the key an administrator picked, not a class name.'
            );

            Test.startTest();
            ReceiptRenderer renderer = ReceiptRendererFactory.get();
            Test.stopTest();

            Assert.isInstanceOfType(
                renderer,
                BlobToPdfReceiptRenderer.class,
                'The Blob PDF key names the shipped renderer.'
            );
        }
    }

    /**
     * Surrounding whitespace is an administrator typing, not a different choice.
     *
     * The platform trims a text field when it is saved, so a stored setting never carries the
     * spaces into the factory. The factory's own trimming is proved on the value it is handed,
     * and the stored path is proved end to end.
     */
    @IsTest
    static void aKeyIsTrimmedBeforeItIsMatched() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Assert.areEqual(
                ReceiptRendererFactory.KEY_BLOB_PDF,
                ReceiptRendererFactory.keyFrom('  Blob PDF  '),
                'The factory trims the value it reads, whatever stored it.'
            );
            chooseRenderer('  Blob PDF  ');
            Assert.areEqual(
                'Blob PDF',
                storedRenderer(),
                'What an administrator typed with spaces around it is stored as the key.'
            );

            Test.startTest();
            ReceiptRenderer renderer = ReceiptRendererFactory.get();
            Test.stopTest();

            Assert.isInstanceOfType(
                renderer,
                BlobToPdfReceiptRenderer.class,
                'A key with spaces around it is still the shipped renderer.'
            );
        }
    }

    /**
     * The finding this class exists for. A class that is a real `ReceiptRenderer`, and that the
     * platform in this very transaction is willing to construct, is still refused, and **its
     * constructor never runs**. Before the allow-list, that constructor ran inside the transaction
     * of whoever was issuing a receipt, and the object it produced was handed the composed HTML of
     * every receipt and statement in the org.
     */
    @IsTest
    static void aRendererOutsideTheAllowListIsRefusedWithoutBeingConstructed() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Type probeType = Type.forName(PROBE_CLASS);
            Assert.isNotNull(
                probeType,
                'The probe class resolves here, so a refusal below is the allow-list and not a name ' +
                'the platform could not find.'
            );
            Object built = probeType.newInstance();
            Assert.areEqual(
                1,
                ReceiptTestDataFactory.probeConstructions,
                'Constructing the probe directly increments its counter, which is how the counter ' +
                'proves anything.'
            );
            Assert.isTrue(
                built instanceof ReceiptRenderer,
                'The probe implements the interface, so an instanceof check after construction would ' +
                'have accepted it.'
            );

            ReceiptTestDataFactory.probeConstructions = 0;
            chooseRenderer(PROBE_CLASS);
            Assert.areEqual(
                PROBE_CLASS,
                storedRenderer(),
                'A class name reached the setting, which is exactly what an editable setting allows.'
            );

            Test.startTest();
            try {
                ReceiptRendererFactory.get();
                Assert.fail('A class name outside the allow-list produced a renderer.');
            } catch (ReceiptRendererFactory.ReceiptRendererFactoryException refused) {
                Assert.areEqual(
                    String.format(
                        Label.Giving_Receipt_UnknownRenderer,
                        new List<String>{ PROBE_CLASS }
                    ),
                    refused.getMessage(),
                    'The message names the value and says to clear the setting.'
                );
            }
            Test.stopTest();

            Assert.areEqual(
                0,
                ReceiptTestDataFactory.probeConstructions,
                'The refused class was never constructed: the key was checked before newInstance.'
            );
        }
    }

    /** A value that is nobody's class and nobody's key is the same refusal. */
    @IsTest
    static void aValueThatIsNeitherAKeyNorAClassIsRefused() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            chooseRenderer('Whatever Maria typed');

            Test.startTest();
            try {
                ReceiptRendererFactory.get();
                Assert.fail('An unrecognized value produced a renderer.');
            } catch (ReceiptRendererFactory.ReceiptRendererFactoryException refused) {
                Assert.areEqual(
                    String.format(
                        Label.Giving_Receipt_UnknownRenderer,
                        new List<String>{ 'Whatever Maria typed' }
                    ),
                    refused.getMessage(),
                    'A typo is refused with the value in the message rather than falling back ' +
                    'silently to the shipped renderer.'
                );
            }
            Test.stopTest();
        }
    }

    /**
     * The fallback key is permitted and its class is not in the package yet, so choosing it today
     * fails with "not available in this org" rather than with "not one we offer". When the
     * fallback ships, the first assertion here fails and this test is the reminder to extend it.
     */
    @IsTest
    static void theFallbackKeyIsPermittedAndSaysSoWhenItsClassIsNotInstalled() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Assert.isTrue(
                ReceiptRendererFactory.permittedKeys()
                    .contains(ReceiptRendererFactory.KEY_VISUALFORCE),
                'ADR-0016 names the Visualforce fallback, so its key is on the allow-list.'
            );
            Assert.isNull(
                Type.forName('VisualforceReceiptRenderer'),
                'The fallback class has not shipped yet. When it does, extend this test to assert ' +
                'that the key returns it.'
            );

            chooseRenderer(ReceiptRendererFactory.KEY_VISUALFORCE);

            Test.startTest();
            try {
                ReceiptRendererFactory.get();
                Assert.fail('A key with no class behind it produced a renderer.');
            } catch (ReceiptRendererFactory.ReceiptRendererFactoryException refused) {
                Assert.areEqual(
                    String.format(
                        Label.Giving_Receipt_RendererUnavailable,
                        new List<String>{ ReceiptRendererFactory.KEY_VISUALFORCE }
                    ),
                    refused.getMessage(),
                    'An allowed key whose class is missing is a different message from a key that ' +
                    'was never allowed, because the two need different answers.'
                );
            }
            Test.stopTest();
        }
    }

    /** Only the two keys ADR-0016 names, and no third. */
    @IsTest
    static void theAllowListIsTheTwoImplementationsTheAdrNames() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Set<String> keys = ReceiptRendererFactory.permittedKeys();

            Assert.areEqual(
                new Set<String>{
                    ReceiptRendererFactory.KEY_BLOB_PDF,
                    ReceiptRendererFactory.KEY_VISUALFORCE
                },
                keys,
                'The list is closed: adding to it is a source change and a review, not a setting.'
            );
        }
    }
}
