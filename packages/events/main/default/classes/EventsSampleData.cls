/**
 * The Event Management part of the C-10 sample data set: Core finds this class by name
 * (`SampleDataModules.MODULE_CLASS_NAMES`), so the same Load Sample Data action in BarnCRM
 * Settings fills an org that has Events with a conference under way and a small community event,
 * and the same Remove Sample Data action takes them away again (ADR-0017, SampleDataModule). The
 * records are built and removed by EventSampleDataLoader.
 *
 * `@NamespaceAccessible`, public, with a public no-argument constructor, because Core resolves it
 * with `Type.forName` under ADR-0017.
 */
@NamespaceAccessible
public with sharing class EventsSampleData implements SampleDataModule {
	@NamespaceAccessible
	public EventsSampleData() {
		// Built by name from Core (SampleDataModules), so it needs a public constructor.
	}

	public String moduleName() {
		return EventsPostInstall.MODULE_KEY;
	}

	public String countLabel() {
		return BarnHelp.text('Events', 'Events_SampleData_CountLabel');
	}

	/** The number the status card shows for Events: sample events. */
	public Integer countLoaded() {
		return canRead() ? EventSampleDataLoader.countSampleEvents() : 0;
	}

	/** Whether a sample event is still here. */
	public Boolean hasSampleRecords() {
		return countLoaded() > 0;
	}

	/**
	 * Whether the user may read what the card asks about. An admin without an Events set (one
	 * the access sync has not reached yet) sees 0 rather than an error on the card.
	 */
	private static Boolean canRead() {
		return Schema.SObjectType.Event__c.isAccessible() &&
			Schema.SObjectType.Event__c.fields.Sample_Data__c.isAccessible();
	}

	/** Starts the Events load, after Core's people and organizations and the modules before it. */
	public void enqueueLoad() {
		SampleDataStageBatch.start(new LoadStages());
	}

	/** Starts the Events removal, before the modules before it and Core's records. */
	public void enqueueRemove() {
		SampleDataRemoveBatch.startRemoval(new RemoveStages());
	}

	/** The load: the events and everything under them, in one stage. */
	public class LoadStages implements SampleDataStages {
		public String name() {
			return 'EventsSampleData.LoadStages';
		}

		public Integer stageCount() {
			return 1;
		}

		public void runStage(Integer stage) {
			EventSampleDataLoader.loadEvents();
		}

		public void finish() {
			SampleDataModules.startAfter(EventsPostInstall.MODULE_KEY);
		}
	}

	/** The removal, one chunk per stage, then on to the module before this one. */
	public class RemoveStages implements SampleDataStages {
		public String name() {
			return 'EventsSampleData.RemoveStages';
		}

		public Integer stageCount() {
			return EventSampleDataLoader.removeStageCount();
		}

		public void runStage(Integer stage) {
			EventSampleDataLoader.removeNext();
		}

		public void finish() {
			SampleDataModules.removeAfter(EventsPostInstall.MODULE_KEY);
		}
	}
}
