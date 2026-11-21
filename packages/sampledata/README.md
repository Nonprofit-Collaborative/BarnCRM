# BarnCRM Sample Data

## Purpose

The sample data set and its loader (ADR-0233 `0233-org-optimizer-and-sample-data-modules.md`,
D-215): 200 households, 440 contacts, 25 organizations, 60 connections and 80 affiliations,
Core's extra sample records, and each installed module's own sample set, loaded and removed
from the Sample Data tab. Optional, in both editions: install it for a scratch org, sandbox or
demo, and uninstall it once the sample records are removed.

## Depends on

- BarnCRM Core

No other module. A module's sample set ships in that module (a `<Module>SampleData` class or
JSON static resource) and runs on Core's sample data framework, so it loads whenever this
package is installed.

## Contents

- Objects: none. The sample records are Core's and the modules' objects, flagged
  `Sample_Data__c`.
- Apex: `SampleDataLoader` (load, remove, status), `SampleDataLoadStages`,
  `SampleDataRemoveStages`, `SampleDataConnections`, `SampleDataSet`, `SampleDataSelector`,
  `SampleDataController`, `SampleDataPackageHost` (Core's `SampleDataHost` seam) and
  `SampleDataPostInstall`.
- LWC: `sampleDataManager` (the Sample Data tab).
- Static resources: `SampleData` (Core's generated set, `scripts/data/generate-sample-data.py`)
  and `CoreSampleData` (Core's extra records, in the generic module format).
- Custom metadata: Setting Definition `Sample_Data` (Settings, General: opens the tab).
- Permission set: `Sample_Data` (BarnCRM Admin holders only; loading and
  removing also need Manage BarnCRM Settings).
- Tab: `Sample_Data`.
- Catalog row: `BarnCRM_Module.SampleData` (Core), both editions.

## Stays in Core

The framework every module's sample set runs on: `SampleDataModules` (load order, the hand-off
between modules, the counts), `SampleDataStageBatch` and `SampleDataRemoveBatch`,
`SampleDataStages`, `SampleDataModule`, `SampleDataFile` (the generic JSON loader) and
`SampleDataException`; the `SampleDataHost` seam; the `Sample_Data__c` and
`Sample_Data_Key__c` fields; and `BarnInstallCheck.loadSampleData`, which says to install this
package when it is missing. The Setup Assistant's Load Sample Data button opens the Sample Data
tab, or says how to get it.
