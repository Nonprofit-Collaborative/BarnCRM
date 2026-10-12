/**
 * Who receives the error digest (C-23, R-E5, ADR-0055): active users of this org only.
 *
 * The recipients setting lists email addresses, because that is what an administrator knows,
 * but every address has to belong to an active internal user, and the digest is addressed to
 * that user record rather than to the address. That keeps the org's failures inside the org and
 * keeps the digest out of the daily limit on email sent to addresses. An empty setting means
 * everyone holding Manage BarnCRM Settings.
 */
public with sharing class ErrorDigestRecipients {
    /** The most people one digest goes to. */
    @TestVisible
    private static final Integer MAX_RECIPIENTS = 50;

    /**
     * The cap in force. A test lowers it instead of creating fifty-one users, which the org's
     * user licences would refuse.
     */
    @TestVisible
    private static Integer recipientCap = MAX_RECIPIENTS;

    private static final String MANAGE_SETTINGS = 'Manage_Nonprofit_Settings';

    /**
     * The users the digest goes to: those whose addresses are listed, in the order listed, or,
     * when none is, every active user holding Manage BarnCRM Settings. At most MAX_RECIPIENTS (50).
     */
    public static List<User> resolve(String configured) {
        if (String.isBlank(configured)) {
            return ErrorDigestSelector.activeUsers(
                CustomPermissionSelector.holderIds(MANAGE_SETTINGS),
                recipientCap
            );
        }
        List<String> listed = addresses(configured);
        Map<String, User> byAddress = ErrorDigestSelector.activeUsersByEmail(
            new Set<String>(listed)
        );
        List<User> found = new List<User>();
        for (String address : listed) {
            User person = byAddress.get(address);
            if (person != null && found.size() < recipientCap) {
                found.add(person);
            }
        }
        return found;
    }

    /**
     * Why a recipients value cannot be saved, naming the addresses that are not active users of
     * this org, or null when every one is. Empty is allowed: it means the administrators.
     * `SettingsService` asks this before it saves the setting.
     */
    public static String refusal(String configured) {
        if (String.isBlank(configured)) {
            return null;
        }
        List<String> listed = addresses(configured);
        Map<String, User> byAddress = ErrorDigestSelector.activeUsersByEmail(
            new Set<String>(listed)
        );
        List<String> unknown = new List<String>();
        for (String address : listed) {
            if (!byAddress.containsKey(address)) {
                unknown.add(address);
            }
        }
        if (unknown.isEmpty()) {
            return null;
        }
        return String.format(
            System.Label.Core_ErrorDigest_UnknownRecipients,
            new List<Object>{ String.join(unknown, ', ') }
        );
    }

    /** The addresses in a comma, semicolon or space separated list, in lower case, in order. */
    private static List<String> addresses(String configured) {
        List<String> found = new List<String>();
        for (String part : configured.split('[,;\\s]+')) {
            String address = part.trim().toLowerCase();
            if (String.isNotBlank(address) && !found.contains(address)) {
                found.add(address);
            }
        }
        return found;
    }
}
