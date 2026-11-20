// Anonymous Apex run by scripts/org/seed-sample-data.sh. Starts the C-10 sample data
// load in the BarnCRM Sample Data package; the loader runs as Batch Apex, so this call
// returns immediately.
// See docs/admin-guide/sample-data.md and data/sample/README.md.
SampleDataLoader.load();
