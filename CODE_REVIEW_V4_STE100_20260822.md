# RPZ Local Processor V4 Patch Review

**Review date:** 2026-08-22

**Input document:** REVIEW_HANDOFF_V4.md

**Review target:** patches/rpz_patch_sigpipe_v4.sh

**Decision:** CONDITIONAL GO

**Language:** ASD-STE100-style English

This document uses short sentences and consistent terms.

This document is not a formal STE compliance certificate.

The iRule code is not in this review.

---

## 1. Executive decision

The V4 runtime design is acceptable.

The V4 patch corrects the 4096-byte SIGPIPE defect.

The V4 patch uses only the tools that exist on BIG-IP.

The V4 patch is much simpler than V3.

The removal of the V3 cleanup command is acceptable.

The removal of the V3 self-test command is acceptable.

The removal of the V3 recovery stage is acceptable.

The ordered file installation is sufficient for the normal deployment path.

The ordered file rollback is sufficient for the normal rollback path.

Do not restore the V3 transaction framework.

Do not deploy V4 to a customer before you close V4-01 through V4-04.

Close V4-05 in the same documentation update.

---

## 2. Decision by item

| Item | Decision | Review result |
|---|---|---|
| SIGPIPE root cause | PASS | The root cause is correct. |
| New file selection function | PASS | The function does not use an early-close pipeline. |
| Embedded payload | PASS | The three MD5 values agree with the reviewed V3 payload. |
| Normal apply | PASS | The LAB test changed all three files to the new versions. |
| Apply failure states | PASS WITH CONDITION | The ordered intermediate states can run. |
| Normal rollback | PASS | The LAB test restored all three original files. |
| Rollback failure states | PASS WITH CONDITION | The ordered intermediate states can run. |
| No handler stop during apply | ACCEPTED WITH CONDITION | The process guard is not a lock. The file order provides the main protection. |
| Active function test | FAIL | The SOP can start two main processes at the same time. |
| State and backup validation | FAIL | V4 accepts some known but unusable file sets. |
| Builder after a commit | FAIL | The builder requires an uncommitted repository state. |
| Project consistency gate | FAIL | The gate checks V3 and returns RC=1. |
| SHA-256 sidecar | PASS | The sidecar is correct when both files are in one directory. |
| SHA-256 handoff command | FAIL | The command uses the wrong current directory. |

---

## 3. Positive results

### 3.1 The runtime patch is small and correct

The patch has 228 lines of tool logic.

The other lines contain the three target files.

The patch changes only these files:

- utils.sh
- parse_rpz.sh
- generate_datagroup.sh

The installation path is a fixed production path.

The patch does not accept a path from an environment variable.

This design is correct for this customer task.

### 3.2 The file replacement method is correct

The patch creates a temporary file in the target directory.

The patch checks the MD5 of the temporary file.

The patch copies the mode and the owner from the target file.

The patch uses mv to replace one target file.

The rename operation is atomic for one file.

The EXIT trap removes an unused temporary file.

The LAB failure tests found no temporary file after a failed mv.

### 3.3 The installation order is correct

The patch installs utils.sh first.

The new utils.sh is compatible with the two original consumer files.

The patch installs parse_rpz.sh second.

The patch installs generate_datagroup.sh last.

The following apply states can run:

| utils.sh | parse_rpz.sh | generate_datagroup.sh | Result |
|---|---|---|---|
| Original | Original | Original | Can run, but has the old defect. |
| New | Original | Original | Can run. |
| New | Original | New | Can run. |
| New | New | Original | Can run. |
| New | New | New | Can run and has the correction. |

The rollback order is the reverse order.

The reverse order also keeps the intermediate states usable.

### 3.4 Failure injection supports the simple design

The reviewer used an isolated LAB directory.

The test did not write to /config.

The reviewer made parse_rpz.sh immutable during apply.

Apply returned RC=1.

The result was new utils.sh and two original consumers.

The state was usable.

The temporary-file count was zero.

The next apply completed the installation.

The reviewer made parse_rpz.sh immutable during rollback.

Rollback returned RC=1.

The result was new utils.sh, new parse_rpz.sh, and original generate_datagroup.sh.

