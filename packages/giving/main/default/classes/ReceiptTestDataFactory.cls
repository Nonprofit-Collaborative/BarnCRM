/**
 * Test data for the receipting feature.
 *
 * It also holds the fake renderer. ADR-0016 records that PDF bytes cannot be asserted in an Apex
 * test, so the tests assert the composed HTML and the record and file graph, and the fake keeps the
 * HTML where a test can read it instead of turning it into bytes nobody can inspect.
 */
@IsTest
public class ReceiptTestDataFactory {
    /**
     * How many times `ConstructionProbe` has been constructed in this transaction. A test resets
     * it and then reads it to tell "the factory refused the name" from "the factory built the
     * class and then refused it", which is the whole difference the renderer allow-list makes.
     */
    public static Integer probeConstructions = 0;

    /** The renderer a test uses: it keeps what it was asked to render, and returns something. */
    public class RecordingRenderer implements ReceiptRenderer {
        public List<String> renderedHtml = new List<String>();

        public Blob render(String html) {
            renderedHtml.add(html);
            return Blob.valueOf(html);
        }

        public String describe() {
            return 'Recording renderer (test)';
        }

        /** The last document composed, which is what a content assertion reads. */
        public String lastHtml() {
            return renderedHtml.isEmpty() ? '' : renderedHtml[renderedHtml.size() - 1];
        }
    }

    /** A renderer that fails, so a test can watch what a failed generation leaves behind. */
    public class FailingRenderer implements ReceiptRenderer {
        public Blob render(String html) {
            throw new RendererFailureException('The PDF service was unavailable.');
        }

        public String describe() {
            return 'Failing renderer (test)';
        }
    }

    public class RendererFailureException extends Exception {
    }

    /**
     * A renderer that records the fact of its own construction. It genuinely implements
     * `ReceiptRenderer`, so an interface check after the fact would accept it: the only thing that
     * stops it being constructed inside somebody else's transaction is that its class name is not
     * on `ReceiptRendererFactory`'s allow-list.
     */
    public class ConstructionProbe implements ReceiptRenderer {
        public ConstructionProbe() {
            ReceiptTestDataFactory.probeConstructions++;
        }

        public Blob render(String html) {
            return Blob.valueOf(html);
        }

        public String describe() {
            return 'Construction probe (test)';
        }
    }

    /**
     * The person a test that stores a file runs as: an administrator created for that test alone.
     *
     * Not the running user, because the running user is shared. Every file a user saves goes into
     * that user's private library, and test classes run in parallel as the same person, each in a
     * transaction that rolls back. When one of those transactions rolls back while another is
     * saving a file into the same library, the second save is refused with
     * `INVALID_CROSS_REFERENCE_KEY, invalid cross reference id: []`, naming no field. Measured on
     * the test org with eight transactions saving and rolling back at once: about one save in 160
     * refused as the shared user, and none in twelve rounds from a user created for the test. A
     * person created for one test has a library nobody else writes to.
     *
     * The running user's profile and the same two roles `run-org-tests.sh` gives the running
     * user, so a test has exactly the access it had before.
     */
    public static User issuer() {
        return TestDataFactory.createUserOnTheRunningUsersProfile(
            'Issuer',
            new List<String>{ 'Nonprofit_Admin', 'Giving_Admin' }
        );
    }

