/**
 * The Accounting Export page (feature X-04). Validates nothing itself: the service refuses in
 * words and this class hands those words to the page, or logs anything unexpected and says so.
 */
public with sharing class AccountingExportController {
    private static final String CONTEXT = 'AccountingExportController';
    private static final String EXPORT_PERMISSION = 'Export_Accounting';

    /** One choice in the payment method list. */
    public class Option {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;

        public Option(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    /** The file, its name, and what it holds; csv is empty when the range has no gifts. */
    public class ExportView {
        @AuraEnabled
        public String csv;
        @AuraEnabled
        public String fileName;
        @AuraEnabled
        public Integer rowCount;
        @AuraEnabled
        public Integer giftCount;
        @AuraEnabled
        public Decimal total;
        /** What `markPosted` compares, so it marks exactly the rows downloaded. */
        @AuraEnabled
        public String digest;
    }

    /** The payment methods the page offers, each labelled as the org labels it. */
    @AuraEnabled(cacheable=true)
    public static List<Option> getPaymentMethods() {
        Set<String> allowed = new Set<String>(AccountingExportService.paymentMethods());
        List<Option> options = new List<Option>();
        for (Schema.PicklistEntry entry : Gift__c.Type__c.getDescribe().getPicklistValues()) {
            if (allowed.contains(entry.getValue())) {
                options.add(new Option(entry.getLabel(), entry.getValue()));
            }
        }
        return options;
    }

    @AuraEnabled
    public static ExportView exportGifts(
        Date fromDate,
        Date toDate,
        Id fundId,
        String paymentMethod,
        Boolean onlyUnposted
    ) {
        requireExport();
        try {
            AccountingExportService.ExportFile built = AccountingExportService.build(
                fromDate,
                toDate,
                fundId,
                paymentMethod,
                onlyUnposted
            );
            ExportView view = new ExportView();
            view.csv = built.csv;
            view.rowCount = built.rowCount;
            view.giftCount = built.giftCount;
            view.total = built.total;
            view.digest = built.digest;
            view.fileName =
                'accounting-export-' +
                String.valueOf(fromDate) +
                '-to-' +
                String.valueOf(toDate) +
                '.csv';
            return view;
        } catch (AccountingExportService.ExportException refused) {
            throw asAuraException(refused.getMessage());
        } catch (Exception unexpected) {
            ErrorLogger.log(unexpected, CONTEXT);
            throw asAuraException(Label.Connect_AccountingExport_ErrorFailed);
        }
    }

    /**
     * Marks the gifts in the file just downloaded posted to accounting (G-20). The page sends
     * the same choices and the digest of the file it downloaded; the service builds the file
     * again and marks nothing unless the digest matches.
     */
    @AuraEnabled
    public static Integer markPosted(
        Date fromDate,
        Date toDate,
        Id fundId,
        String paymentMethod,
        Boolean onlyUnposted,
        String digest
    ) {
        requireExport();
        try {
            return AccountingExportService.markPosted(
                fromDate,
                toDate,
                fundId,
                paymentMethod,
                onlyUnposted,
                digest
            );
        } catch (AccountingExportService.ExportException refused) {
            throw asAuraException(refused.getMessage());
        } catch (Exception unexpected) {
            ErrorLogger.log(unexpected, CONTEXT);
            throw asAuraException(Label.Connect_AccountingExport_ErrorFailed);
        }
    }

    /** The export builds a file of every gift the person can see, so it needs its own permission. */
    private static void requireExport() {
        if (!FeatureManagement.checkPermission(EXPORT_PERMISSION)) {
            throw asAuraException(Label.Connect_AccountingExport_NoExportPermission);
        }
    }

    private static AuraHandledException asAuraException(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}
