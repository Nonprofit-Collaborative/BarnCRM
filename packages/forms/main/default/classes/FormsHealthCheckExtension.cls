/**
 * Public forms' checks in Health Check, in the Settings console (C-42b; ADR-NEXT public forms on
 * a Salesforce Site, decision 9; ADR-0057's extension seam, ADR-0125's fixes). Core finds this
 * class by name (`HealthCheckExtensions.EXTENSION_CLASSES`).
 *
 * Asked only while a public form is published, of a viewer who may manage settings:
 * - no active Salesforce Site to serve it (the Setup step Salesforce forces);
 * - a Site guest user without `Forms_Public_Guest` (fix: assign it);
 * - a Site guest user that can read people or organizations (never changed automatically);
 * - processing not scheduled (fix: schedule it as the viewer);
 * - received submissions waiting over an hour.
 *
 * `@NamespaceAccessible`, public, with a public no-argument constructor, because Core resolves it
 * with `Type.forName` under ADR-0017.
 */
@NamespaceAccessible
public with sharing class FormsHealthCheckExtension implements HealthCheckExtension, HealthCheckFixExtension {
	@TestVisible
	private static final String FIX_GUEST = 'forms_public_guest_access';
	@TestVisible
	private static final String FIX_SCHEDULE = 'forms_public_processing';
	public static final String GUEST_PERMISSION_SET = 'Forms_Public_Guest';
	private static final Integer WAIT_MINUTES = 60;

	@NamespaceAccessible
	public FormsHealthCheckExtension() {
		// Built by name from Core (HealthCheckExtensions), so it needs a public constructor.
	}

	public List<HealthCheckService.Finding> findings() {
		List<HealthCheckService.Finding> found = new List<HealthCheckService.Finding>();
		if (
			!HealthCheckService.canManageSettings() ||
			ModuleManagerService.turnedOff().contains(FormsAccessSync.MODULE_NAME.toLowerCase()) ||
			!Schema.SObjectType.Form__c.isAccessible()
		) {
			return found;
		}
		try {
			addFindings(found);
		} catch (Exception e) {
			found.add(HealthCheckService.checkFailed('forms_public', e));
		}
		return found;
	}

	private static void addFindings(List<HealthCheckService.Finding> found) {
		if (
			[
				SELECT COUNT()
				FROM Form__c
				WHERE Public__c = TRUE AND Status__c = 'Published'
				WITH USER_MODE
			] == 0
		) {
			return;
		}
		if (FormsSites.active().isEmpty()) {
			found.add(
				finding(
					'forms_public_no_site',
					BarnHelp.text('Forms', 'Forms_Health_NoSiteTitle'),
					BarnHelp.text('Forms', 'Forms_Health_NoSiteDetail'),
					HealthCheckService.SEVERITY_WARNING
				)
			);
		}
		List<String> missing = sitesWithoutGuestAccess();
		if (!missing.isEmpty()) {
			found.add(
				finding(
						FIX_GUEST,
						BarnHelp.text('Forms', 'Forms_Health_GuestAccessTitle'),
						BarnHelp.text('Forms', 'Forms_Health_GuestAccessDetail'),
						HealthCheckService.SEVERITY_WARNING
					)
					.withScope(missing)
					.withFix(labelOf(FIX_GUEST), HealthCheckService.FIX_ACTION_PREFIX + FIX_GUEST)
			);
		}
		if (guestsReadPeople()) {
			found.add(
				finding(
					'forms_public_guest_reads_people',
					BarnHelp.text('Forms', 'Forms_Health_GuestReadsPeopleTitle'),
					BarnHelp.text('Forms', 'Forms_Health_GuestReadsPeopleDetail'),
					HealthCheckService.SEVERITY_ERROR
				)
			);
		}
		if (!FormPublicProcessor.isScheduled()) {
			found.add(
				finding(
						FIX_SCHEDULE,
						BarnHelp.text('Forms', 'Forms_Health_NotScheduledTitle'),
						BarnHelp.text('Forms', 'Forms_Health_NotScheduledDetail'),
						HealthCheckService.SEVERITY_WARNING
					)
					.withScope(scopeOf(FIX_SCHEDULE))
					.withFix(
						labelOf(FIX_SCHEDULE),
						HealthCheckService.FIX_ACTION_PREFIX + FIX_SCHEDULE
					)
			);
		}
		Datetime before = Datetime.now().addMinutes(-WAIT_MINUTES);
		if (
			[
				SELECT COUNT()
				FROM Form_Submission__c
				WHERE Status__c = :FormIntakeService.RECEIVED AND CreatedDate < :before
				WITH USER_MODE
			] > 0
		) {
			found.add(
				finding(
					'forms_public_waiting',
					BarnHelp.text('Forms', 'Forms_Health_WaitingTitle'),
					BarnHelp.text('Forms', 'Forms_Health_WaitingDetail'),
					HealthCheckService.SEVERITY_WARNING
				)
			);
		}
	}

	private static HealthCheckService.Finding finding(
		String key,
		String title,
		String detail,
		String severity
	) {
		return new HealthCheckService.Finding(
			key,
			title,
			detail,
			severity,
			HealthCheckService.CATEGORY_SETTINGS
		);
	}

	/** The names of active Sites whose guest user lacks the public forms permission set. */
	private static List<String> sitesWithoutGuestAccess() {
		Set<Id> granted = new Set<Id>();
		for (PermissionSetAssignment assignment : [
			SELECT AssigneeId
			FROM PermissionSetAssignment
			WHERE PermissionSet.Name = :GUEST_PERMISSION_SET AND AssigneeId IN :guestUserIds()
			WITH SYSTEM_MODE
		]) {
			granted.add(assignment.AssigneeId);
		}
		List<String> names = new List<String>();
		for (FormsSites.SiteInfo site : FormsSites.active()) {
			if (site.guestUserId != null && !granted.contains(site.guestUserId)) {
				names.add(site.name);
			}
		}
		return names;
	}

	/** True when any active Site's guest user may read Contact or Account. */
	private static Boolean guestsReadPeople() {
		Set<Id> permissionSetIds = new Set<Id>();
		for (PermissionSetAssignment assignment : [
			SELECT PermissionSetId
			FROM PermissionSetAssignment
			WHERE AssigneeId IN :guestUserIds()
			WITH SYSTEM_MODE
		]) {
			permissionSetIds.add(assignment.PermissionSetId);
		}
		return [
				SELECT COUNT()
				FROM ObjectPermissions
				WHERE
					ParentId IN :permissionSetIds
					AND SobjectType IN ('Contact', 'Account')
					AND PermissionsRead = TRUE
				WITH SYSTEM_MODE
			] > 0;
	}

	private static Set<Id> guestUserIds() {
		Set<Id> ids = new Set<Id>();
		for (FormsSites.SiteInfo site : FormsSites.active()) {
			if (site.guestUserId != null) {
				ids.add(site.guestUserId);
			}
		}
		return ids;
	}

	public List<String> fixScope(String fixKey) {
		return scopeOf(fixKey);
	}

	public String fixLabel(String fixKey) {
		return labelOf(fixKey);
	}

	private static List<String> scopeOf(String fixKey) {
		if (fixKey == FIX_GUEST) {
			return sitesWithoutGuestAccess();
		}
		return fixKey == FIX_SCHEDULE ? new List<String>{ FormPublicProcessor.JOB_NAME } : null;
	}

	private static String labelOf(String fixKey) {
		if (fixKey == FIX_GUEST) {
			return BarnHelp.text('Forms', 'Forms_Health_GuestAccessFix');
		}
		return fixKey == FIX_SCHEDULE
			? BarnHelp.text('Forms', 'Forms_Health_NotScheduledFix')
			: null;
	}

	public String runFix(String fixKey, List<String> scope) {
		if (fixKey == FIX_SCHEDULE) {
			FormPublicProcessor.schedule();
			return BarnHelp.text('Forms', 'Forms_Health_NotScheduledDone');
		}
		if (fixKey != FIX_GUEST) {
			return null;
		}
		Set<String> names = new Set<String>(scope == null ? new List<String>() : scope);
		List<PermissionSet> sets = [
			SELECT Id
			FROM PermissionSet
			WHERE Name = :GUEST_PERMISSION_SET
			WITH SYSTEM_MODE
			LIMIT 1
		];
		List<PermissionSetAssignment> added = new List<PermissionSetAssignment>();
		for (FormsSites.SiteInfo site : FormsSites.active()) {
			if (!sets.isEmpty() && names.contains(site.name) && site.guestUserId != null) {
				added.add(
					new PermissionSetAssignment(
						AssigneeId = site.guestUserId,
						PermissionSetId = sets[0].Id
					)
				);
			}
		}
		insert as user added;
		return BarnHelp.text(
			'Forms',
			'Forms_Health_GuestAccessDone',
			new List<Object>{ String.join(new List<String>(names), ', ') }
		);
	}
}
