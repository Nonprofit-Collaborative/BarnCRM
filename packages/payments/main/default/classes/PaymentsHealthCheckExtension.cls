/**
 * Payments' checks in Health Check, in the Settings console (ADR-NEXT `NEXT-payments-module.md`,
 * decision 7; ADR-0057's extension seam, ADR-0125's fixes). Core finds this class by name
 * (`HealthCheckExtensions.EXTENSION_CLASSES`).
 *
 * Asked only while Payments is turned on, of a viewer who may manage settings:
 * - the chosen processor's keys not all entered;
 * - a Stripe secret key for the other mode (a test key in Live, or a live key in Test);
 * - no active Salesforce Site to receive processor events;
 * - a Site guest user without `Payments_Webhook_Guest` (fix: assign it);
 * - processing not scheduled (fix: schedule it as the viewer);
 * - received events waiting over an hour.
 *
 * `@NamespaceAccessible`, public, with a public no-argument constructor, because Core resolves it
 * with `Type.forName` under ADR-0017.
 */
@NamespaceAccessible
public with sharing class PaymentsHealthCheckExtension implements HealthCheckExtension, HealthCheckFixExtension {
	@TestVisible
	private static final String FIX_GUEST = 'payments_guest_access';
	@TestVisible
	private static final String FIX_SCHEDULE = 'payments_processing';
	public static final String GUEST_PERMISSION_SET = 'Payments_Webhook_Guest';
	private static final Integer WAIT_MINUTES = 60;

	@NamespaceAccessible
	public PaymentsHealthCheckExtension() {
		// Built by name from Core (HealthCheckExtensions), so it needs a public constructor.
	}

	public List<HealthCheckService.Finding> findings() {
		List<HealthCheckService.Finding> found = new List<HealthCheckService.Finding>();
		if (
			!HealthCheckService.canManageSettings() ||
			ModuleManagerService.turnedOff()
				.contains(PaymentsAccessSync.MODULE_NAME.toLowerCase()) ||
			!Schema.SObjectType.Payment_Event__c.isAccessible()
		) {
			return found;
		}
		try {
			addFindings(found);
		} catch (Exception e) {
			found.add(HealthCheckService.checkFailed('payments', e));
		}
		return found;
	}

	private static void addFindings(List<HealthCheckService.Finding> found) {
		String processor = PaymentService.defaultProcessor();
		if (!PaymentService.isReady(processor)) {
			found.add(
				finding(
					'payments_keys_missing',
					BarnHelp.text('Payments', 'Payments_Health_KeysMissingTitle'),
					BarnHelp.text(
						'Payments',
						'Payments_Health_KeysMissingDetail',
						new List<Object>{ processor }
					),
					HealthCheckService.SEVERITY_WARNING
				)
			);
		}
		if (stripeKeyMismatch()) {
			found.add(
				finding(
					'payments_mode_mismatch',
					BarnHelp.text('Payments', 'Payments_Health_ModeMismatchTitle'),
					BarnHelp.text(
						'Payments',
						'Payments_Health_ModeMismatchDetail',
						new List<Object>{ PaymentService.mode() }
					),
					HealthCheckService.SEVERITY_ERROR
				)
			);
		}
		if (PaymentSites.active().isEmpty()) {
			found.add(
				finding(
					'payments_no_site',
					BarnHelp.text('Payments', 'Payments_Health_NoSiteTitle'),
					BarnHelp.text('Payments', 'Payments_Health_NoSiteDetail'),
					HealthCheckService.SEVERITY_WARNING
				)
			);
		}
		List<String> missing = sitesWithoutGuestAccess();
		if (!missing.isEmpty()) {
			found.add(
				finding(
						FIX_GUEST,
						BarnHelp.text('Payments', 'Payments_Health_GuestAccessTitle'),
						BarnHelp.text('Payments', 'Payments_Health_GuestAccessDetail'),
						HealthCheckService.SEVERITY_WARNING
					)
					.withScope(missing)
					.withFix(labelOf(FIX_GUEST), HealthCheckService.FIX_ACTION_PREFIX + FIX_GUEST)
			);
		}
		if (!PaymentEventProcessor.isScheduled()) {
			found.add(
				finding(
						FIX_SCHEDULE,
						BarnHelp.text('Payments', 'Payments_Health_NotScheduledTitle'),
						BarnHelp.text('Payments', 'Payments_Health_NotScheduledDetail'),
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
				FROM Payment_Event__c
				WHERE Status__c = 'Received' AND CreatedDate < :before
				WITH USER_MODE
			] > 0
		) {
			found.add(
				finding(
					'payments_waiting',
					BarnHelp.text('Payments', 'Payments_Health_WaitingTitle'),
					BarnHelp.text('Payments', 'Payments_Health_WaitingDetail'),
					HealthCheckService.SEVERITY_WARNING
				)
			);
		}
	}

	/** True when the Stripe secret key is for the other mode (`sk_test_`, `sk_live_`, `rk_`). */
	@TestVisible
	private static Boolean stripeKeyMismatch() {
		String key = PaymentService.keys().Stripe_Secret_Key__c;
		if (String.isBlank(key) || key.length() < 8) {
			return false;
		}
		Boolean testKey = key.substring(3, 8) == 'test_';
		Boolean liveKey = key.substring(3, 8) == 'live_';
		return PaymentService.mode() == PaymentService.LIVE ? testKey : liveKey;
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

	/** The names of active Sites whose guest user lacks the receiver's permission set. */
	private static List<String> sitesWithoutGuestAccess() {
		Set<Id> granted = new Set<Id>();
		for (PermissionSetAssignment assignment : [
			SELECT AssigneeId
			FROM PermissionSetAssignment
			WHERE
				PermissionSet.Name = :GUEST_PERMISSION_SET
				AND AssigneeId IN :PaymentSites.guestUserIds()
			WITH SYSTEM_MODE
		]) {
			granted.add(assignment.AssigneeId);
		}
		List<String> names = new List<String>();
		for (PaymentSites.SiteInfo site : PaymentSites.active()) {
			if (site.guestUserId != null && !granted.contains(site.guestUserId)) {
				names.add(site.name);
			}
		}
		return names;
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
		return fixKey == FIX_SCHEDULE ? new List<String>{ PaymentEventProcessor.JOB_NAME } : null;
	}

	private static String labelOf(String fixKey) {
		if (fixKey == FIX_GUEST) {
			return BarnHelp.text('Payments', 'Payments_Health_GuestAccessFix');
		}
		return fixKey == FIX_SCHEDULE
			? BarnHelp.text('Payments', 'Payments_Health_NotScheduledFix')
			: null;
	}

	public String runFix(String fixKey, List<String> scope) {
		if (fixKey == FIX_SCHEDULE) {
			PaymentEventProcessor.schedule();
			return BarnHelp.text('Payments', 'Payments_Health_NotScheduledDone');
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
		for (PaymentSites.SiteInfo site : PaymentSites.active()) {
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
			'Payments',
			'Payments_Health_GuestAccessDone',
			new List<Object>{ String.join(new List<String>(names), ', ') }
		);
	}
}
