/**
 * Public event pages' checks in Health Check, in the Settings console (EV-16; ADR-0190 public
 * event pages, decision 8; ADR-0057's extension seam). Core finds this class by name
 * (`HealthCheckExtensions.EXTENSION_CLASSES`).
 *
 * Asked only while an Open or Closed event has Public Page on, of a viewer who may manage
 * settings:
 * - no package that serves public pages (BarnCRM Forms) is installed: the pages cannot be shown;
 * - an Open public event names no registration form: its page shows details only;
 * - Take payment online is on but BarnCRM Payments is not installed or its keys are missing (EV-20).
 *
 * `@NamespaceAccessible`, public, with a public no-argument constructor, because Core resolves it
 * with `Type.forName` under ADR-0017.
 */
@NamespaceAccessible
public with sharing class EventsHealthCheckExtension implements HealthCheckExtension {
	@TestVisible
	private static final String NO_HOST = 'events_public_no_host';
	@TestVisible
	private static final String NO_FORM = 'events_public_no_form';
	@TestVisible
	private static final String PAYMENTS_NOT_READY = 'events_payments_not_ready';
	private static final Set<String> SHOWN_STATUSES = new Set<String>{ 'Open', 'Closed' };

	@NamespaceAccessible
	public EventsHealthCheckExtension() {
		// Built by name from Core (HealthCheckExtensions), so it needs a public constructor.
	}

	public List<HealthCheckService.Finding> findings() {
		List<HealthCheckService.Finding> found = new List<HealthCheckService.Finding>();
		if (
			!HealthCheckService.canManageSettings() ||
			ModuleManagerService.turnedOff().contains(EventsPostInstall.MODULE_KEY.toLowerCase()) ||
			!Schema.SObjectType.Event__c.isAccessible()
		) {
			return found;
		}
		try {
			addFindings(found);
		} catch (Exception e) {
			found.add(HealthCheckService.checkFailed('events_public', e));
		}
		// EV-20: Take payment online is on but Payments cannot take the payment.
		if (EventsSettings.onlinePayments() && !EventPayments.takesOnline()) {
			found.add(
				new HealthCheckService.Finding(
					PAYMENTS_NOT_READY,
					BarnHelp.text('Events', 'Events_Health_PaymentsNotReadyTitle'),
					BarnHelp.text('Events', 'Events_Health_PaymentsNotReadyDetail'),
					HealthCheckService.SEVERITY_WARNING,
					HealthCheckService.CATEGORY_SETTINGS
				)
			);
		}
		return found;
	}

	private static void addFindings(List<HealthCheckService.Finding> found) {
		Integer published = 0;
		Integer withoutForm = 0;
		for (Event__c event : [
			SELECT Status__c, Registration_Form_Key__c
			FROM Event__c
			WHERE Public_Page__c = TRUE AND Status__c IN :SHOWN_STATUSES
			WITH USER_MODE
			LIMIT 2000
		]) {
			published++;
			if (event.Status__c == 'Open' && String.isBlank(event.Registration_Form_Key__c)) {
				withoutForm++;
			}
		}
		if (published == 0) {
			return;
		}
		if (!PublicPageExtensions.hostInstalled()) {
			found.add(
				new HealthCheckService.Finding(
					NO_HOST,
					BarnHelp.text('Events', 'Events_Health_PublicNoHostTitle'),
					BarnHelp.text(
						'Events',
						'Events_Health_PublicNoHostDetail',
						new List<Object>{ published }
					),
					HealthCheckService.SEVERITY_WARNING,
					HealthCheckService.CATEGORY_SETTINGS
				)
			);
		} else if (withoutForm > 0) {
			found.add(
				new HealthCheckService.Finding(
					NO_FORM,
					BarnHelp.text('Events', 'Events_Health_PublicNoFormTitle'),
					BarnHelp.text(
						'Events',
						'Events_Health_PublicNoFormDetail',
						new List<Object>{ withoutForm }
					),
					HealthCheckService.SEVERITY_INFO,
					HealthCheckService.CATEGORY_SETTINGS
				)
			);
		}
	}
}
