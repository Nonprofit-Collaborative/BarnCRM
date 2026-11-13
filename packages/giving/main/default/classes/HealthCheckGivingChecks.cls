/**
 * The Giving questions Health Check asks, added to Core's one report through
 * `GivingHealthCheckExtension` (G-20 follow-up, ADR-0053, ADR-0057). Grouped the way
 * ADR-0039 groups Core's own checks, in its own class, so a second Giving check reads next to
 * this one rather than inside Core.
 *
 * Three questions. Whether receipt generation has been failing is asked of every viewer; who
 * holds the receipt lock override and which locked gifts are unposted are asked only of a
 * viewer who may manage settings. The first two moved here from Core with C-29 (ADR-0059),
 * with their keys, wording, severities, categories and fixes unchanged.
 *
 * Whether a gift is in the books, and what "locked" means, is `GiftPostingLock`'s rule
 * (ADR-0022, ADR-0053): a gift with a counting status (Received, Refunded or Written off, or a
 * blank status, which `GiftPostingLock.isInBooks` also reads as Received) and a type other than
 * In-kind. This class asks nothing about that rule Core does not already enforce; it only
 * reports what the rule finds, capped and linked the way `HealthCheckHouseholdChecks` reports
 * orphan records in Core.
 *
 * Only asked of a viewer who may manage settings (`HealthCheckService.canManageSettings()`):
 * posting and the close date are an administrator's business. `HealthCheckGivingSelector` reads
 * `without sharing`, unlike `HouseholdOrphanSelector`'s shared orphan reads in Core: Gift__c
 * ships with Private sharing (R-G14), so a viewer's own record sharing narrows which gifts they
 * own or share, not which gifts are actually locked and unposted, and a Health Check finding
 * that silently under-counts because the administrator does not happen to share every gift is a
 * wrong answer, not a narrower one. ADR-0021, amended by this ADR, keeps this as a named
 * exception to "reads that reach a user stay in user mode," so the gate matters twice as much
 * as it would for a shared read: `HealthCheckGivingSelector` asserts
 * `canManageSettings()` itself, not only this class, the same permission check that is the
 * access control that matters for every other Settings-category check that reads org-wide
 * state.
 */
