# RPZ Local Processor Phase 1B Review, Round 2

**Review date:** 2026-08-23

**Reviewed handoff:** `REVIEW_HANDOFF_PHASE1B.md`

**Reviewed handoff SHA-256:**
`dba1f933c4c3bd71cdc9941703c3ad42770ef9c2f6a222a5a6fd082cf32c7148`

**Reviewed production patch:** `patches/rpz_patch_phase1b_v1.sh`

**Reviewed patch SHA-256:**
`bd42e9b35e34f3fd5012aa139bf963e8273bf848e2f0642a68305d94ae433aa6`

**Overall decision:** CONDITIONAL GO

**Current patch artifact for a customer canary:** HOLD

**Controlled e2e driver:** NO-GO

**Version 1.2.2 package:** NO-GO and HOLD

**CR-10:** Phase 2 P0. It does not block Phase 1B by itself.

**Language:** ASD-STE100-style English

This document uses short sentences and consistent terms.

This document is not a formal STE compliance certificate.

The iRule code is not in this review.

---

## 1. Executive decision

The Phase 1B design is still correct for the reported disk-growth problem.

The patch limits the normal temporary-file families.

The patch keeps `final/` outside the cleanup scope.

The EXIT trap works on the tested success, NO_UPDATE, and failure paths.

The patch keeps the tested main-process exit status.

The patch builder is deterministic.

The patch sidecar is correct.

The project gate returns `PASS=31 FAIL=0`.

The reviewer reproduced the updated LAB regression result:

```text
PASS=104 FAIL=0
RC=0
```

P1B-02 is closed.

The original unsafe-character part of P1B-03 is closed.

P1B-04 is closed.

P1B-05 and P1B-06 remain in the package HOLD scope.

That HOLD decision is acceptable.

The version 1.2.2 package is still not deployable.

P1B-01 is only partially closed.

The new e2e driver has effective LAB identity guards.

However, the driver does not check all synthetic-file operations.

A failed `touch -d` can again leave a new 0-byte file in the real data tree.

This condition can reproduce the cause of the first e2e incident.

P1B-07 is not fully closed.

Several current documents still contain old source code, old line counts, or old test results.

This review adds one new payload finding.

P1B-08 is a Medium finding.

Two valid family names can have a prefix relationship.

For example, `alpha` and `alpha_beta` are both accepted names.

The pattern `alpha_*.txt` also selects `alpha_beta_*.txt`.

The reviewer reproduced this condition on BIG-IP 17.1.3.1.

The cleanup kept zero `alpha` files and 24 `alpha_beta` files.

This result violates the per-family KEEP rule.

The current known LAB families do not have this relationship.

Thus, the current LAB service is not affected by P1B-08.

The general patch logic is affected.

Do not use the current patch SHA-256 for a customer canary.

Make the small corrections in Section 9.

Then rebuild the patch and run the focused tests in Section 10.

Do not add a transaction framework.

Do not add another language runtime.

Do not add CR-10 to the Phase 1B patch.

---

## 2. Finding disposition

| Finding | Round 2 status | Result |
|---|---|---|
| P1B-01 | OPEN, severity reduced to Medium | The LAB identity guards work. The synthetic-file operations and cleanup are not fully fail-closed. |
| P1B-02 | CLOSED | Values outside `1-99999` fall back before Bash arithmetic. The 36-digit test passes. |
| P1B-03 | CLOSED for the original condition | The `A-Za-z0-9._-` rule blocks the tested glob metacharacters. P1B-08 covers a different valid-prefix ambiguity. |
| P1B-04 | CLOSED | Count deletion failures and age deletion failures produce WARN messages. The reported counts are accurate. |
| P1B-05 | ACCEPTED HOLD | The installer still rejects 1.2.2. The package remains NO-GO. This does not block patch-only work. |
| P1B-06 | ACCEPTED HOLD | The current package still has macOS xattr headers. The package remains NO-GO. |
| P1B-07 | OPEN, Low | The permanent tests are present. Some current documents are still inconsistent. |
| P1B-08 | NEW, Medium | A valid family prefix can select and delete files from another valid family. |

No Critical finding is open in the Phase 1B payload.

No High finding is open in the Phase 1B payload.

P1B-08 must close before the general patch release.

P1B-01 must close before the e2e driver is used as an acceptance gate.

P1B-07 must close before final handoff.

---

## 3. Independent artifact evidence

### 3.1 Identity values

