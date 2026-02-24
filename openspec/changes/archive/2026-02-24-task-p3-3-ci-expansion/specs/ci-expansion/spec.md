# ci-expansion Specification Delta

### Requirement: CI lane separation
- The system SHALL separate CI into lint, test, and release-sanity lanes.

#### Scenario: CI run decomposition
- GIVEN a push or pull request
- WHEN CI runs
- THEN lint, test, and release-sanity execute as separate jobs with clear labels.

### Requirement: Regression harness in CI test lane
- The system SHALL run shell regression tests in the CI test lane.

#### Scenario: Test lane execution
- GIVEN CI test job
- WHEN it runs
- THEN `./tests/run.sh` is executed and failures fail the job.

### Requirement: Isolated installer sanity validation
- The system SHALL validate installer and uninstaller flows using isolated paths in CI.

#### Scenario: Release-sanity installer flow
- GIVEN CI release-sanity job
- WHEN install/uninstall scripts run with env-overridden temp paths
- THEN install creates runnable command symlink and uninstall removes it.