The state was usable.

The next rollback restored all original files.

The reviewer made utils.sh immutable during rollback.

Rollback returned RC=1.

The result was new utils.sh and two original consumers.

The state was usable.

The next rollback restored all original files.

These results support the ordered-state design.

### 3.5 The actual LAB installation is healthy

The patch SHA-256 check returned RC=0 on the LAB device.

The V4 check command returned RC=0.

The installed files have these MD5 values:

| File | MD5 |
|---|---|
| utils.sh | b8294149dc978305e19bcd83fcb650e6 |
| parse_rpz.sh | cefa71b6623632dd51c60a51cdf72196 |
| generate_datagroup.sh | 9599755a54db53652c070cd70ae92652 |

The handler is active.

The handler interval is 300 seconds.

The reviewer did not change the production scripts.

The reviewer removed all review fixtures from the LAB device.

---

## 4. Findings

## V4-01 — High — The function test can run with an active iCall process

### Location

- patches/README.md, lines 63 through 66
- scripts/main.sh, lines 105 through 188
- config/icall_setup_api.sh, lines 59 through 67

### Condition

The SOP gives an active test command:

    bash /config/snmp/RPZ_Local_Processor/scripts/main.sh --force

The SOP does not stop the periodic handler before this command.

The main script does not have a process lock.

The periodic handler can start main.sh at the same time.

Two main processes can write raw files, parsed files, final files, and DataGroups.

The active test can therefore add a new race during deployment.

The passive option also has an incorrect time statement.

The handler starts at intervals of 300 seconds.

An iCall start does not always perform an RPZ update.

The script stops when the SOA serial did not change.

The source data can have a change interval of 10 to 80 minutes.

Thus, 300 seconds is not a maximum time for a full passive test.

### Effect

The active test can overlap with a scheduled run.

The passive test can finish without testing the corrected code path.

The operator can accept a deployment without a valid end-to-end result.

### Required change

Change the active test procedure.

Use this sequence:

1. Set rpz_processor_handler to inactive.
2. Wait until pgrep does not show an RPZ process.
3. Run main.sh with the force option.
4. Record the command exit status.
5. Check the final files.
6. Check the DataGroup revision and size.
7. Set rpz_processor_handler to active.
8. Run tmsh save sys config.
9. Check the handler status and interval.

Restore the handler for a successful test.

Restore the handler for a failed test.

Do not leave the device with an inactive handler.

If you keep the passive option, change its acceptance rule.

Wait for a real processing event.

Do not use one handler interval as the maximum wait time.

### Acceptance test

The active test must start with an inactive handler.

No other RPZ process can run during the active test.

The test must show RC=0.

The final-file time must change.

The DataGroup revision must increase.

The handler must finish in the active state.

The handler interval must be 300 seconds.

---

## V4-02 — Medium — Rollback can report success for an unusable file set

### Location

- patches/rpz_patch_sigpipe_v4.sh, lines 98 through 120
- patches/rpz_patch_sigpipe_v4.sh, lines 123 through 168
- patches/rpz_patch_sigpipe_v4.sh, lines 170 through 197

### Condition

The V4 state model checks each file independently.

The state model accepts each known original or new MD5 value.

The state model does not check the provider dependency.

utils.sh is the provider file.

parse_rpz.sh and generate_datagroup.sh are the consumer files.

The new consumer files require the new find_newest_file function.

The function exists only in the new utils.sh.

Thus, these file sets cannot run:

| utils.sh | parse_rpz.sh | generate_datagroup.sh |
|---|---|---|
| Original | New | Original |
| Original | Original | New |
| Original | New | New |

The reviewer created the first file set in an isolated LAB directory.

The V4 check command returned RC=0.

The check command reported a partial installation.

parse_rpz.sh returned RC=1.

The log contained this message:

    find_newest_file: command not found

The reviewer then used apply to repair the file set.

Apply saved the unusable file set in a backup directory.

Rollback accepted this backup.

Rollback returned RC=0.

Rollback printed a completion message.

parse_rpz.sh returned RC=1 after the rollback.

### Effect

The check command can report success for an unusable state.

Rollback can report success after it restores an unusable state.

