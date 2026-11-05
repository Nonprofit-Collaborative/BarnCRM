/**
 * The Funders part of the C-10 sample data set: Core finds this class by name
 * (`SampleDataModules.MODULE_CLASS_NAMES`), so the same Load Sample Data action in BarnCRM
 * Settings fills an org that has Funders with three grants to Core's sample organizations, and
 * the same Remove Sample Data action takes them away again (ADR-0017, SampleDataModule). The
 * records are built and removed by GrantSampleDataLoader.
 *
 * `@NamespaceAccessible`, public, with a public no-argument constructor, because Core resolves it
 * with `Type.forName` under ADR-0017.
 */
@NamespaceAccessible
public with sharing class FundersSampleData implements SampleDataModule {
	@NamespaceAccessible
	public FundersSampleData() {
		// Built by name from Core (SampleDataModules), so it needs a public constructor.
	}

	public String moduleName() {
		return FundersAccessSync.MODULE_NAME;
	}

	public String countLabel() {
		return System.Label.Funders_SampleData_CountLabel;
	}

	/** The number the status card shows for Funders: sample grants. */
	public Integer countLoaded() {
		return canRead() ? GrantSampleDataLoader.countSampleGrants() : 0;
	}

	/** Whether a sample grant is still here. */
	public Boolean hasSampleRecords() {
		return countLoaded() > 0;
	}

	/**
	 * Whether the user may read what the card asks about. An admin without a Funders set (one
	 * the access sync has not reached yet) sees 0 rather than an error on the card.
	 */
	private static Boolean canRead() {
		return Schema.SObjectType.Grant__c.isAccessible() &&
			Schema.SObjectType.Grant__c.fields.Sample_Data__c.isAccessible();
	}

	/** Starts the Funders load, after Core's organizations and the modules before it. */
	public void enqueueLoad() {
		SampleDataStageBatch.start(new LoadStages());
	}

	/** Starts the Funders removal, before the modules before it and Core's records. */
	public void enqueueRemove() {
		SampleDataRemoveBatch.startRemoval(new RemoveStages());
	}

	/** The load: the grants, in one stage. */
	public class LoadStages implements SampleDataStages {
		public String name() {
			return 'FundersSampleData.LoadStages';
		}

		public Integer stageCount() {
			return 1;
		}

		public void runStage(Integer stage) {
			GrantSampleDataLoader.loadGrants();
		}

		public void finish() {
			SampleDataModules.startAfter(FundersAccessSync.MODULE_NAME);
		}
	}

	/** The removal, one chunk per stage, then on to the module before this one. */
	public class RemoveStages implements SampleDataStages {
		public String name() {
			return 'FundersSampleData.RemoveStages';
		}

		public Integer stageCount() {
			return GrantSampleDataLoader.removeStageCount();
		}

		public void runStage(Integer stage) {
			GrantSampleDataLoader.removeNext();
		}

		public void finish() {
			SampleDataModules.removeAfter(FundersAccessSync.MODULE_NAME);
		}
	}
}