The handoff values agree with the reviewed files.

| File | Identity | Lines |
|---|---|---:|
| `REVIEW_HANDOFF_PHASE1B.md` | SHA-256 `dba1f933c4c3bd71cdc9941703c3ad42770ef9c2f6a222a5a6fd082cf32c7148` | 131 |
| `patches/rpz_patch_phase1b_v1.sh` | MD5 `69866163e2059036ecf4f538d680fb76` | 585 |
| `patches/rpz_patch_phase1b_v1.sh` | SHA-256 `bd42e9b35e34f3fd5012aa139bf963e8273bf848e2f0642a68305d94ae433aa6` | 585 |
| `patches/build_patch_phase1b.sh` | MD5 `39ed1950640adc0544352c1d6da256e9` | 303 |
| `scripts/main.sh` | MD5 `0835f71bda78b8ae870d93bae8e82055` | 347 |
| `tests/lab/f5_patch_1b_test.sh` | MD5 `fa780dbef3b7836f3a9c734410216b71` | 351 |
| `tests/lab/f5_e2e_1b_controlled.sh` | MD5 `3bae3175bd09b235241a9e9b07caae73` | 143 |

The Phase 1B sidecar returned RC=0.

The extracted embedded `main.sh` is byte-for-byte equal to `scripts/main.sh`.

The reviewed shell files passed `bash -n`.

### 3.2 Deterministic build

The reviewer made a clean temporary tree.

The tree contained only these required inputs:

- `scripts/main.sh`
- `patches/build_patch_phase1b.sh`

The builder returned RC=0.

The builder reported:

```text
PASS: bash -n
PASS: round-trip
PASS: no placeholder remains
Total lines: 585
Embedded lines: 351
Tool logic lines: 234
SHA-256: bd42e9b35e34f3fd5012aa139bf963e8273bf848e2f0642a68305d94ae433aa6
```

The generated patch was byte-for-byte equal to the reviewed patch.

The generated sidecar was byte-for-byte equal to the reviewed sidecar.

### 3.3 Project gate

The reviewer ran `tests/check_source_consistency.sh`.

The result was:

```text
PASS=31
FAIL=0
RC=0
```

The gate confirmed the Phase 1B embedded payload.

The gate confirmed the Phase 1B MD5 table.

The gate confirmed the Phase 1B sidecar.

The gate also confirmed package content consistency.

The package consistency result is not an installability result.

### 3.4 Package HOLD

The reviewed package is:

```text
dist/rpz_local_processor_v1.2.2_20260823_014255.tar.gz
SHA-256: 783514f9c358e2559f13924b0003dd48135cb54d045ab00b82480e83e6ce5cd4
```

The outer sidecar returned RC=0.

The installer still contains:

```text
SUPPORTED_VERSIONS="1.2.1"
```

The package version is 1.2.2.

The package therefore still fails P1B-05.

The raw archive still contains these headers:

```text
SCHILY.xattr.com.apple.provenance
LIBARCHIVE.xattr.com.apple.provenance
```

The package therefore still fails P1B-06.

`dist/DO_NOT_DEPLOY.md` clearly marks the package as HOLD.

This disposition satisfies the round 1 option to keep the package out of scope.

Do not deploy this package.

---

## 4. Independent LAB evidence

### 4.1 Environment and initial state

The reviewer used the configured LAB device at `10.8.34.223`.

The LAB hostname was:

```text
cdns.ryantseng.work
```

The LAB Bash version was:

```text
GNU bash, version 4.2.46(2)-release
```

The LAB `main.sh` MD5 was:

```text
0835f71bda78b8ae870d93bae8e82055
```

The LAB patch files had the same SHA-256 values as the reviewed local files.

The V4 patch check returned RC=0.

The Phase 1B patch check returned RC=0.

The handler was active with interval 300.

The `rpztw` DataGroup had revision 22 and size 2,243,094 bytes.

### 4.2 Updated regression

The reviewer ran the current `f5_patch_1b_test.sh` on the LAB device.

The test used its `/var/tmp/rpz_1b_test` fixture.

It did not use the real `/config` data tree.

The result was:

```text
PASS=104
FAIL=0
RC=0
```

The result confirms these corrections:

- KEEP input boundaries
- unsafe glob-character rejection
- count-delete failure reporting
- age-delete failure reporting
- failure-path cleanup
- NO_UPDATE cleanup
- `--no-cleanup` behavior
- fixture `LOG_FILE` use

