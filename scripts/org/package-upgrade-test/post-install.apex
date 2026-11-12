// Template for scripts/org/package-upgrade-test.sh: %%NS%% and %%CLASS%% are filled in. Not deployed.
// Used only with --type unlocked. A post-install script runs for managed packages only, so on
// an unlocked install the test runs each package's setup itself, as the installing admin, the
// way Module Manager's Finish Setup does. The steps only add what is missing.
new %%NS%%.%%CLASS%%().runSetup(UserInfo.getUserId());
