/**
 * The one place that names the custom permission for configuring BarnCRM and checks it.
 *
 * Every settings console page, every module's settings page, and every job an administrator
 * starts asks the same question before it changes anything. Asking it here keeps the name in
 * one place, so a page cannot drift to a different spelling or permission. Each caller still
 * raises its own error, with its own label, when the answer is no.
 */
@NamespaceAccessible
public with sharing class BarnCRMPermissions {
    /** The custom permission that lets a person configure BarnCRM. */
    @NamespaceAccessible
    public static final String MANAGE_SETTINGS = 'Manage_BarnCRM_Settings';

    /** True when the running user may change BarnCRM settings. */
    @NamespaceAccessible
    public static Boolean canManageSettings() {
        return FeatureManagement.checkPermission(MANAGE_SETTINGS);
    }
}
