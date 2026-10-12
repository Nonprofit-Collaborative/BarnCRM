/**
 * The organization's logo, as an `img` element the receipt renderer can use (R-RC13, ADR-0016).
 *
 * **This is ADR-0016's second spike, and the spike is open.** Nobody has confirmed in a real org
 * how an image reaches the Visualforce PDF rendering service, and it cannot be confirmed without
 * one. ADR-0016 names three routes to try, in order, and all three are implemented here behind one
 * setting so that settling the question in an org is a settings change rather than a package
 * version:
 *
 * 1. `File download`, the shipped route: the file's download URL on this org.
 * 2. `Embedded image`: the bytes as a base64 `data:` URI. ADR-0016 records that the renderer is
 *    not expected to accept these, which is why it is second rather than first.
 * 3. `Document server`: a classic Document marked externally available, addressed through the
 *    image server. On this route the setting in the Organization section holds a Document
 *    identifier rather than a file identifier, and no file lookup happens.
 *
 * **A receipt with no logo is a valid receipt**, which decides how every failure here behaves:
 * nothing throws, nothing fails a document, and a logo that cannot be found is one Error Log
 * warning per transaction rather than one per receipt in a year end run.
 *
 * The file lookup runs in user mode, deliberately. The logo is not a number a document would be
 * wrong without, so ADR-0021's argument for reading package owned data in system mode does not
 * apply: if the running user cannot see the file, the honest outcome is a document without a logo
 * and a log entry saying to share the file, not an elevated read.
 */
