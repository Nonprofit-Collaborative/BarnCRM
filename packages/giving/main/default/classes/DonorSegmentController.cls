/**
 * What the Donor Segments page reads and does (feature G-28, canonical model Section 25O).
 *
 * Every method requires the Find and Export Records custom permission (R-DS6, R-SQ5): a segment
 * is a Find query, and the export is the sensitive act. Reads and the one write, saving a
 * template as the person's own saved query, run as the person (`DonorSegmentService`). The
 * page's answers are plain JSON shapes; the Find tab name and its page state key carry the
 * package namespace, so they come from here (NamespaceUtil), never from the component.
 */
public with sharing class DonorSegmentController {
    private static final String CONTEXT = 'Donor segments page';
    private static final String FIND_TAB = 'Find';
    private static final String SAVED_QUERY_STATE = 'savedQueryId';

    /** The page: the templates, the segments, and what the export and Find links need. */
    public class PageModel {
        @AuraEnabled
        public List<DonorSegmentTemplates.Template> templates;
        @AuraEnabled
        public List<DonorSegmentService.Segment> segments;
        @AuraEnabled
        public Integer exportLimit;
        @AuraEnabled
        public String findTabApiName;
        @AuraEnabled
        public String stateKey;
        /** The segment a save wrote, so the page opens it; empty otherwise. */
        @AuraEnabled
        public String savedId;
    }

    @AuraEnabled
    public static PageModel getPage() {
        try {
            requirePermission();
            return page();
        } catch (Exception caught) {
            throw asUserError(caught);
        }
    }

    /** Saves a starter template as the person's own segment and returns the page with it open. */
    @AuraEnabled
    public static PageModel saveFromTemplate(String templateKey, String objectName, String name) {
        try {
            requirePermission();
            Id saved = DonorSegmentService.saveFromTemplate(templateKey, objectName, name);
            PageModel model = page();
            model.savedId = saved;
            return model;
        } catch (Exception caught) {
            throw asUserError(caught);
        }
    }

    @AuraEnabled
    public static DonorSegmentService.SegmentCount countSegment(String segmentId) {
        try {
            requirePermission();
            return DonorSegmentService.countRecords(idOf(segmentId));
        } catch (Exception caught) {
            throw asUserError(caught);
        }
    }

    @AuraEnabled
    public static DonorSegmentService.Rows listSegment(String segmentId) {
        try {
            requirePermission();
            return DonorSegmentService.listRows(idOf(segmentId));
        } catch (Exception caught) {
            throw asUserError(caught);
        }
    }

    /** One export page; the page asks again with `lastId` until `done` or the export limit. */
    @AuraEnabled
    public static DonorSegmentService.Rows exportPage(
        String segmentId,
        String layout,
        String afterId
    ) {
        try {
            requirePermission();
            return DonorSegmentService.exportPage(idOf(segmentId), layout, afterId);
        } catch (Exception caught) {
            throw asUserError(caught);
        }
    }

    private static PageModel page() {
        PageModel model = new PageModel();
        model.templates = DonorSegmentTemplates.all();
        model.segments = DonorSegmentService.segments();
        model.exportLimit = FindController.exportLimit();
        model.findTabApiName = NamespaceUtil.qualify(FIND_TAB);
        model.stateKey = NamespaceUtil.stateKey(SAVED_QUERY_STATE);
        return model;
    }

    /** An Id from the page, or null when it is not one (refused as not found). */
    private static Id idOf(String value) {
        try {
            return String.isBlank(value) ? null : Id.valueOf(value);
        } catch (StringException notAnId) {
            return null;
        }
    }

    private static void requirePermission() {
        if (!FeatureManagement.checkPermission(FindController.PERMISSION)) {
            throw new DonorSegmentService.SegmentException(
                System.Label.Giving_Segments_ErrorNoPermission
            );
        }
    }

    /** Anything the person can act on is shown as it is; anything else is logged and summarized. */
    private static AuraHandledException asUserError(Exception caught) {
        String message = caught.getMessage();
        if (
            !(caught instanceof DonorSegmentService.SegmentException) &&
            !(caught instanceof QueryCompiler.QueryCompilerException)
        ) {
            ErrorLogger.log(caught, CONTEXT);
            message = System.Label.Giving_Segments_Unexpected;
        }
        AuraHandledException reported = new AuraHandledException(message);
        reported.setMessage(message);
        return reported;
    }
}
