/**
 * The Contact Point Sync page (C-45; ADR-0176 contact point sync module, decisions 10 and 11):
 * whether each kind can be copied in this org and why not, the preview count, the last backfill,
 * and Run Backfill. Thin: it returns plain JSON and every text the page shows, so the page holds
 * no rules (plan 9.9).
 *
 * Opened by holders of Contact Point Sync Admin (class access). The counts are org-wide, read in
 * system mode, because the backfill they preview is org-wide; starting it also needs Manage
 * BarnCRM Settings.
 */
public with sharing class ContactPointSyncController {
	private static final String CONTEXT = 'ContactPointSyncController';
	private static final Set<String> RUNNING_STATUSES = new Set<String>{
		'Holding',
		'Queued',
		'Preparing',
		'Processing'
	};

	/** The page counts this many people and then says "more". A test lowers it. */
	@TestVisible
	private static Integer countCap = 10000;

	/** One kind's line on the page. */
	public class KindStatus {
		@AuraEnabled
		public String kind;
		@AuraEnabled
		public Boolean ready;
		@AuraEnabled
		public String message;
	}

	public class Status {
		@AuraEnabled
		public List<KindStatus> kinds = new List<KindStatus>();
		@AuraEnabled
		public Boolean anyReady = false;
		@AuraEnabled
		public Boolean canRun;
		@AuraEnabled
		public Boolean running;
		@AuraEnabled
		public Integer peopleCount;
		@AuraEnabled
		public Boolean peopleCountCapped;
		@AuraEnabled
		public Integer managedCount;
		@AuraEnabled
		public Datetime lastBackfill;
		@AuraEnabled
		public String lastSummary;
	}

	@AuraEnabled
	public static Status getStatus() {
		try {
			return status();
		} catch (Exception unexpected) {
			throw UserErrors.wrap(unexpected, CONTEXT, true);
		}
	}

	/** Starts the backfill, or says in words why it cannot start. */
	@AuraEnabled
	public static Status runBackfill() {
		Status current;
		try {
			current = status();
		} catch (Exception unexpected) {
			throw UserErrors.wrap(unexpected, CONTEXT, true);
		}
		String refusal = refusal(current);
		if (refusal != null) {
			throw UserErrors.message(refusal);
		}
		try {
			ContactPointBackfillBatch.start();
		} catch (Exception unexpected) {
			throw UserErrors.wrap(unexpected, CONTEXT, true);
		}
		current.running = true;
		return current;
	}

	@TestVisible
	private static String refusal(Status current) {
		if (!current.canRun) {
			return BarnHelp.text('ContactPoints', 'ContactPoints_Page_NoManagePermission');
		}
		if (!current.anyReady) {
			return BarnHelp.text('ContactPoints', 'ContactPoints_Page_NothingToCopy');
		}
		if (current.running) {
			return BarnHelp.text('ContactPoints', 'ContactPoints_Page_Running');
		}
		return null;
	}

	private static Status status() {
		Status current = new Status();
		Boolean individuals = ContactPointSyncService.individualsAvailable();
		for (String kind : ContactPointSyncService.kinds()) {
			KindStatus line = kindStatus(kind, individuals);
			current.anyReady = current.anyReady || line.ready;
			current.kinds.add(line);
		}
		current.canRun = AutomationControl.canManage();
		current.running = ![
				SELECT Id
				FROM AsyncApexJob
				WHERE
					ApexClass.Name = :ContactPointBackfillBatch.CLASS_NAME
					AND Status IN :RUNNING_STATUSES
				WITH SYSTEM_MODE
				LIMIT 1
			]
			.isEmpty();
		Integer people = [SELECT COUNT() FROM Contact WITH SYSTEM_MODE LIMIT :countCap + 1];
		current.peopleCountCapped = people > countCap;
		current.peopleCount = current.peopleCountCapped ? countCap : people;
		current.managedCount = [
			SELECT COUNT()
			FROM Contact_Point_Link__c
			WHERE Contact_Point_Id__c != NULL
			WITH SYSTEM_MODE
			LIMIT :countCap + 1
		];
		Contact_Point_Sync_Settings__c saved = Contact_Point_Sync_Settings__c.getOrgDefaults();
		current.lastBackfill = saved == null ? null : saved.Last_Backfill__c;
		current.lastSummary = saved == null ? null : saved.Last_Backfill_Summary__c;
		return current;
	}

	private static KindStatus kindStatus(String kind, Boolean individuals) {
		KindStatus line = new KindStatus();
		line.kind = kind;
		line.ready = false;
		Schema.SObjectType type = ContactPointSyncService.typeOf(kind);
		if (type == null) {
			line.message = BarnHelp.text(
				'ContactPoints',
				'ContactPoints_Kind_Missing',
				new List<Object>{ kind }
			);
		} else if (!individuals) {
			line.message = BarnHelp.text(
				'ContactPoints',
				'ContactPoints_Kind_NoIndividual',
				new List<Object>{ kind }
			);
		} else if (!ContactPointSyncService.switchedOn(kind)) {
			line.message = BarnHelp.text(
				'ContactPoints',
				'ContactPoints_Kind_Off',
				new List<Object>{ kind }
			);
		} else {
			line.ready = true;
			line.message = type.getDescribe().isAccessible()
				? BarnHelp.text(
						'ContactPoints',
						'ContactPoints_Kind_Ready',
						new List<Object>{ kind }
				  )
				: BarnHelp.text(
						'ContactPoints',
						'ContactPoints_Kind_Restricted',
						new List<Object>{ kind }
				  );
		}
		return line;
	}
}