public with sharing class HealthCheckGivingChecks {
	/** Counts stop here, and the finding says "more than" this many. A test lowers it. */
	@TestVisible
	private static Integer countCap = 1000;

	/** How many example gifts a finding links to. */
	private static final Integer LINKS_SHOWN = 5;

	/**
	 * How many reconciled receipt numbers are ordinary. One number consumed by a failed run
	 * is the mechanism working (R-RC3); more than one is generation failing repeatedly with
	 * nobody watching.
	 */
	private static final Integer RECEIPT_FAILURES_EXPECTED = 1;

	/** Injected by the tests, which cannot create a custom permission with DML. */
	@TestVisible
	private static CustomPermissionSelector.Holders holdersOverride;

	/** The check keys, which name a check that threw in its `check_failed_<key>` finding. */
	private static final String CHECK_RECEIPT_GENERATION = 'receipt_generation';
	private static final String CHECK_OVERRIDE_RECEIPT_LOCK = 'override_receipt_lock';
	private static final String CHECK_UNPOSTED_CLOSED_PERIOD = 'unposted_gifts_closed_period';
	private static final String CHECK_DONATION_FORM_AMOUNT = 'donation_form_amount';
	private static final String CHECK_LOOKUP_SKEW = 'gift_lookup_skew';
	private static final String CHECK_GIFT_OWNERSHIP_SKEW = 'gift_ownership_skew';

	/**
	 * Every finding Giving adds to the Health Check report, for this viewer. Each check is
	 * isolated the way Core isolates its own: one that throws becomes its own
	 * `check_failed_<key>` finding, and the other Giving findings still stand.
	 */
	public static List<HealthCheckService.Finding> findings() {
		List<String> checks = new List<String>{ CHECK_RECEIPT_GENERATION };
		if (HealthCheckService.canManageSettings()) {
			checks.add(CHECK_OVERRIDE_RECEIPT_LOCK);
			checks.add(CHECK_UNPOSTED_CLOSED_PERIOD);
			checks.add(CHECK_DONATION_FORM_AMOUNT);
			checks.add(CHECK_LOOKUP_SKEW);
			checks.add(CHECK_GIFT_OWNERSHIP_SKEW);
		}

		List<HealthCheckService.Finding> findings = new List<HealthCheckService.Finding>();
		for (String check : checks) {
			if (HealthCheckService.nearLimits()) {
				break;
			}
			try {
				addIfAny(findings, run(check));
			} catch (Exception e) {
				findings.add(HealthCheckService.checkFailed(check, e));
			}
		}
		return findings;
	}

	private static HealthCheckService.Finding run(String check) {
		if (check == CHECK_OVERRIDE_RECEIPT_LOCK) {
			return overrideReceiptLockFinding();
		}
		if (check == CHECK_UNPOSTED_CLOSED_PERIOD) {
			return unpostedClosedPeriodFinding();
		}
		if (check == CHECK_DONATION_FORM_AMOUNT) {
			return donationFormAmountFinding();
		}
		if (check == CHECK_LOOKUP_SKEW) {
			return lookupSkewFinding();
		}
		if (check == CHECK_GIFT_OWNERSHIP_SKEW) {
			return HealthCheckSkew.ownership(
				CHECK_GIFT_OWNERSHIP_SKEW,
				Gift__c.SObjectType.getDescribe().getName(),
				null,
				null,
				Gift__c.SObjectType.getDescribe().getLabelPlural()
			);
		}
		return receiptGenerationFinding();
	}

	/**
	 * Funds and Appeals with more than HealthCheckSkew.threshold() gifts (D-200 P12, lookup
	 * skew). Every gift saved against one of them locks the same parent row, so large parallel
	 * loads fail with lock errors. Read from the rollup counts, never by counting gifts.
	 */
	private static HealthCheckService.Finding lookupSkewFinding() {
		Integer threshold = HealthCheckSkew.threshold();
		List<SObject> skewed = new List<SObject>();
		skewed.addAll(
			[
				SELECT Id, Name
				FROM Fund__c
				WHERE Gift_Count__c > :threshold
				WITH SYSTEM_MODE
				ORDER BY Gift_Count__c DESC
				LIMIT :LINKS_SHOWN
			]
		);
		skewed.addAll(
			[
				SELECT Id, Name
				FROM Appeal__c
				WHERE Gift_Count__c > :threshold
				WITH SYSTEM_MODE
				ORDER BY Gift_Count__c DESC
				LIMIT :LINKS_SHOWN
			]
		);
		if (skewed.isEmpty()) {
			return null;
		}
		List<HealthCheckService.Link> links = new List<HealthCheckService.Link>();
		for (SObject record : skewed) {
			links.add(new HealthCheckService.Link(record));
		}
		return new HealthCheckService.Finding(
				CHECK_LOOKUP_SKEW,
				BarnHelp.text('Giving', 'Giving_HealthCheck_LookupSkewTitle'),
				String.format(
					BarnHelp.text('Giving', 'Giving_HealthCheck_LookupSkewDetail'),
					new List<Object>{ threshold.format() }
				),
				HealthCheckService.SEVERITY_INFO,
				HealthCheckService.CATEGORY_SETTINGS
			)
			.withLinks(links);
	}

	private static void addIfAny(
		List<HealthCheckService.Finding> findings,
		HealthCheckService.Finding finding
	) {
		if (finding != null) {
			findings.add(finding);
		}
	}

	/**
	 * Receipt numbers consumed by a run that failed (R-RC3). One is the reconciliation
	 * mechanism doing its job and is reported as information; more than one is receipt
	 * generation failing repeatedly, which is a warning because the donors are waiting. A
	 * person who cannot read receipts is told nothing rather than told zero.
	 */
	private static HealthCheckService.Finding receiptGenerationFinding() {
		ReceiptGenerationFailureSelector.Result failures = ReceiptGenerationFailureSelector.generationFailures();
		if (failures == null || failures.available != true || failures.count <= 0) {
			return null;
		}

		if (failures.count <= RECEIPT_FAILURES_EXPECTED) {
			return new HealthCheckService.Finding(
					'receipt_generation_failed_once',
					Label.Giving_HealthCheck_ReceiptFailedOneTitle,
					BarnHelp.text('Giving', 'Giving_HealthCheck_ReceiptFailedOneDetail'),
					HealthCheckService.SEVERITY_INFO,
					HealthCheckService.CATEGORY_SETTINGS
				)
				.withFix(Label.Core_ErrorLogTile_ViewAll, ErrorLogCountSelector.listViewUrl());
		}

		String counted = failures.capped == true
			? String.format(
					Label.Core_HealthCheck_OrphansMoreThan,
					new List<Object>{ failures.count.format() }
			  )
			: String.valueOf(failures.count);
		List<Object> count = new List<Object>{ counted };
		return new HealthCheckService.Finding(
				'receipt_generation_failed',
				String.format(Label.Giving_HealthCheck_ReceiptFailedManyTitle, count),
				String.format(
					BarnHelp.text('Giving', 'Giving_HealthCheck_ReceiptFailedManyDetail'),
					count
				),
				HealthCheckService.SEVERITY_WARNING,
				HealthCheckService.CATEGORY_SETTINGS
			)
			.withFix(Label.Core_ErrorLogTile_ViewAll, ErrorLogCountSelector.listViewUrl());
	}

	/**
	 * Active appeals with Donation Page on whose donation form has no `amount` question (R-AP5):
	 * their page cannot start a checkout. Forms is read by name, so Giving needs no Forms.
	 */
	private static HealthCheckService.Finding donationFormAmountFinding() {
		Schema.SObjectType formType = NamespaceUtil.packagedObjectType('Form__c');
		Map<Id, List<Appeal__c>> byForm = new Map<Id, List<Appeal__c>>();
		for (Appeal__c appeal : [
			SELECT Id, Name, Donation_Form_Key__c
			FROM Appeal__c
			WHERE Active__c = TRUE AND Donation_Page__c = TRUE AND Donation_Form_Key__c != NULL
			WITH USER_MODE
			LIMIT 200
		]) {
			try {
				Id formId = Id.valueOf(appeal.Donation_Form_Key__c.trim());
				if (!byForm.containsKey(formId)) {
					byForm.put(formId, new List<Appeal__c>());
				}
				byForm.get(formId).add(appeal);
			} catch (StringException notAnId) {
				continue;
			}
		}
		Schema.SObjectType versionType = NamespaceUtil.packagedObjectType('Form_Version__c');
		if (formType == null || versionType == null || byForm.isEmpty()) {
			return null;
		}
		Set<Id> formIds = byForm.keySet();
		// Form__c.Published_Version__c is a version number, not a lookup: the published
		// definition is the form's newest Form_Version__c, as Forms itself reads it.
		String formLookup = String.escapeSingleQuotes(NamespaceUtil.qualify('Form__c'));
		String definition = String.escapeSingleQuotes(NamespaceUtil.qualify('Definition__c'));
		String versionNumber = String.escapeSingleQuotes(NamespaceUtil.qualify('Version__c'));
		Map<Id, String> newest = new Map<Id, String>();
		for (
			SObject version : Database.query(
				'SELECT ' +
					formLookup +
					', ' +
					definition +
					' FROM ' +
					String.escapeSingleQuotes(String.valueOf(versionType)) +
					' WHERE ' +
					formLookup +
					' IN :formIds ORDER BY ' +
					versionNumber +
					' DESC',
				AccessLevel.SYSTEM_MODE
			)
		) {
			Id formId = (Id) version.get(formLookup);
			if (!newest.containsKey(formId)) {
				newest.put(formId, (String) version.get(definition));
			}
		}
		List<HealthCheckService.Link> links = new List<HealthCheckService.Link>();
		for (
			SObject form : Database.query(
				'SELECT Id FROM ' +
					String.escapeSingleQuotes(String.valueOf(formType)) +
					' WHERE Id IN :formIds',
				AccessLevel.SYSTEM_MODE
			)
		) {
			if (!asksAmount(newest.get(form.Id))) {
				for (Appeal__c appeal : byForm.get(form.Id)) {
					links.add(new HealthCheckService.Link(appeal));
				}
			}
		}
		if (links.isEmpty()) {
			return null;
		}
		return new HealthCheckService.Finding(
				'donation_form_no_amount',
				BarnHelp.text('Giving', 'Giving_HealthCheck_DonationFormTitle'),
				BarnHelp.text('Giving', 'Giving_HealthCheck_DonationFormDetail'),
				HealthCheckService.SEVERITY_WARNING,
				HealthCheckService.CATEGORY_SETTINGS
			)
			.withLinks(links);
	}

	/** True when a form definition has a question whose key is `amount`. */
	@TestVisible
	private static Boolean asksAmount(String definition) {
		Object steps;
		try {
			steps = String.isBlank(definition)
				? null
				: ((Map<String, Object>) JSON.deserializeUntyped(definition)).get('steps');
		} catch (Exception unreadable) {
			return false;
		}
		for (
			Object step : steps instanceof List<Object> ? (List<Object>) steps : new List<Object>()
		) {
			Object fields = step instanceof Map<String, Object>
				? ((Map<String, Object>) step).get('fields')
				: null;
			for (
				Object field : fields instanceof List<Object>
					? (List<Object>) fields
					: new List<Object>()
			) {
				if (
					field instanceof Map<String, Object> &&
					((Map<String, Object>) field).get('key') == GivingDonationPage.ANSWER_AMOUNT
				) {
					return true;
				}
			}
		}
		return false;
	}

	/**
	 * Anyone holding the receipt lock override, by name (ADR-0024). Naming them is the point:
	 * an administrator cannot take a permission away from "somebody". Salesforce shows a
	 * person only their own access, which is why this is asked only of an administrator.
	 */
	private static HealthCheckService.Finding overrideReceiptLockFinding() {
		CustomPermissionSelector.Holders holders = holdersOverride != null
			? holdersOverride
			: CustomPermissionSelector.holders(GiftService.OVERRIDE_RECEIPT_LOCK_PERMISSION);
		if (holders == null || holders.readable != true || holders.total <= 0) {
			return null;
		}

		String detail = String.format(
			BarnHelp.text('Giving', 'Giving_HealthCheck_OverrideLockDetail'),
			new List<Object>{ holderList(holders) }
		);
		return new HealthCheckService.Finding(
				'override_receipt_lock',
				Label.Giving_HealthCheck_OverrideLockTitle,
				detail,
				HealthCheckService.SEVERITY_WARNING,
				HealthCheckService.CATEGORY_ACCESS
			)
			.withFix(
				Label.Giving_HealthCheck_OverrideLockFix,
				HealthCheckService.FIX_CUSTOM_PERMISSIONS_URL
			);
	}

	/**
	 * The holders as a sentence: the first few by name, then a count of the rest, so an org
	 * that has granted the permission to a whole profile still produces a readable line.
	 */
	private static String holderList(CustomPermissionSelector.Holders holders) {
		List<String> parts = new List<String>(holders.names);
		Integer unnamed = holders.total - holders.names.size();
		if (unnamed > 0) {
			parts.add(
				String.format(
					Label.Giving_HealthCheck_OverrideLockMoreNames,
					new List<Object>{ String.valueOf(unnamed) }
				)
			);
		}
		return String.join(parts, ', ');
	}

	/**
	 * Gifts in the books, dated on or before Books Closed Through, that nothing has marked
	 * posted (G-20 follow-up). They are already locked by the period, so nothing about them
	 * can change until they are posted or the period is reopened; a bookkeeper who closed the
	 * month without exporting and marking every gift is the ordinary way this happens.
	 */
	private static HealthCheckService.Finding unpostedClosedPeriodFinding() {
		Date closed = GiftPostingLock.closedThrough();
		if (closed == null) {
			return null;
		}
		Integer count = HealthCheckGivingSelector.countUnpostedInClosedPeriod(closed, countCap + 1);
		if (count == null || count <= 0) {
			return null;
		}
		List<Gift__c> first = HealthCheckGivingSelector.unpostedInClosedPeriod(closed, LINKS_SHOWN);

		String counted = count > countCap
			? String.format(
					Label.Core_HealthCheck_OrphansMoreThan,
					new List<Object>{ countCap.format() }
			  )
			: count.format();

		String text = BarnHelp.text('Giving', 'Giving_HealthCheck_UnpostedClosedPeriodDetail');
		if (!first.isEmpty()) {
			text +=
				' ' +
				String.format(
					Label.Core_HealthCheck_OrphansFirstListed,
					new List<Object>{ String.valueOf(first.size()) }
				);
		}

		List<HealthCheckService.Link> links = new List<HealthCheckService.Link>();
		for (Gift__c gift : first) {
			links.add(new HealthCheckService.Link(gift));
		}

		return new HealthCheckService.Finding(
				'unposted_gifts_closed_period',
				String.format(
					Label.Giving_HealthCheck_UnpostedClosedPeriodTitle,
					new List<Object>{ counted }
				),
				text,
				HealthCheckService.SEVERITY_WARNING,
				HealthCheckService.CATEGORY_SETTINGS
			)
			.withFix(Label.Giving_HealthCheck_UnpostedClosedPeriodFix, SettingSections.GIVING)
			.withLinks(links);
	}
}