### 4.3 E2E refusal paths

The reviewer ran three no-change refusal cases on the LAB device.

The results were:

```text
no --lab-only: RC=2
missing E2E_CONFIRM: RC=2
wrong E2E_CONFIRM: RC=2
```

The handler state did not change.

The DataGroup revision remained 22.

This evidence confirms the new argument and confirmation guards.

The source code also has an exact hostname guard.

The successful destructive e2e was not repeated in this review.

The handoff already contains a normal-path `PASS=20 FAIL=0` result.

The current driver has an open failure-path defect.

The payload also needs a new build for P1B-08.

Another successful run of the current artifact would not test either open defect.

### 4.4 New prefix-overlap test

The reviewer made a new fixture under `/var/tmp`.

The fixture did not use the real `/config` data tree.

The fixture contained:

- 30 files in family `alpha`
- 30 files in family `alpha_beta`
- one `final/` sentinel

Both prefixes satisfy the new safe-character rule.

The reviewer called the reviewed cleanup function with KEEP=24.

The observed result was:

```text
[INFO] Count cleanup: parsed/alpha_*.txt deleted 36 files and kept 24 files
RC=0
alpha=0
alpha_beta=24
total parsed files=24
final sentinel present=yes
```

The log language on the LAB device was Chinese.

The values above are an English description of that output.

The exact LAB output included:

```text
OVERLAP_RC=0 ALPHA=0 ALPHA_BETA=24 TOTAL=24 FINAL_SENTINEL_RC=0
```

This test proves P1B-08.

### 4.5 Final LAB state

The reviewer removed all review-owned temporary files.

The final checks returned:

```text
V4 check RC=0
Phase 1B check RC=0
handler status=active
handler interval=300
rpztw revision=22
rpztw size=2243094
/config use=7%
raw count=16
rpztw parsed count=16
phishtw parsed count=16
rpzip parsed count=16
review temporary files=0
```

The new overlap test did not change the real DataGroup tree.

---

## 5. Payload assessment

### 5.1 Cleanup scope

Result: PASS.

The age cleanup enters only `raw/` and `parsed/`.

It uses `-maxdepth 1`.

It does not enter `final/`.

The final sentinel passed all fixture tests.

### 5.2 KEEP validation

Result: PASS.

The new expression is:

```bash
^[1-9][0-9]{0,4}$
```

The code applies this expression before Bash arithmetic.

The accepted numeric range is 1 through 99999.

Values 0 and 100000 fall back to 24.

A 36-digit value also falls back to 24.

This change closes the arithmetic-overflow path in P1B-02.

### 5.3 Delete-error reporting

Result: PASS.

The count cleanup records successful and failed deletions separately.

It gives a WARN message when one or more deletions fail.

It does not claim that the retained count is 24 after a failed deletion.

The age cleanup also gives a WARN message when `find -delete` fails.

The cleanup remains nonfatal to the main RPZ process.

This behavior is correct for this maintenance patch.

### 5.4 EXIT trap

Result: PASS.

The trap saves `$?` before cleanup.

The trap calls cleanup only once.

The trap returns the saved status.

The updated tests cover these main-process paths:

- processing failure with cleanup
- processing failure with `--no-cleanup`
- NO_UPDATE with cleanup
- NO_UPDATE with `--no-cleanup`
- successful real processing in the handoff e2e

The tested exit-status behavior is correct.

The trap cannot run after SIGKILL or OOM termination.

That condition is a documented shell limitation.

It is not a new finding.

### 5.5 Cleanup log volume

Result: PASS.

An idle cleanup gives no output when it has no work.

A cleanup with deletions gives a summary.

A cleanup with a deletion failure gives a WARN message.

This behavior is suitable for a 300-second handler interval.

### 5.6 Family selection

Result: FAIL.

The metacharacter restriction is useful.

It does not make a broad family glob exact.

P1B-08 gives the details.

---

## 6. P1B-01 — Medium — The e2e driver is not fully fail-closed

### Status from round 1

The dangerous host-selection part is corrected.

The following controls are present:

- exact `--lab-only` argument
- exact LAB hostname
- exact confirmation string
- initial handler active/300 check
- inactive-state check
- quiet-process check
- apply gate
- revision and final-file checks
- final handler and save checks
- a synthetic-file manifest

These changes reduce the severity from High to Medium.

The complete finding is not closed.

### Location