A wrong backup selection can also restore only part of the correction.

The original SIGPIPE defect can then return.

### Required change

Keep the simple ordered replacement design.

Add one dependency rule:

> If a consumer is new, utils.sh must be new.

Apply this rule in the check command.

Apply this rule before apply changes a file.

Apply this rule to all backup files before rollback changes a file.

For the current customer rollout, use the simplest rollback rule:

> A rollback backup must contain three original V1.2 files.

Reject a mixed backup before the first target file changes.

After rollback, require three original MD5 values.

Return a non-zero status for any other final state.

Do not add the V3 recovery-stage framework.

### Acceptance test

Test all eight original/new file combinations.

The five usable combinations must return a normal check result.

The three new-consumer and original-utils combinations must not return a normal check result.

Rollback must reject a mixed backup before it changes a target file.

Rollback to a pure original backup must return RC=0.

---

## V4-03 — Medium — The builder cannot run after the source commit

### Location

- patches/build_patch_v4.sh, lines 12 through 31

### Condition

The builder reads the original files from Git HEAD.

The current HEAD contains the original V1.2 files.

The working tree contains the new files.

This condition exists only before the source commit.

The reviewer created a clean temporary repository.

The temporary HEAD contained the three new source files.

The builder returned RC=1.

The first error was:

    HEAD utils.sh md5=b8294149dc978305e19bcd83fcb650e6

The builder expected the original MD5 value.

Thus, the builder cannot rebuild V4 from the release commit.

### Effect

The deterministic-build statement is true only in the current uncommitted state.

A future engineer cannot rebuild the patch from a clean release checkout.

### Required change

Do not use the moving HEAD name as the original-source location.

Use one of these simple methods:

1. Use the reviewed original MD5 constants directly.
2. Use one fixed baseline commit ID for the original files.

Keep the three checks for the new working-tree files.

Build the patch from the committed new source files.

Run the builder in a clean checkout of the release commit.

The output SHA-256 must be stable.

### Acceptance test

Commit the new source files in a temporary repository.

Run the builder from that clean commit.

The builder must return RC=0.

The output SHA-256 must agree with the release value.

---

## V4-04 — Medium — The project gate checks V3 and fails the V4 tree

### Location

- tests/check_source_consistency.sh, lines 19 through 21
- tests/check_source_consistency.sh, lines 67 through 109
- tests/check_source_consistency.sh, lines 111 through 119

### Condition

The project gate sets PATCH to rpz_patch_sigpipe_v3.sh.

The embedded-payload PASS results refer to V3.

The MD5-table PASS results refer to V3.

The gate does not validate the V4 artifact.

The patches directory contains V3 and V4.

The gate requires one patch file.

The reviewer ran the gate.

The result was PASS=24 and FAIL=1.

The command returned RC=1.

### Effect

The project gate is not a valid V4 release gate.

The PASS output can give a wrong assurance about V4.

The release tree cannot meet its own consistency condition.

### Required change

Make V4 the current patch in the gate.

Use the V4 embed delimiter and V4 MD5 table format.

Alternatively, call build_patch_v4.sh from the gate.

Move V3 to an archive path that is not an active-patch path.

You can also change the gate to ignore an explicit archive path.

Keep V3 as review evidence.

Do not count V3 as a current deployment patch.

### Acceptance test

Run tests/check_source_consistency.sh from the repository root.

The command must validate V4.

The command must return RC=0.

The output must not identify V3 as the current patch.

---

## V4-05 — Low — The handoff SHA-256 command uses the wrong current directory

### Location

- REVIEW_HANDOFF_V4.md, lines 36 through 40
- patches/rpz_patch_sigpipe_v4.sh.sha256, line 1

### Condition

The sidecar contains only the patch base name.

The handoff runs this command from the repository root:

    shasum -a 256 -c patches/rpz_patch_sigpipe_v4.sh.sha256

The checksum tool searches for the patch in the repository root.

The patch is in the patches directory.

The reviewer ran the command.

The command returned RC=1.

The same command returned RC=0 in the patches directory.

The device command also returned RC=0 in /var/tmp.

### Effect