    /**
     * Everything a receipt needs before it can be issued: an organization to issue it, a numbering
     * prefix, a letter of each kind, permission to issue and to manage the letters, a renderer
     * that does not need a PDF engine, and a default fund so the gifts being receipted can be
     * saved at all. Returns the renderer so a test can read what was composed.
     */
    public static RecordingRenderer setUpReceipting() {
        GivingTestDataFactory.ensureDefaultFund();

        Nonprofit_Settings__c core = Nonprofit_Settings__c.getOrgDefaults();
        core.SetupOwnerId = UserInfo.getOrganizationId();
        core.Organization_Legal_Name__c = 'Hope For Homes';
        core.Organization_Address__c = '14 Bridge Street, Springfield';
        upsert core;

        Giving_Settings__c giving = Giving_Settings__c.getOrgDefaults();
        giving.SetupOwnerId = UserInfo.getOrganizationId();
        giving.Receipt_Number_Prefix__c = 'HFH';
        giving.Receipt_Next_Counter__c = 1;
        giving.Receipt_Place_Of_Issue__c = 'Springfield';
        giving.Organization_EIN__c = '12-3456789';
        giving.Receipt_Signer_Name__c = 'Tom Alvarez';
        giving.Receipt_Signer_Title__c = 'Executive Director';
        upsert giving;

        insert new List<Receipt_Template__c>{
            new Receipt_Template__c(
                Name = 'Per gift receipt',
                Type__c = ReceiptNumberSequence.TYPE_PER_GIFT,
                Active__c = true,
                Body__c = perGiftTemplateBody()
            ),
            new Receipt_Template__c(
                Name = 'Consolidated statement',
                Type__c = ReceiptNumberSequence.TYPE_STATEMENT,
                Active__c = true,
                Body__c = statementTemplateBody()
            )
        };

        ReceiptService.issuePermission = true;
        // Maria configures Open Impact, so the tests that edit a letter run as somebody who may.
        // A custom permission cannot be granted to the user a test runs as without assigning a
        // permission set, which would make every receipting test a test of that assignment.
        ReceiptTemplateService.managePermission = true;
        RecordingRenderer renderer = new RecordingRenderer();
        ReceiptRendererFactory.overrideRenderer = renderer;
        return renderer;
    }

    public static String perGiftTemplateBody() {
        return '<p>{{OrganizationName}}</p><p>Receipt {{ReceiptNumber}}</p>' +
            '<p>Dear {{DonorName}}, thank you for your gift of {{Amount}} received on {{GiftDate}}.</p>';
    }

    public static String statementTemplateBody() {
        return '<p>{{OrganizationName}}</p><p>Statement {{ReceiptNumber}} for {{StatementYear}}</p>' +
            '<p>Dear {{DonorName}}, your giving totalled {{Amount}}.</p>{{GiftLines}}';
    }

    /** A cash gift with nothing given in return, which is the ordinary case. */
    public static Gift__c plainCashGift(Id donorContactId, Decimal amount, Date giftDate) {
        Gift__c gift = GivingTestDataFactory.buildGift(donorContactId, amount);
        gift.Type__c = 'Cash';
        gift.Gift_Date__c = giftDate;
        return gift;
    }

    /** A gift where the donor received something, so the receipt owes a disclosure. */
    public static Gift__c quidProQuoGift(
        Id donorContactId,
        Decimal amount,
        Decimal benefitValue,
        String benefitDescription,
        Date giftDate
    ) {
        Gift__c gift = plainCashGift(donorContactId, amount, giftDate);
        gift.Benefit_Description__c = benefitDescription;
        gift.Benefit_Value__c = benefitValue;
        return gift;
    }

    /**
     * A gift of goods, whose receipt describes and never values them. Its amount is zero, which
     * is what R-G12 requires of a real one, and what it was worth is on Fair Market Value.
     */
    public static Gift__c inKindGift(Id donorContactId, String description, Date giftDate) {
        return inKindGift(donorContactId, description, 900, giftDate);
    }

    /**
     * The same gift with the fair market value named, so a test can assert that its own figure
     * reaches no rendered document (R-RC12).
     */
    public static Gift__c inKindGift(
        Id donorContactId,
        String description,
        Decimal value,
        Date giftDate
    ) {
        Gift__c gift = GivingTestDataFactory.buildGift(donorContactId, 0);
        gift.Type__c = 'In-kind';
        gift.Gift_Date__c = giftDate;
        gift.In_Kind_Description__c = description;
        gift.Fair_Market_Value__c = value;
        return gift;
    }
}