- `tests/lab/f5_e2e_1b_controlled.sh`, lines 19 through 54
- `tests/lab/f5_e2e_1b_controlled.sh`, lines 75 through 107
- `tests/lab/f5_e2e_1b_controlled.sh`, lines 118 through 138

### Condition

The script enables only `set -u`.

It does not enable `set -e` or `pipefail`.

This choice is acceptable only when each important command has an explicit check.

The synthetic-file loop does not check file creation.

It does not check `touch -d`.

The manifest entry is added after the unchecked `touch` command.

If `touch -d` fails, the script continues.

The 0-byte file then has a new mtime.

The pipeline can select that file as its input.

This is the same unsafe input condition as the first e2e incident.

The line `ok "seeded ..."` uses the manifest array length.

It does not count the files that exist.

Thus, 120 failed writes can still produce a seed PASS message.

The family checks accept any value at or below 24.

Zero files therefore pass the family-count check.

The test can miss a cleanup implementation that deletes a complete family.

The explicit manifest cleanup does not check each `rm` command.

The code clears the manifest even when one or more files remain.

The EXIT trap then cannot retry those file paths.

The EXIT trap also ignores handler-restore and save failures.

The normal path checks those operations before PASS.

The abnormal path has no equivalent result message.

### Effect

The driver can report a false seed PASS.

The driver can expose the LAB again to a new 0-byte synthetic input.

The driver can accept zero retained files.

The driver can leave a synthetic file after a cleanup failure.

This is a test-driver defect.

It is not a defect in the production patch target selection.

### Required change

Keep the current four LAB identity guards.

Make these focused changes:

1. Refuse to overwrite a pre-existing synthetic-file path.
2. Check each file-creation command.
3. Add the new path to the manifest immediately after creation.
4. Check each `touch -d` command.
5. Verify that all 120 synthetic files exist before `main.sh` starts.
6. Verify that their mtimes are older than the real input candidate.
7. Capture patch `check` output and RC separately.
8. Require `check RC=0` before the text check.
9. Require exactly 24 files in each seeded family after cleanup.
10. Do not accept zero as a successful seeded-family result.
11. Check each manifest removal.
12. Clear the manifest only when no listed file remains.
13. Report a handler-restore or save failure from the EXIT path.

Do not add a general test framework.

Do not add a bypass flag.

### Acceptance test

Repeat all five refusal cases.

Verify that each refusal returns RC=2 before a real data-tree change.

Add one safe failure-injection test for a synthetic-file operation.

The failure-injection result must be:

- nonzero driver RC
- handler active/300 at exit
- configuration save attempted and verified
- DataGroup revision unchanged
- no review-owned synthetic file left

Then run one successful controlled e2e test with the rebuilt patch.

Require exactly 24 files in each seeded family.

---

## 7. P1B-07 — Low — The current records are not internally consistent

### Location

- `REVIEW_HANDOFF_PHASE1B.md`, lines 56 through 84
- `REVIEW_HANDOFF_PHASE1B.md`, lines 112 through 130
- `docs/PHASE1B_DESIGN_20260823.md`, lines 48 through 135
- `docs/PHASE1B_DESIGN_20260823.md`, Section 8
- `patches/README.md`, lines 214 through 270
- `STATUS_20260822.md`, lines 239 through 250
- `STATUS_20260822.md`, Section 11
- `tests/lab/f5_patch_1b_test.sh`, lines 3 through 5
- `process.md`, Section 23.4

### Condition

The handoff artifact table correctly says that `main.sh` has 347 lines.

The next section says that the revised file has 323 lines.

The handoff test section still reports `PASS=66 FAIL=0`.

It also still reports e2e `PASS=5 FAIL=0`.

The current results are 104 and 20.

The handoff asks about 67 added lines.

The current file changed from 256 to 347 lines.

The handoff reading order points only to process Section 22.

The response evidence is in process Section 23.

The design status at the top is current.

However, the design code samples are from the prior implementation.

The KEEP sample still accepts an unlimited digit count.

The prune sample still suppresses `rm` failures.

The prune sample does not contain the safe-prefix check.

The age-cleanup sample still suppresses `find` failures.

Design Section 8 still says that confirmation is pending.

The patch README calls 403 MB a hard limit.

It is only an estimate.

File sizes, zone count, and input volume can change it.

The status file says that Phase 1B is complete near the top.

The same file later says that implementation has not started.

The regression script header still says F1-F7 and T1-T2.