public with sharing class ReceiptLogoSource {
    public static final String ROUTE_FILE_DOWNLOAD = 'File download';
    public static final String ROUTE_EMBEDDED_IMAGE = 'Embedded image';
    public static final String ROUTE_DOCUMENT_SERVER = 'Document server';

    private static final String SETTINGS_OBJECT = 'Giving_Settings__c';
    private static final String KEY_LOGO_DOCUMENT = 'Receipt_Logo_Document_Id__c';
    private static final String KEY_PRINT_LOGO = 'Receipt_Print_Logo__c';
    private static final String KEY_WIDTH = 'Receipt_Logo_Width_Mm__c';
    private static final String KEY_DELIVERY = 'Receipt_Logo_Delivery__c';

    private static final Integer DEFAULT_WIDTH_MM = 40;
    private static final Integer MAX_WIDTH_MM = 170;
    private static final String CONTEXT = 'ReceiptLogoSource';

    /** File extension to media type, for the embedded image route only. */
    private static final Map<String, String> MEDIA_TYPES = new Map<String, String>{
        'png' => 'image/png',
        'jpg' => 'image/jpeg',
        'jpeg' => 'image/jpeg',
        'gif' => 'image/gif'
    };

    /**
     * One resolved source per file for the life of the transaction. A year end chunk composes 25
     * documents from the same logo and must not query for it 25 times. A key present with a null
     * value is a file that could not be resolved, so a failure is not retried either.
     */
    @TestVisible
    private static Map<String, String> resolvedSources = new Map<String, String>();

    /** Whether this transaction has already logged that the logo could not be printed. */
    @TestVisible
    private static Boolean alreadyWarned = false;

    /**
     * The `img` element for the top of a document, or an empty string when there is nothing to
     * print: no logo uploaded, the setting turned off, or a file that could not be resolved.
     */
    public static String imageTag() {
        if (!printLogo()) {
            return '';
        }
        String documentId = trimmed(SettingsService.getValue(SETTINGS_OBJECT, KEY_LOGO_DOCUMENT));
        if (String.isBlank(documentId)) {
            return '';
        }
        String source = sourceFor(documentId, route());
        if (String.isBlank(source)) {
            return '';
        }
        return '<img class="logo" src="' +
            source.escapeHtml4() +
            '" style="width: ' +
            widthMm() +
            'mm;" alt=""/>';
    }

    /** Forgets what this transaction resolved. For tests, and for a batch that reuses a context. */
    @TestVisible
    private static void reset() {
        resolvedSources = new Map<String, String>();
        alreadyWarned = false;
    }

    // ----------------------------------------------------------------------- the three routes

    private static String sourceFor(String documentId, String selectedRoute) {
        if (resolvedSources.containsKey(documentId)) {
            return resolvedSources.get(documentId);
        }
        String source = null;
        try {
            if (ROUTE_DOCUMENT_SERVER.equalsIgnoreCase(selectedRoute)) {
                source =
                    '/servlet/servlet.ImageServer?id=' +
                    documentId +
                    '&oid=' +
                    UserInfo.getOrganizationId();
            } else {
                Boolean embedded = ROUTE_EMBEDDED_IMAGE.equalsIgnoreCase(selectedRoute);
                ContentVersion version = latestVersionOf(documentId, embedded);
                if (version == null) {
                    warnOnce(
                        'The receipt logo file ' +
                            documentId +
                            ' could not be read, so documents are being produced without a logo. ' +
                            'Check that the file still exists and that the people who issue ' +
                            'receipts can see it.'
                    );
                } else if (embedded) {
                    source = embeddedImage(version);
                } else {
                    source = '/sfc/servlet.shepherd/version/download/' + version.Id;
                }
            }
        } catch (Exception failure) {
            ErrorLogger.log(failure, CONTEXT);
        }
        resolvedSources.put(documentId, source);
        return source;
    }

    private static ContentVersion latestVersionOf(String documentId, Boolean withBytes) {
        List<ContentVersion> versions;
        if (withBytes) {
            versions = [
                SELECT Id, FileExtension, VersionData
                FROM ContentVersion
                WHERE ContentDocumentId = :documentId AND IsLatest = TRUE
                WITH USER_MODE
                LIMIT 1
            ];
        } else {
            versions = [
                SELECT Id, FileExtension
                FROM ContentVersion
                WHERE ContentDocumentId = :documentId AND IsLatest = TRUE
                WITH USER_MODE
                LIMIT 1
            ];
        }
        return versions.isEmpty() ? null : versions[0];
    }

    private static String embeddedImage(ContentVersion version) {
        String extension = version.FileExtension == null ? '' : version.FileExtension.toLowerCase();
        String mediaType = MEDIA_TYPES.containsKey(extension)
            ? MEDIA_TYPES.get(extension)
            : MEDIA_TYPES.get('png');
        if (version.VersionData == null) {
            return null;
        }
        return 'data:' + mediaType + ';base64,' + EncodingUtil.base64Encode(version.VersionData);
    }

    // -------------------------------------------------------------------------- the settings

    /**
     * Whether the logo prints. Absent means yes: an organization that uploaded a logo in the Setup
     * Assistant expects to see it, and the setting exists to turn that off rather than on.
     */
    private static Boolean printLogo() {
        Object stored = SettingsService.getValue(SETTINGS_OBJECT, KEY_PRINT_LOGO);
        if (stored == null) {
            return true;
        }
        if (stored instanceof Boolean) {
            return (Boolean) stored;
        }
        return Boolean.valueOf(String.valueOf(stored));
    }

    private static String route() {
        String stored = trimmed(SettingsService.getValue(SETTINGS_OBJECT, KEY_DELIVERY));
        return String.isBlank(stored) ? ROUTE_FILE_DOWNLOAD : stored;
    }

    /**
     * The printed width. A width nobody set, or one that would run off the page, falls back to the
     * shipped one rather than producing a document an administrator cannot use.
     */
    private static Integer widthMm() {
        Object stored = SettingsService.getValue(SETTINGS_OBJECT, KEY_WIDTH);
        if (!(stored instanceof Decimal)) {
            return DEFAULT_WIDTH_MM;
        }
        Integer width = ((Decimal) stored).intValue();
        return (width <= 0 || width > MAX_WIDTH_MM) ? DEFAULT_WIDTH_MM : width;
    }

    private static String trimmed(Object stored) {
        return stored == null ? null : String.valueOf(stored).trim();
    }

    private static void warnOnce(String message) {
        if (alreadyWarned) {
            return;
        }
        alreadyWarned = true;
        ErrorLogger.logMessage(message, CONTEXT, ErrorLogger.SEVERITY_WARNING);
    }
}