An engineer can get a false checksum failure.

### Required change

Use this repository command:

    cd patches
    shasum -a 256 -c rpz_patch_sigpipe_v4.sh.sha256

Also state that the patch and sidecar must be in the same directory.

Keep the sidecar base-name format.

This format is correct for the device upload.

### Acceptance test

Run the documented workstation command.

The command must return RC=0.

Run the documented device command.

The command must return RC=0.

---

## 5. Review answers

### Question 1: Does the 228-line tool logic have a missing failure path?

Yes.

The state model does not enforce the provider dependency.

Rollback can accept a backup that has an unusable file set.

See V4-02.

The normal ordered failure paths are acceptable.

The LAB fault-injection tests support this result.

### Question 2: Is deployment without a handler stop acceptable?

It is acceptable for apply and rollback, with a stated limit.

The pgrep check is a best-effort check.

The pgrep check is not a process lock.

The handler can start after pgrep returns.

The ordered atomic replacements prevent a new persistent failure.

One process can still use an old consumer during the short change period.

That process can have the old SIGPIPE failure one more time.

Document this limit.

Do not use an active force test while the handler is active.

See V4-01.

### Question 3: Can file order replace a multi-file transaction?

Yes, for this patch and the normal state sequence.

The provider change is backward compatible.

The installation order is correct.

The rollback order is correct.

The fault-injection tests show usable intermediate states.

V4 must also enforce the dependency rule in V4-02.

No V3 recovery stage is necessary.

### Question 4: Is the README SOP sufficient?

No.

The function-test procedure can cause concurrent main processes.

The passive-test time statement is not correct.

The workstation checksum step does not state its current-directory condition.

See V4-01 and V4-05.

### Question 5: Is the builder verification chain sufficient?

No.

The builder cannot run after the new source files are in HEAD.

The project gate still checks V3.

The project gate currently returns RC=1.

See V4-03 and V4-04.

---

## 6. Accepted limits

The following limits do not block V4:

- V4 does not clean old temporary files.
- Phase 1B owns the retention policy.
- V4 does not add a full process lock.
- V4 does not add a multi-file transaction.
- V4 does not include a self-test command.
- V4 keeps backups in /var/tmp.
- The pgrep check can have a time-of-check race.
- One administrator must run one patch command at a time.

The exact 4096-byte SIGPIPE defect cannot occur in the three corrected call sites.

Another future failure can still stop the normal cleanup function.

Do not describe V4 as a complete disk-life-cycle correction.

---

## 7. Recommended external regression test

Keep the production patch small.

Do not put the 16-test matrix back into the patch.

Put the V4 tool tests in a separate LAB test file.

The test file must not use /config as its target.

The test file should cover these cases:

1. Original check.
2. Normal apply.
3. Repeat apply.
4. Failure at each apply file.
5. Resume after each apply failure.
6. Normal rollback.
7. Failure at each rollback file.
8. Resume after each rollback failure.
9. All eight original/new state combinations.
10. Pure-original backup validation.
11. Mixed-backup rejection.
12. Temporary-file cleanup.

This test does not increase the production patch size.

This test makes future V4 changes repeatable.

---

## 8. Release conditions

Complete these actions before customer deployment:

1. Correct the active and passive test steps in the SOP.
2. Add the provider dependency rule.
3. Reject a mixed rollback backup before file replacement.
4. Make the builder work from a clean release commit.
5. Make the project gate validate V4 and return RC=0.
6. Correct the workstation SHA-256 command.
7. Rebuild V4.
8. Calculate a new SHA-256 value if the artifact changes.
9. Run the V4 LAB matrix again.
10. Run one controlled end-to-end test with an inactive handler.
11. Restore the handler to active.
12. Save the BIG-IP configuration.
13. Confirm the final files and the DataGroup revision.
14. Update REVIEW_HANDOFF_V4.md with the final evidence.

---

## 9. Final statement

V4 is the correct direction.

The core patch is correct.

The simpler ordered-state design is acceptable.

The current artifact is not ready for an unconditional customer rollout.

Close the four release findings.

Close the checksum documentation finding.

Then use one device as the canary.

The final decision is CONDITIONAL GO.