The current test has F1-F11 and T1-T4.

Process Section 23.4 says that the canary is unlocked.

This round found P1B-08 and a remaining P1B-01 condition.

That statement is no longer current.

### Effect

A maintainer can copy obsolete code from the design document.

A reviewer can select old evidence from the handoff.

An operator can treat an estimate as a guaranteed disk limit.

These errors do not change the current runtime artifact.

### Required change

Update the handoff to the new artifact after P1B-08 closes.

Use the new line count, MD5, and SHA-256 values.

Use the new regression and e2e results.

Make the design code samples equal to the final implementation.

Change Design Section 8 from pending questions to recorded decisions.

Change `hard limit` to `estimate` in all current operational documents.

Mark old results in process Section 22 as historical results.

Update process Section 23 with this review response.

Update the status file and remove the contradictory pending sections.

Update the regression script header.

Do not rewrite valid historical incident evidence.

---

## 8. P1B-08 — Medium — Valid family prefixes can overlap

### Location

- `scripts/main.sh`, lines 86 through 135
- the embedded `main.sh` in `patches/rpz_patch_phase1b_v1.sh`
- `tests/lab/f5_patch_1b_test.sh`, F9 and the missing overlap case

### Condition

The code extracts each family prefix from a valid timestamped file name.

The code accepts these prefix characters:

```text
A-Z a-z 0-9 . _ -
```

The code then sends this pattern to `prune_by_count`:

```bash
"${prefix}_*.txt"
```

The asterisk can match another valid prefix component.

For example:

```text
alpha_20260801_000001.txt
alpha_beta_20260801_000001.txt
```

For family `alpha`, the pattern `alpha_*.txt` selects both files.

The safe-character rule does not prevent this condition.

F9 tests `*`, `?`, and `[` in the prefix.

F9 does not test one valid prefix that contains another valid prefix.

### Reproduction

The reviewer used Bash 4.2 on the LAB device.

The reviewer created 30 `alpha` files and 30 `alpha_beta` files.

All files had the required timestamp form.

The reviewer ran cleanup with KEEP=24.

The result was:

```text
cleanup RC=0
alpha=0
alpha_beta=24
```

The cleanup log said that `alpha_*.txt` deleted 36 files.

This result is deterministic for the tested names.

### Effect

The cleanup can delete the complete retained history of one family.

The cleanup can delete files from another valid family.

The log can identify the wrong family selector.

The `final/` files are not deleted.

The next parse run can create new parsed files.

Thus, this condition does not directly publish an empty DataGroup.

It still violates the Phase 1B retention contract.

The current known LAB families are:

```text
rpztw
phishtw
rpzip
```

These names do not overlap.

The four customer devices were not checked in this review.

### Required change

Use an exact timestamp-shaped pattern for each family.

Do not use a broad `prefix_*.txt` selector.

A minimal correction is suitable.

For example, use a reusable timestamp glob that has exactly 8 date digits and 6 time digits.

The parsed selector must have this form:

```text
<literal-prefix>_[0-9]{8}_[0-9]{6}.txt
```

In Bash glob syntax, write each digit position explicitly.

Keep the prefix validation.

Also tighten the raw selector to its exact generated filename shape.

Do not read `zonelist.txt` in cleanup.

Do not add a parser framework.

### Required regression

Add a new permanent test.

Use at least these valid families:

```text
alpha
alpha_beta
```

Create 30 files in each family.

Run cleanup with KEEP=24.

Require these results:

```text
alpha=24
alpha_beta=24
```

Require the newest file in each family to remain.

Require the oldest excess file in each family to be absent.

Require `final/` to remain unchanged.

The test must fail against the current reviewed SHA-256 value.

The test must pass against the rebuilt value.

---

## 9. Required correction set

Use this order.

### 9.1 Correct the family selector

Close P1B-08 first.

Make the family pattern exact for the generated timestamp format.

Add the prefix-overlap regression.

Run the complete fixture regression.

### 9.2 Complete the e2e fail-closed behavior

Keep all current identity guards.

Gate every synthetic-file state change.

Track a created path before a later metadata operation can fail.

Require exact post-cleanup family counts.

Do not clear a manifest that still has existing files.

Add one safe failure-path test.

### 9.3 Update current records

Close P1B-07 after the source and tests are final.

Do not calculate final hashes before the last source change.

Do not describe the current reviewed SHA-256 as approved for canary.

