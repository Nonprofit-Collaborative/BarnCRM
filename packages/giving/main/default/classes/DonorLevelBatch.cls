/**
 * Re-places every donor on the ladder: the nightly pass, and the Recalculate now button on the
 * Donor Levels page, which are the same job (R-DL6).
 *
 * A save announces a changed giving total, so real time assignment covers almost everything. Two
 * things announce nothing and are the whole reason this batch exists: a fiscal year turning over,
 * which changes what "giving this year" means without touching a single record, and a ladder an
 * administrator edited yesterday, which changes what every total earns.
 *
 * It runs over accounts first and chains to contacts, so one run covers households, organizations,
 * people held as accounts, and people held as contacts. Only the records that actually move are
 * written, so a normal night reads broadly and writes very little.
 */
public with sharing class DonorLevelBatch implements Database.Batchable<SObject>, Database.Stateful {
	@TestVisible
	private static final String ACCOUNTS = 'Account';
	@TestVisible
	private static final String CONTACTS = 'Contact';
	/** The settings console section the Donor Levels page is in. */
	private static final String GIVING_SECTION = 'Giving';

	private final String scopeObject;
	private Integer moved = 0;
	/** Who pressed Recalculate now, told when the run ends; null for the nightly run (Q-04). */
	private Id notifyUserId;
	/**
	 * Last gift date ranges in pairs, for a pass over only the donors crossing a recency cutoff
	 * (D-200 P1); null for every donor.
	 */
	@TestVisible
	private final List<Date> edges;

	/** A run that starts with accounts and chains to contacts. */
	public DonorLevelBatch() {
		this(ACCOUNTS, JobNotifier.starter(), 0, null);
	}

	@TestVisible
	private DonorLevelBatch(String scopeObject) {
		this(scopeObject, JobNotifier.starter(), 0, null);
	}

	/** A pass that carries who to tell, what the passes before it moved, and its ranges. */
	private DonorLevelBatch(String scopeObject, Id notifyUserId, Integer moved, List<Date> edges) {
		this.scopeObject = scopeObject;
		this.notifyUserId = notifyUserId;
		this.moved = moved;
		this.edges = edges;
	}

	/**
	 * A run over only the donors whose last gift date lies in these ranges: the night's donor
	 * scores move only where days since the last gift cross a recency cutoff. It neither records
	 * a recalculation nor sends a notice.
	 */
	public static DonorLevelBatch recencyEdges(List<Date> edges) {
		return new DonorLevelBatch(ACCOUNTS, null, 0, edges);
	}

	public Database.QueryLocator start(Database.BatchableContext context) {
		if (edges != null) {
			return DonorLevelSelector.recencyEdgeLocator(scopeObject, edges);
		}
		return ACCOUNTS.equals(scopeObject)
			? DonorLevelSelector.accountLocator()
			: DonorLevelSelector.contactLocator();
	}

	public void execute(Database.BatchableContext context, List<SObject> scope) {
		try {
			DonorLevelService.clearCache();
			// The records as read, so only values the pass changed are written (RT-09).
			Map<Id, SObject> before = new Map<Id, SObject>();
			for (SObject record : scope) {
				before.put(record.Id, record.clone(true, true, true, true));
			}
			List<SObject> changed = DonorLevelService.assignAll(scope);
			// The same pass keeps donor scores right as the days go by (G-19, R-DT5).
			List<SObject> rescored = DonorScoreService.scoreAll(scope);
			Map<Id, SObject> toSave = new Map<Id, SObject>(changed);
			toSave.putAll(rescored);
			DonorLevelWriter.saveChanged(toSave.values(), before);
			moved += changed.size();
		} catch (Exception chunkFailure) {
			// One bad chunk must not stop the rest of the org being re-placed.
			ErrorLogger.log(chunkFailure, 'DonorLevelBatch.' + scopeObject);
		}
	}

	public void finish(Database.BatchableContext context) {
		try {
			if (ACCOUNTS.equals(scopeObject)) {
				if (!Test.isRunningTest()) {
					Database.executeBatch(
						new DonorLevelBatch(CONTACTS, notifyUserId, moved, edges),
						200
					);
				}
				return;
			}
			if (edges != null) {
				return;
			}
			DonorLevelService.recordRecalculation(System.now());
		} catch (Exception finishFailure) {
			ErrorLogger.log(finishFailure, 'DonorLevelBatch.finish');
		}
		// The contacts pass is the end of the run, so the one notification goes from there.
		JobNotifier.aboutSettings(
			notifyUserId,
			Label.Giving_JobNotice_DonorLevels,
			false,
			String.format(
				BarnHelp.text('Giving', 'Giving_JobNotice_DonorLevelsBody'),
				new List<Object>{ moved.format() }
			),
			GIVING_SECTION
		);
	}
}
