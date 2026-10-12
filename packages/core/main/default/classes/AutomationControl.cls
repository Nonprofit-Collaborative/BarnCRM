/**
 * The on and off switches behind the Automation page of the Nonprofit Settings console.
 *
 * Three separate mechanisms, in the order the dispatcher applies them:
 *
 *   1. a per transaction bypass, for tests and for internal bulk operations that deliberately
 *      run without a handler;
 *   2. the org wide pause, held as a datetime on Nonprofit Settings, so it expires by itself,
 *      with a one-time `AutomationResumeJob` that records the end (R-A5, ADR-0055);
 *   3. the per automation switch, held as a row per automation on Automation Setting.
 *
 * An automation whose shipped registry row carries `Always_Runs__c` is none of these three
 * things: it enforces a rule rather than providing a convenience, so the dispatcher does not
 * ask about it and `setEnabled` refuses to change it (ADR-0024). Its row is still materialized,
 * so the console can list it and say why its switch will not move.
 *
 * An automation with no row yet still runs. That matters on upgrade: a newly shipped automation
 * works from the moment it is installed, and `ensureDefaults` materializes its row without ever
 * touching a row the administrator already has (Decision D-06, rule R-A2).
 */
@NamespaceAccessible
public with sharing class AutomationControl {
    public static final String PAUSE_SETTING_NAME = 'Automation Paused Until';
    // Bare, and correctly so: a custom permission defined in the same package resolves without a
    // namespace prefix, so this is not the B5 problem that TriggerHandler.getName had.
    public static final String MANAGE_SETTINGS_PERMISSION = 'Manage_Nonprofit_Settings';

    private static final Set<Integer> ALLOWED_PAUSE_HOURS = new Set<Integer>{ 1, 2, 4, 8, 24 };

    /** The longest pause the page offers. A pause ending later than this is not one it set. */
    @NamespaceAccessible
    public static final Integer LONGEST_PAUSE_HOURS = 24;

    private static final String RESUME_SCHEDULE_CONTEXT = 'Automation pause: scheduling the automatic resume';
    private static final Set<String> BYPASSED_NAMES = new Set<String>();

    private static Map<String, Boolean> enabledByName;

    @NamespaceAccessible
    public class AutomationControlException extends Exception {
    }

    @NamespaceAccessible
    public static Set<Integer> allowedPauseHours() {
        return ALLOWED_PAUSE_HOURS.clone();
    }

    // ------------------------------------------------------------------ per automation switch

    @NamespaceAccessible
    public static Boolean isEnabled(String automationName) {
        if (String.isBlank(automationName)) {
            return false;
        }
        if (enabledByName == null) {
            loadEnabledCache();
        }
        Boolean enabled = enabledByName.get(automationName.toLowerCase());
        return enabled == null ? true : enabled;
    }

    /**
     * Switches one automation on or off and records the change. Saving the value it already has
     * writes nothing (rule R-S1).
     */
    @NamespaceAccessible
    public static void setEnabled(String automationName, Boolean enabled) {
        if (String.isBlank(automationName)) {
            throw new AutomationControlException(Label.Core_Automation_NameRequired);
        }
        requirePermission();
        List<Automation_Setting__c> matches = AutomationSettingSelector.selectByNames(
            new Set<String>{ automationName }
        );
        if (matches.isEmpty()) {
            throw new AutomationControlException(Label.Core_Automation_NotFound);
        }
        Boolean target = enabled == true;
        Automation_Setting__c setting = matches[0];
        // An automation that enforces a rule is not a switch (ADR-0024). Refusing here rather
        // than only in the component is what makes it true of the API as well as of the page.
        if (setting.Always_Runs__c == true) {
            throw new AutomationControlException(Label.Core_Automation_AlwaysRuns);
        }
        Boolean previous = setting.Enabled__c;
        if (previous == target) {
            return;
        }
        // Only the switch is sent. The record read above also carries Always_Runs__c, which
        // no packaged permission set may edit, and a user mode update of a record carrying a
        // field the user cannot edit is refused even when its value has not changed.
        Database.update(
            new Automation_Setting__c(Id = setting.Id, Enabled__c = target),
            AccessLevel.USER_MODE
        );
        clearCache();
        SettingsService.logChange(
            'Automation: ' + setting.Automation_Name__c,
            String.valueOf(previous),
            String.valueOf(target)
        );
    }

    @NamespaceAccessible
    public static void clearCache() {
        enabledByName = null;
    }

    // -------------------------------------------------------------------------- global pause

    @NamespaceAccessible
    public static Boolean isPaused() {
        return pausedUntil() != null;
    }

    /**
     * When the current pause ends, or null when automation is running.
     */
    @NamespaceAccessible
    public static Datetime pausedUntil() {
        Nonprofit_Settings__c settings = SettingsService.getSettings();
        if (settings == null || settings.Automation_Paused_Until__c == null) {
            return null;
        }
        return settings.Automation_Paused_Until__c > System.now()
            ? settings.Automation_Paused_Until__c
            : null;
    }

    /**
     * The permission that governs every write on this page. Checked here rather than only in the
     * controller, because the pause is written in system mode (`AutomationSettingsWriter` says
     * why) and this is the check that stands in for the platform's.
     */
    @NamespaceAccessible
    public static Boolean canManage() {
        return FeatureManagement.checkPermission(MANAGE_SETTINGS_PERMISSION);
    }

    /** Test seam: makes scheduling the resume fail, as it does when the org has 100 jobs. */
    @TestVisible
    private static Boolean schedulingFailsForTest = false;

    private static void requirePermission() {
        if (!canManage()) {
            throw new AutomationControlException(Label.Core_Automation_NoPermission);
        }
    }

    /**
     * Pauses everything for the given number of hours and schedules the job that records the
     * end. A job that cannot be scheduled (the org already has 100) does not stop the pause:
     * automation still resumes on time, the failure goes to the Error Log, and Health Check
     * reports a pause with no automatic resume.
     */
    @NamespaceAccessible
    public static Datetime pauseAll(Integer hours) {
        if (hours == null || !ALLOWED_PAUSE_HOURS.contains(hours)) {
            throw new AutomationControlException(Label.Core_Automation_PauseHoursInvalid);
        }
        Datetime until = writePausedUntil(System.now().addHours(hours));
        try {
            if (schedulingFailsForTest) {
                throw new AutomationControlException('Scheduling refused for this test.');
            }
            AutomationResumeJob.scheduleAt(until);
        } catch (Exception failed) {
            ErrorLogger.log(failed, RESUME_SCHEDULE_CONTEXT);
        }
        return until;
    }

    /**
     * Resumes now and cancels the scheduled resume. A resume job left behind would find no
     * pause and change nothing, so failing to cancel it is logged rather than refused.
     */
    @NamespaceAccessible
    public static void resumeAll() {
        writePausedUntil(null);
        try {
            AutomationResumeJob.cancel();
        } catch (Exception failed) {
            ErrorLogger.log(failed, RESUME_SCHEDULE_CONTEXT);
        }
    }

    /**
     * Clears a pause whose end has passed and records the resume, as the Resume button would.
     * Called by `AutomationResumeJob`, which runs as the administrator who paused; the
     * permission was checked when the pause was set, and this can only do what the clock has
     * already done, so it is not checked again. A pause still running, or none, is left alone.
     *
     * @return true when a pause was cleared
     */
    @NamespaceAccessible
    public static Boolean resumeExpiredPause() {
        return resumeExpiredPause(null);
    }

    /**
     * The same, for the pause ending at `expectedEnd` only. The stored end is read under a lock
     * on the settings record, so a pause saved a moment ago is either seen (and left alone,
     * because its end differs) or waits until this has finished. A null `expectedEnd` clears
     * whatever expired pause is stored.
     */
    @NamespaceAccessible
    public static Boolean resumeExpiredPause(Datetime expectedEnd) {
        Datetime stored = OrgSettingsSystemWriter.lockStored()?.Automation_Paused_Until__c;
        if (stored == null || stored > System.now()) {
            return false;
        }
        if (expectedEnd != null && !sameSecond(stored, expectedEnd)) {
            return false;
        }
        AutomationSettingsWriter.savePausedUntil(null);
        SettingsService.clearCache();
        SettingsService.logChange(PAUSE_SETTING_NAME, String.valueOf(stored), '');
        return true;
    }

    private static Boolean sameSecond(Datetime first, Datetime second) {
        return first.getTime() / 1000 == second.getTime() / 1000;
    }

    /**
     * The name of the person who started the pause in effect, read from the Setting Change the
     * pause wrote, or null when automation is running or the pause was not set from the page.
     */
    @NamespaceAccessible
    public static String pausedBy() {
        if (!isPaused()) {
            return null;
        }
        Setting_Change__c latest = SettingChangeSelector.latestFor(PAUSE_SETTING_NAME);
        if (latest == null || String.isBlank(latest.New_Value__c)) {
            return null;
        }
        return latest.Changed_By__r?.Name;
    }

    /**
     * True when a pause is in effect that nothing will end on time: no resume job is scheduled,
     * or its end is further ahead than the longest pause the page offers. Such a pause was set
     * before automatic resume existed or somewhere other than the Automation page (R-A5).
     */
    @NamespaceAccessible
    public static Boolean isPauseWithoutResume() {
        Datetime until = pausedUntil();
        if (until == null) {
            return false;
        }
        return until > System.now().addHours(LONGEST_PAUSE_HOURS) ||
            AutomationResumeJob.scheduledAt() == null;
    }

    private static Datetime writePausedUntil(Datetime until) {
        requirePermission();
        // Read under the lock the save below also takes, so the audit row's old value is the
        // one stored, not one another person replaced a moment ago.
        Datetime previous = OrgSettingsSystemWriter.lockStored()?.Automation_Paused_Until__c;
        AutomationSettingsWriter.savePausedUntil(until);
        SettingsService.clearCache();
        SettingsService.logChange(
            PAUSE_SETTING_NAME,
            previous == null ? '' : String.valueOf(previous),
            until == null ? '' : String.valueOf(until)
        );
        return until;
    }

    // -------------------------------------------------------------------- per transaction bypass

    @NamespaceAccessible
    public static void bypass(String automationName) {
        if (String.isNotBlank(automationName)) {
            BYPASSED_NAMES.add(automationName.toLowerCase());
        }
    }

    @NamespaceAccessible
    public static void clearBypass(String automationName) {
        if (String.isNotBlank(automationName)) {
            BYPASSED_NAMES.remove(automationName.toLowerCase());
        }
    }

    @NamespaceAccessible
    public static void clearAllBypasses() {
        BYPASSED_NAMES.clear();
    }

    @NamespaceAccessible
    public static Boolean isBypassed(String automationName) {
        return String.isNotBlank(automationName) &&
            BYPASSED_NAMES.contains(automationName.toLowerCase());
    }

    // ------------------------------------------------------------------------ materialization

    /**
     * Creates an Automation Setting row for every shipped automation that does not have one yet,
     * and leaves every existing row exactly as the administrator left it. Safe to call on every
     * install, every upgrade, and twice in a row. Returns how many rows it created.
     *
     * Called by each package's post-install script (through `ensureDefaultsDuringInstall`), so
     * the Automation page lists every switch from the first install, and by the Health Check fix
     * (C-21), which enforces Manage Nonprofit Settings before it gets here.
     */
    @NamespaceAccessible
    public static Integer ensureDefaults() {
        List<Automation_Setting__c> toCreate = missingDefaults();
        if (toCreate.isEmpty()) {
            return 0;
        }
        // Written through AutomationSettingsWriter in system mode (ADR-0021): every row carries
        // Always_Runs__c, which no packaged permission set may edit, so a user mode insert is
        // refused for everyone, and in a post-install script nobody holds a permission set at
        // all. Nothing here comes from user input: every value is copied from the package's own
        // shipped registry.
        AutomationSettingsWriter.insertSwitches(toCreate);
        clearCache();
        return toCreate.size();
    }

    /**
     * The same thing, called from a post-install script, where nothing may throw. An install
     * must not fail because a switch row could not be created: an automation with no row still
     * runs, and Health Check names the missing switches and restores them. So a failure is
     * written to the Error Log and the caller is told nothing was created.
     *
     * @param context the calling script, so the Error Log entry names it
     * @return how many rows were created, and zero when the step failed
     */
    @NamespaceAccessible
    public static Integer ensureDefaultsDuringInstall(String context) {
        try {
            return ensureDefaults();
        } catch (Exception failed) {
            ErrorLogger.log(
                failed,
                String.isBlank(context) ? 'AutomationControl.ensureDefaults' : context
            );
            return 0;
        }
    }

    /**
     * The names of the shipped automations that have no switch row yet, without creating them,
     * so Health Check can say what restoring them would add (C-21, ADR-0048).
     */
    @NamespaceAccessible
    public static List<String> missingDefaultNames() {
        List<String> names = new List<String>();
        for (Automation_Setting__c setting : missingDefaults()) {
            names.add(setting.Name);
        }
        return names;
    }

    /** The switch rows ensureDefaults would create: one per shipped automation not yet here. */
    private static List<Automation_Setting__c> missingDefaults() {
        List<Automation_Setting__c> toCreate = new List<Automation_Setting__c>();
        List<Automation_Registry__mdt> registry = shippedRegistry();
        if (registry.isEmpty()) {
            return toCreate;
        }
        Set<String> existingNames = new Set<String>();
        for (Automation_Setting__c setting : AutomationSettingSelector.selectAllForFramework()) {
            if (String.isNotBlank(setting.Automation_Name__c)) {
                existingNames.add(setting.Automation_Name__c.toLowerCase());
            }
        }
        for (Automation_Registry__mdt entry : registry) {
            if (
                String.isBlank(entry.DeveloperName) ||
                existingNames.contains(entry.DeveloperName.toLowerCase())
            ) {
                continue;
            }
            existingNames.add(entry.DeveloperName.toLowerCase());
            toCreate.add(
                new Automation_Setting__c(
                    Name = String.isBlank(entry.MasterLabel)
                        ? entry.DeveloperName
                        : entry.MasterLabel,
                    Automation_Name__c = entry.DeveloperName,
                    Description__c = entry.Description__c,
                    Enabled__c = entry.Enabled_By_Default__c == true,
                    Always_Runs__c = entry.Always_Runs__c == true,
                    Handler_Class__c = entry.Handler_Class__c,
                    Object_Name__c = entry.Object_Name__c,
                    Execution_Order__c = entry.Execution_Order__c,
                    Is_Package_Default__c = true
                )
            );
        }
        return toCreate;
    }

    private static List<Automation_Registry__mdt> shippedRegistry() {
        return AutomationRegistrySelector.selectAll();
    }

    private static void loadEnabledCache() {
        enabledByName = new Map<String, Boolean>();
        for (Automation_Setting__c setting : AutomationSettingSelector.selectAllForFramework()) {
            if (String.isNotBlank(setting.Automation_Name__c)) {
                enabledByName.put(setting.Automation_Name__c.toLowerCase(), setting.Enabled__c);
            }
        }
    }
}