### 9.4 Rebuild once

Run `build_patch_phase1b.sh` after all payload changes.

Update the sidecar.

Update all embedded MD5 values.

Report the new line counts and identity values.

### 9.5 Keep excluded work excluded

Do not change V4 payload files for these findings.

Do not rerun the 4096 failure curve.

Do not add CR-10 to Phase 1B.

Do not repair package 1.2.2 unless the package HOLD decision changes.

---

## 10. Required verification for round 3

### 10.1 Local checks

Run syntax checks on all changed shell files.

Run the Phase 1B sidecar check from the `patches` directory.

Extract the embedded `main.sh`.

Compare it byte-for-byte with `scripts/main.sh`.

Rebuild in a clean temporary tree.

Require byte-for-byte equality with the submitted patch.

Run the project gate.

Report PASS, FAIL, and RC.

### 10.2 LAB fixture regression

Run the complete updated `f5_patch_1b_test.sh` on BIG-IP Bash 4.2.

Report the new assertion count.

Require FAIL=0 and RC=0.

Include the new valid-prefix overlap case.

Keep all existing F8 through F11 tests.

Keep T3 and T4.

### 10.3 E2E driver negative checks

Repeat these refusal cases:

- missing `--lab-only`
- wrong hostname
- missing confirmation
- wrong confirmation
- handler not initially active/300

Verify no `/config` data change for each case.

Run one safe synthetic-operation failure case.

Verify restoration and cleanup after that failure.

### 10.4 Successful controlled e2e

Run one successful controlled e2e only after the patch is rebuilt.

Record these values:

- patch SHA-256
- patch apply RC
- patch check RC
- main RC
- exact count for each seeded family
- final file size and mtime before and after
- DataGroup revision and size before and after
- expected diagnostic lines
- handler state before and after
- configuration-save result
- synthetic-file cleanup result

Require exactly 24 files in each seeded family.

### 10.5 Final state

Remove only review-owned fixture files.

Confirm V4 check RC=0.

Confirm Phase 1B check RC=0.

Confirm handler active/300.

Confirm a normal DataGroup size and revision.

Confirm no review-owned temporary file remains.

---

## 11. Canary decision

The current patch SHA-256 is not approved for a customer canary.

The required payload correction is small.

It is safer to rebuild before the first customer device.

After P1B-01, P1B-07, and P1B-08 close, the patch can return for a short confirmation review.

If that review passes, use one customer device as the canary.

Use this operational order:

1. Verify the exact V4 patch SHA-256.
2. Verify the exact Phase 1B patch SHA-256.
3. Run V4 `check` on that customer device.
4. Run Phase 1B `check` on that customer device.
5. Stop the handler.
6. Wait for the RPZ process to become quiet.
7. Apply and verify V4.
8. Apply and verify Phase 1B.
9. Run the controlled real-data acceptance sequence.
10. Restore handler active/300.
11. Save the system configuration.
12. Observe at least one later handler tick.
13. Confirm bounded file counts and no cleanup WARN message.

Do not use the version 1.2.2 package for this canary.

Do not deploy all customer devices at the same time.

---

## 12. Answers to the handoff questions

### Question 1

The production `main.sh` failure paths are adequately covered for this scope.

The e2e driver still has unchecked state-change paths.

P1B-08 is a separate family-selection defect.

### Question 2

The reviewed EXIT trap keeps the tested main-process exit status.

The ERR trap does not change that result in the tested paths.

No additional trap framework is necessary.

### Question 3

The quiet cleanup behavior is acceptable.

Cleanup on a NO_UPDATE tick is also acceptable.

A real deletion failure must continue to produce a WARN message.

### Question 4

The first e2e incident does not make Phase 1B incorrect by itself.

It proves that CR-10 must be Phase 2 P0.

It also makes strict e2e failure checks necessary.

CR-10 must remain separate from this minimal patch.

---

## 13. Final conclusion

The main Phase 1B approach is suitable for the F5 shell environment.

The solution does not need a larger framework.

The second implementation closes the overflow and delete-reporting defects.

The new LAB guards substantially improve the destructive test.

Two focused technical corrections remain.

One record correction also remains.

Close P1B-01.

Close P1B-07.

Close P1B-08.

Keep package 1.2.2 on HOLD.

Keep CR-10 as Phase 2 P0.

Then rebuild and return the new artifact for confirmation.

The reviewer did not modify production source code in this round.

The reviewer added only this review document.
