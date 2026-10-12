/**
 * Which `ReceiptRenderer` this org uses.
 *
 * The setting exists because ADR-0016's first spike is open: nobody has yet confirmed in a real
 * org that `Blob.toPdf()` is not metered as a callout inside a batch. If it is, an org can move to
 * the fallback implementation by changing one value in the BarnCRM Settings console rather than
 * by waiting for a package version. An empty setting, which is the shipped state, means the
 * renderer the package ships.
 *
 * **The setting holds a key, never a class name, and the key set is closed.** ADR-0016 names
 * exactly two implementations, so the choice is a fixed list of two, stored as text and validated
 * in Apex under ADR-0019. The class behind a key is resolved only after the key is recognized, so
 * nothing an administrator types is ever passed to `Type.forName` and nothing an administrator
 * types is ever constructed. That ordering is the point: the earlier version of this class called
 * `newInstance()` on the configured name and checked the interface afterwards, which put an
 * arbitrary no-argument constructor inside every receipt-issuing user's transaction, and, for a
 * class that did implement the interface, handed it the composed HTML of every receipt and
 * statement in the org (donor names, amounts, gift lines, the EIN). The setting object is
 * protected and will be hidden from subscribers once a namespace is registered, but the namespace
 * is deferred and no package version exists, so today it is an ordinary editable setting and the
 * gate has to be here.
 *
 * A value that is not one of the keys is an error with a readable message, not a silent fallback:
 * an administrator who chose a renderer and got the default anyway would have no way to tell.
 */
public with sharing class ReceiptRendererFactory {
    /** The shipped renderer: the Visualforce PDF rendering service through `Blob.toPdf()`. */
    public static final String KEY_BLOB_PDF = 'Blob PDF';

    /** The fallback ADR-0016 names: a Visualforce page rendered as PDF. */
    public static final String KEY_VISUALFORCE = 'Visualforce';

    /**
     * Every renderer this package permits, key to class name. Closed, and checked **before** any
     * class is resolved or constructed. ADR-0016 names two implementations and this is both of
     * them; adding a third is a source change here plus a choice in the setting definition, which
     * is exactly the review this gate exists for. The fallback class is not in the package yet, so
     * choosing it in an org that does not have it is a readable error rather than a silent
     * default.
     */
    private static final Map<String, String> PERMITTED_RENDERERS = new Map<String, String>{
        KEY_BLOB_PDF => 'BlobToPdfReceiptRenderer',
        KEY_VISUALFORCE => 'VisualforceReceiptRenderer'
    };

    /**
     * Set by a test to run the whole feature without producing PDF bytes. Production code never
     * assigns it; ADR-0016 records that PDF bytes cannot be asserted in an Apex test, so the tests
     * assert the composed HTML and the record and file graph instead.
     */
    @TestVisible
    private static ReceiptRenderer overrideRenderer;

    public static ReceiptRenderer get() {
        if (overrideRenderer != null) {
            return overrideRenderer;
        }
        String chosen = keyFrom(Giving_Settings__c.getOrgDefaults().Receipt_Renderer__c);
        if (KEY_BLOB_PDF.equals(chosen)) {
            // The shipped renderer is constructed directly, so the ordinary path never reaches
            // reflection at all.
            return new BlobToPdfReceiptRenderer();
        }
        if (!PERMITTED_RENDERERS.containsKey(chosen)) {
            throw refusal(Label.Giving_Receipt_UnknownRenderer, chosen);
        }
        return resolve(chosen);
    }

    /**
     * The key a configured value names: the shipped renderer when nothing is set, and otherwise
     * the value without the whitespace around it, which is an administrator typing rather than a
     * different choice.
     */
    @TestVisible
    private static String keyFrom(String configured) {
        return String.isBlank(configured) ? KEY_BLOB_PDF : configured.trim();
    }

    /**
     * The class behind a key that has already been allowed. Only a class name this package owns
     * reaches `Type.forName`, and nothing is constructed before the key was recognized.
     */
    private static ReceiptRenderer resolve(String chosen) {
        Type rendererType = Type.forName(PERMITTED_RENDERERS.get(chosen));
        if (rendererType == null) {
            throw refusal(Label.Giving_Receipt_RendererUnavailable, chosen);
        }
        Object instance = rendererType.newInstance();
        if (!(instance instanceof ReceiptRenderer)) {
            // Unreachable while the map holds only renderers, and kept so that a future entry
            // that is not one fails here rather than at the call site.
            throw refusal(Label.Giving_Receipt_RendererUnavailable, chosen);
        }
        return (ReceiptRenderer) instance;
    }

    /** A refusal that names the value, so an administrator can see what to clear. */
    private static ReceiptRendererFactoryException refusal(String message, String chosen) {
        return new ReceiptRendererFactoryException(
            String.format(message, new List<String>{ chosen })
        );
    }

    /** The keys an administrator may choose, for the setting definition and for a test. */
    @TestVisible
    private static Set<String> permittedKeys() {
        return PERMITTED_RENDERERS.keySet().clone();
    }

    public class ReceiptRendererFactoryException extends Exception {
    }
}
