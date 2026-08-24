# RPZ Local Processor Phase 1B Review

**Review date:** 2026-08-23

**Input documents:**

- `docs/PHASE1B_DESIGN_20260823.md`
- `REVIEW_HANDOFF_PHASE1B.md`

**Production patch:** `patches/rpz_patch_phase1b_v1.sh`

**Reviewed patch SHA-256:**
`fd85d67df1dc3d73ff69f8eb08eb62cdcf645445105dffb706e9ef466c3b0608`

**Overall decision:** CONDITIONAL GO

**Production patch decision:** CONDITIONAL GO

**Controlled e2e driver decision:** NO-GO

**Version 1.2.2 package decision:** NO-GO

**CR-10 decision:** Phase 2 P0. It does not block the Phase 1B scope by itself.

**Language:** ASD-STE100-style English

This document uses short sentences and consistent terms.

This document is not a formal STE compliance certificate.

The iRule code is not in this review.

---

## 1. Executive decision

The Phase 1B direction is correct.

The cleanup scope is now much safer.

The new `find` commands cannot enter `final/`.

The default count rule keeps the latest 24 files in each normal file family.

The EXIT trap works on the tested success, NO_UPDATE, and failure paths.

The trap keeps the original exit status on those paths.

The one-file patch mechanism is suitable for this task.

The patch builder is deterministic.

The reviewer reproduced all 66 reported regression assertions.

The reviewer also reproduced the Phase 1B patch and V4 prerequisite state on the LAB device.

The current artifact is not ready for a customer canary.

Three cleanup edge conditions need a small payload correction.

The current e2e driver is destructive and does not have a hard LAB guard.

It can also report PASS without a revision increase or a valid final handler state.

The version 1.2.2 package cannot pass its own installer version gate.

The package also contains macOS extended-attribute headers.

Do not add a transaction framework to Phase 1B.

Do not add CR-10 to this patch.

Make the focused changes in Section 10.

Then rebuild and run one controlled LAB e2e test.

After those conditions pass, use one customer device as the canary.

---

## 2. Decision by deliverable

| Deliverable | Decision | Review result |
|---|---|---|
| Cleanup scope | PASS | Only `raw/` and `parsed/` are in the age cleanup scope. |
| Default KEEP=24 behavior | PASS WITH CONDITIONS | Normal families keep 24. Input overflow and glob-prefix cases need correction. |
| EXIT trap | PASS WITH CONDITIONS | Normal, NO_UPDATE, and tested failure paths keep the expected status. An accepted huge KEEP value can break the trap cleanup. |
| Cleanup logging | FAIL | A delete failure is hidden, and the log reports a false retained count. |
| Patch mechanism | PASS | Check, apply, rollback, backup, target preflight, and fault recovery passed. |
| Builder | PASS | A clean temporary build produced the exact reviewed SHA-256 value. |
| Project gate | PASS WITH GAP | The gate returns 31/0, but it does not test package/installer version compatibility. |
| LAB regression | PASS WITH GAPS | The 66 assertions reproduce. They do not cover the three new edge cases or NO_UPDATE. |
| Controlled e2e driver | NO-GO | It has no hard LAB identity guard and does not gate all acceptance values. |
| Package 1.2.2 | NO-GO | Its installer accepts only version 1.2.1. The archive also contains macOS xattr headers. |
| CR-10 | PHASE 2 P0 | The incident proves the defect. Phase 1B does not create this defect. |

---

## 3. Scope and architecture result

Phase 1B changes only `main.sh` in production.

This scope is appropriate.

The patch does not change the V4 files:

- `utils.sh`
- `parse_rpz.sh`
- `generate_datagroup.sh`

The Phase 1B file does not call `find_newest_file()`.

Thus, Phase 1B has no runtime code dependency on V4.

The operational sequence must still be V4 first and Phase 1B second.

This sequence gives the customer the SIGPIPE correction before retention cleanup starts.

The reverse rollback sequence is correct:

1. Roll back Phase 1B.
2. Roll back V4.

The one-file replacement does not need a multi-file transaction.

The current patch target preflight is correct.

The current pure-original rollback rule is correct.

Do not restore the V3 recovery framework.

---

## 4. Independent evidence

### 4.1 Artifact identity

The artifact values agree with the handoff.

| File | MD5 or SHA-256 |
|---|---|
| `rpz_patch_phase1b_v1.sh` MD5 | `da0c7ed96aa3aaa6fda73a389165af52` |
| `rpz_patch_phase1b_v1.sh` SHA-256 | `fd85d67df1dc3d73ff69f8eb08eb62cdcf645445105dffb706e9ef466c3b0608` |
| `build_patch_phase1b.sh` MD5 | `5d77083f1173e4789adbecd3a8506f64` |
| new `main.sh` MD5 | `5a04c25ff2042d26d47dbf41543d0b99` |
| `f5_patch_1b_test.sh` MD5 | `8a7d061e129afe4fab262aa5bb288de7` |
| `f5_e2e_1b_controlled.sh` MD5 | `9f9c1a67cfa276c2db1e438af2c76923` |

The Phase 1B sidecar returned RC=0.

The five reviewed Phase 1B shell files passed `bash -n`.

### 4.2 Deterministic builder

The reviewer copied only these files to a temporary clean tree:

- `scripts/main.sh`
- `patches/build_patch_phase1b.sh`

The builder returned RC=0.

The output was:

```text
PASS: bash -n
PASS: round-trip
PASS: no placeholder remains
Total lines: 561
Embedded lines: 327
Tool logic lines: 234
SHA-256: fd85d67df1dc3d73ff69f8eb08eb62cdcf645445105dffb706e9ef466c3b0608
```

The generated patch was byte-for-byte equal to the reviewed patch.

### 4.3 Project gate

The reviewer ran the project gate.

The result was:

```text
PASS=31  FAIL=0
RC=0
```

The gate correctly checks these Phase 1B items:

- one current Phase 1B patch
- embedded `main.sh` equality
- original and new MD5 values
- the Phase 1B SHA-256 sidecar

The gate has package compatibility and metadata-header gaps.

See P1B-05 and P1B-06.

### 4.4 LAB regression

The LAB copy of the test file had this SHA-256 value:

```text
a94c9f1dd25fb104c80cedc446a8dafeb4294461e0488c0cc7a66d2bcf0cca59
```

This value agrees with the local file.

The reviewer ran the 66-assertion regression again.

The result was:

```text
PASS=66  FAIL=0
RC=0
```

The reported M1 through M10 cases passed.

The reported F1 through F7 cases passed.

The reported T1 and T2 cases passed.

The fixture was removed after the test.

### 4.5 Independent NO_UPDATE test

The supplied regression does not test the NO_UPDATE path.

The reviewer added an isolated test in `/var/tmp`.

The test used a fake `check_soa.sh` that returned `NO_UPDATE`.

The test started with 30 raw files and one final sentinel.

The result was:

```text
NOUPDATE_RC=0 RAW=24 FINAL=1
[INFO] SOA Serial did not change
[INFO] Count cleanup deleted 6 and kept 24
```

This result confirms the intended NO_UPDATE runtime behavior.

Add this case to the permanent regression test.

### 4.6 LAB final state

The LAB device has the reviewed Phase 1B `main.sh` MD5.

The LAB device also has all three reviewed V4 MD5 values.

The Phase 1B check returns RC=0.

The V4 check returns RC=0.

The handler is active.

The interval is 300 seconds.

The `/config` file system is 7 percent used.

The reviewer removed all temporary review scripts and fixtures.

---

## 5. Positive payload results

### 5.1 The delete scope is correct

The old cleanup searched the complete output tree.

The new age cleanup uses these exact directories:

- `OUTPUT_DIR/raw`
- `OUTPUT_DIR/parsed`

Both commands use `-maxdepth 1`.

The commands do not search `final/`.

The count cleanup also uses only `raw/` and `parsed/`.

This is the most important Phase 1B safety change.

### 5.2 Normal count retention is correct

The normal raw family was reduced from 100 files to 24 files.

Three normal parsed families were each reduced from 100 files to 24 files.

The newest raw file stayed present.

The oldest raw file was removed.

The three final sentinel files stayed present.

The algorithm uses no pipeline and no `ls` command.

Thus, it does not recreate the 4096-byte SIGPIPE pattern.

### 5.3 The normal EXIT trap behavior is correct

The success path calls cleanup once.

The EXIT trap does not call it a second time.

The tested failure path returned RC=1 after cleanup.

The independent NO_UPDATE path returned RC=0 after cleanup.

The final sentinel stayed present in both tests.

The `run_cleanup_once()` structure is sufficient.

### 5.4 Silent no-op cleanup is acceptable

It is acceptable to produce no INFO output when cleanup has no work.

This prevents log growth on NO_UPDATE ticks.

Do not suppress a delete failure.

A delete failure must produce a WARN message.

---

## 6. Findings

## P1B-01 — High — The destructive e2e driver is not fail-closed

### Location

- `tests/lab/f5_e2e_1b_controlled.sh`, lines 1 through 92
- `tests/lab/README.md`, lines 1 through 28

### Condition

The e2e driver writes to the real `/config/snmp/rpz_datagroups` tree.

It stops and starts the real iCall handler.

It applies the real Phase 1B patch.

It runs the real main process.

It saves the BIG-IP configuration.

The script has no `--lab-only` argument.

The script does not check the LAB hostname.

The script does not require an explicit operator confirmation.

The script can therefore run on a customer device if an engineer copies it there.

The EXIT trap removes broad `202607*` path patterns.

It does not remove only files that this test created.

The EXIT trap sets the handler to active, but it does not save or verify that state.

The script does not verify that the initial handler change to inactive succeeded.

The script prints the before and after revision values.

It does not compare them.

The script prints the final handler state.

It does not assert `active` and `300`.

The script can print `SAVE_OK`, but a missing `SAVE_OK` does not fail the test.

The script displays diagnostic log lines.

It does not require the expected diagnostic lines.

The PASS counter checks only four family counts and one file size.

Thus, `PASS=5 FAIL=0` is not a complete e2e acceptance gate.

### Effect

An accidental production execution can modify customer state.

A failed revision update can still produce `PASS=5 FAIL=0`.

A handler restore or configuration-save failure can also produce PASS.

The first e2e accident shows why every step needs a hard gate.

### Required change

Treat this test as a high-destructive LAB test.

Add these mandatory controls:

1. Require an exact `--lab-only` argument.
2. Require hostname `cdns.ryantseng.work` with no bypass flag.
3. Require an explicit confirmation value that contains the complete hostname.
4. Require the initial handler state to be `active` with interval 300.
5. Require the inactive change to succeed and verify the inactive state.
6. Require the process wait to finish successfully.
7. Require the patch apply and patch check to succeed.
8. Record every synthetic file in a test-owned list.
9. Remove only the files in that list.
10. Record revision, size, final mtime, and handler state as variables.
11. Assert the before-and-after values.
12. Require the two main diagnostic strings.
13. Restore the handler and save the configuration in the EXIT path.
14. Verify the final handler state before a PASS result.

Use `set -euo pipefail` or explicit checks for every state-changing command.

Do not use an early-close display pipeline with `head` under `pipefail`.

Update `tests/lab/README.md`.

Mark this test as high destructive.

### Acceptance test

Verify these refusal cases without `/config` changes:

- no `--lab-only`
- wrong hostname
- missing confirmation
- wrong confirmation
- handler not initially active/300

Then run one successful LAB test.

Require these results:

- apply RC=0
- patch check RC=0
- main RC=0
- final mtime increases
- revision increases
- final size is nonzero and reasonable
- all four normal families have at most 24 files
- configuration save succeeds
- final handler state is active/300
- no synthetic test file remains

---

## P1B-02 — Medium — An accepted KEEP value can overflow Bash arithmetic

### Location

- `scripts/main.sh`, lines 39 through 44
- `scripts/main.sh`, lines 85 through 100
- the embedded `main.sh` in the Phase 1B patch

### Condition

The validation accepts any positive decimal string that does not start with zero.

Bash 4.2 arithmetic uses a fixed-size signed integer.

A very large accepted value wraps during this expression:

```bash
del=$(( ${#files[@]} - keep ))
```

The reviewer used an isolated LAB fixture with 30 raw files.

The reviewer set this value:

```text
RPZ_KEEP_COUNT=999999999999999999999999999999999999
```

Observed result:

```text
EDGE1_RC=1 RAW=0 FINAL=1
main.sh: line 98: files[$i]: unbound variable
```

The cleanup removed all 30 raw files.

It then indexed past the array.

The `set -u` error stopped the cleanup.

The final sentinel was not removed.

### Effect

An accepted configuration value can remove the complete raw history.

It can also change a successful or NO_UPDATE exit into RC=1.

The default value 24 does not have this defect.

### Required change

Set an explicit numeric upper limit.

Normalize the accepted value as base 10 only after a safe length check.

Use the default value 24 for an out-of-range value.

Document the accepted range.

The simplest option is to make 24 a constant if runtime tuning is not required.

Do not evaluate an unbounded environment string in Bash arithmetic.

### Acceptance test

Add these values to the permanent regression:

- `abc`
- `0`
- `7`
- `24`
- the documented maximum
- one value above the maximum
- a 36-digit positive value

Every invalid or out-of-range value must warn and use 24.

The cleanup must return RC=0.

It must keep 24 of 30 raw files.

---

## P1B-03 — Medium — A glob character in a file-family prefix can delete another family

### Location

- `scripts/main.sh`, lines 103 through 118
- the embedded `main.sh` in the Phase 1B patch

### Condition

The parsed-family prefix comes from a file name.

The regular expression accepts any nonempty prefix.

The prefix is then used as an unescaped shell glob.

The reviewer created these isolated families:

- 30 `alpha` files
- 30 `beta` files
- one timestamp-shaped file with prefix `*`

Observed result:

```text
EDGE2_RC=0 ALPHA=0 BETA=24 FINAL=1
[INFO] Count cleanup: parsed/alpha_*.txt deleted 6 and kept 24
[INFO] Count cleanup: parsed/*_*.txt deleted 31 and kept 24
```

The `*` prefix matched all parsed families.

The cleanup removed all files in the `alpha` family.

### Effect

One malformed or manually created file name can cross the family boundary.

This violates the per-family retention rule.

It also contradicts the design statement for foreign file names.

The normal customer zone names do not contain shell glob characters.

### Required change

Do not use an unvalidated file-derived value as a glob.

Use one of these small solutions:

1. Accept only the safe prefix characters that the processor creates.
2. Or escape all shell glob characters before the prefix is used.

The safe-prefix option is simpler.

If a prefix is not safe, skip count pruning for that prefix and write one WARN message.

The age rule can still process that file later.

### Acceptance test

Test these prefix characters:

- `*`
- `?`
- `[` 
- backslash

No malformed prefix can change a normal family count.

The final sentinel must stay present.

Normal `rpztw`, `phishtw`, and `rpzip` families must still keep 24 files.

---

## P1B-04 — Medium — Delete failures are hidden and the success log is false

### Location

- `scripts/main.sh`, lines 95 through 100
- `scripts/main.sh`, lines 127 through 130
- the embedded `main.sh` in the Phase 1B patch

### Condition

The count loop discards `rm` errors.

The loop always logs the requested delete count.

It does not log the actual delete count.

The age cleanup also discards all `find -delete` errors.

The reviewer made one of the six oldest raw victims immutable.

Observed result:

```text
EDGE3_RC=0 RAW=25 LOCKED_EXISTS=yes FINAL=1
[INFO] Count cleanup: raw/dnsxdump_*.out deleted 6 and kept 24
```

Only five files were removed.

The log stated that six files were removed.

The log also stated that 24 files remained.

The actual count was 25.

### Effect

A permission, attribute, or file-system problem can disable retention silently.

The file count and disk use can continue to grow.

The operator can believe that the limit still works.

This failure mode is directly related to the customer incident goal.

### Required change

Keep cleanup nonfatal to the RPZ processing result.

Do not hide the cleanup failure.

Count successful and failed deletions separately.

Log the actual result.

Write WARN output when one deletion fails.

Also write WARN output when an age-based `find -delete` command fails.

Do not claim `kept 24` if the actual count is larger.

### Acceptance test

Make one count-prune victim immutable.

Require these results:

- the main cleanup returns RC=0
- the WARN message identifies a delete failure
- the summary does not claim a false count
- the final sentinel stays present

Add an equivalent age-delete failure case.

The next run after the attribute is removed must reach 24 files.

---

## P1B-05 — Medium — Package 1.2.2 cannot pass its own installer version gate

### Location

- `package.sh`, line 16
- `install.sh`, line 24
- `tests/check_source_consistency.sh`, package checks
- `dist/rpz_local_processor_v1.2.2_20260823_003641.tar.gz`

### Condition

The package VERSION is 1.2.2.

The packaged installer supports only 1.2.1.

The project gate checks package content equality.

It does not check that the installer accepts the package VERSION.

The reviewer extracted the actual package on the LAB device.

The reviewer used `RPZ_INSTALL_TEST_MODE=1` and isolated `/var/tmp` targets.

Observed result:

```text
INSTALL_RC=1
INSTALL_TARGET_EXISTS=no
OUTPUT_TARGET_EXISTS=no
Package version '1.2.2' is not supported by this installer (1.2.1)
```

The installer failed before it wrote a target file.

This fail-closed behavior is good.

The package is still unusable.

### Effect

The version 1.2.2 tar file cannot be used for a verified installation.

The 31-pass gate can give a false package-ready impression.

This defect does not affect an existing-device Phase 1B patch deployment.

### Required change

Choose one release scope:

1. If package 1.2.2 is a deliverable, add 1.2.2 to the supported versions, rebuild it, and test it.
2. If this release is patch-only, keep package 1.2.2 on HOLD and remove it from Phase 1B GO evidence.

Add a gate check that requires `package.sh` VERSION to be in `SUPPORTED_VERSIONS`.

Correct the package version comment at `package.sh:15`.

### Acceptance test

Extract the rebuilt package on the LAB device.

Use isolated installation targets.

Require installer RC=0.

Verify every installed source file against the package manifest.

Remove the isolated targets after the test.

---

## P1B-06 — Low — Package 1.2.2 contains macOS xattr headers

### Location

- `package.sh`, lines 83 through 117
- `dist/rpz_local_processor_v1.2.2_20260823_003641.tar.gz`

### Condition

The package script removes AppleDouble files.

It does not remove the `com.apple.provenance` extended attribute from staged files.

The archive contains these header keys:

```text
LIBARCHIVE.xattr.com.apple.provenance
SCHILY.xattr.com.apple.provenance
```

The LAB GNU tar command printed an unknown-header warning for the packaged files.

The current gate searches only for metadata file names.

It does not detect metadata headers.

### Effect

The package extracts with warnings on BIG-IP.

The file data is still extracted.

The warning reduces package portability and operator confidence.

### Required change

Remove extended attributes from the staging tree before archive creation.

Also use the no-xattr option that is available in the macOS tar tool.

Keep the AppleDouble filename check.

Add an extraction test on the target GNU tar version.

### Acceptance test

The rebuilt archive must not contain `LIBARCHIVE.xattr` or `SCHILY.xattr` strings.

LAB extraction must produce no unknown extended-header warning.

The inner and outer SHA-256 checks must still pass.

---

## P1B-07 — Low — Permanent tests and release records are incomplete

### Location

- `tests/lab/f5_patch_1b_test.sh`, lines 252 through 271
- `tests/lab/README.md`
- `docs/PHASE1B_DESIGN_20260823.md`, lines 4 and 283 through 290
- `package.sh`, line 15
- `dist/DO_NOT_DEPLOY.md`

### Condition

The permanent regression does not test NO_UPDATE.

The reviewer confirmed that NO_UPDATE works, but this evidence is not repeatable from the repository test.

The T1 and T2 commands do not set a fixture `LOG_FILE`.

They append error records to the real LAB `/var/log/ltm` file.

The LAB README does not list the two Phase 1B test scripts.

The design document still says that implementation has not started.

Its final section still asks for decisions that were already made.

The package comment says version 1.2.1 while the code builds version 1.2.2.

The HOLD document does not state the version 1.2.2 status.

The design calls 403 MB a hard disk limit.

It is an estimate for the current number of families and the measured average file sizes.

It is not a byte hard limit if zone count or record size increases.

### Required change

Add a permanent NO_UPDATE trap test.

Set `LOG_FILE` to the test fixture in T1 and T2.

Document both Phase 1B tests and their destructive levels.

Update the design status and resolved decisions.

Correct the package version comment.

State the explicit HOLD or release status of package 1.2.2.

Call 403 MB a current-capacity estimate, not a universal hard limit.

---

## 7. CR-10 decision

The first e2e incident is valid evidence for CR-10.

`generate_datagroup.sh` warns for a zero-byte required zone file.

It then copies that file to `final/`.

`update_datagroup.sh` skips a zero-byte final file.

In the observed incident, the TMOS DataGroup stayed unchanged.

This result prevented a service change in that one case.

It is not a complete safety guarantee.

A partial or malformed nonzero data set can follow a different path.

CR-10 must be the highest-priority Phase 2 item.

Phase 2 must keep the last known-good final files when validation fails.

Phase 2 must validate all required zone artifacts before publication.

Phase 2 should use temporary final files and atomic rename after validation.

Do not implement that work in Phase 1B.

Phase 1B does not modify `generate_datagroup.sh` or `update_datagroup.sh`.

Phase 1B excludes `final/` from cleanup.

Phase 1B also keeps recent raw and parsed recovery material.

Thus, CR-10 does not independently block the retention patch.

It does block a claim that the complete publication pipeline is fail-safe.

---

## 8. Answers to the handoff questions

### Question 1: Are failure paths missing?

The normal success, failure, and NO_UPDATE cleanup paths work.

SIGKILL and OOM cannot run an EXIT trap. This limit is accepted.

P1B-02 is a missing cleanup failure path for an accepted KEEP value.

P1B-04 is a missing observable path for delete failures.

The permanent test also needs the NO_UPDATE case.

### Question 2: Does the EXIT trap keep the exit status?

Yes, for the reviewed default configuration and tested paths.

The T1 failure kept RC=1.

The independent NO_UPDATE test kept RC=0.

The ERR trap and EXIT trap can coexist in these paths.

P1B-02 shows that an arithmetic/nounset failure inside cleanup can prevent the final `exit "$rc"` command.

Close P1B-02 before the status-preservation claim is unconditional.

### Question 3: Are silent cleanup and NO_UPDATE cleanup acceptable?

Yes.

A no-op cleanup can stay silent.

NO_UPDATE cleanup is necessary because it is the common stalled-update path.

A delete failure must not stay silent.

### Question 4: Does the incident block Phase 1B?

No, not by itself.

The incident came from the test harness and the existing CR-10 behavior.

The incident did not come from the Phase 1B cleanup code.

It requires a safer e2e driver before release evidence is accepted.

It also moves CR-10 to Phase 2 P0.

---

## 9. Accepted limits

The count rule uses the timestamp in the file name.

This is accepted for normal processor artifacts.

The count is per family.

The total disk use changes when the number of zones or the data size changes.

The 403 MB value is a current estimate.

It is not a fixed byte quota.

SIGKILL and OOM do not run the EXIT trap.

The next normal tick can correct the count.

The process does not have a full workflow lock.

The count cleanup normally removes old names while a writer creates a new name.

This existing race is accepted for Phase 1B.

Only one administrator can run patch commands at one time.

The Phase 1B rollback returns to the old cleanup behavior.

This rollback result is known and accepted for emergency recovery.

---

## 10. Required Fable5 changes

Keep the production change small.

### 10.1 Production payload

1. Bound and normalize `RPZ_KEEP_COUNT`.
2. Reject or escape unsafe parsed-family prefixes.
3. Report actual count-delete results.
4. Write WARN output for count and age delete failures.
5. Keep cleanup failure nonfatal to the RPZ processing result.
6. Keep `final/` outside every cleanup path.

### 10.2 Regression test

Add these cases:

1. Very large KEEP value.
2. Maximum accepted KEEP value.
3. Value above the maximum.
4. Parsed prefix with `*`.
5. Parsed prefix with `?`.
6. Parsed prefix with `[`.
7. Immutable count-prune victim.
8. Age-delete failure.
9. NO_UPDATE exit with cleanup.
10. NO_UPDATE exit with `--no-cleanup`.

Set `LOG_FILE` to a fixture path in process tests.

### 10.3 Controlled e2e

Replace the current driver with a fail-closed LAB-only driver.

Add the guards and assertions in P1B-01.

Update `tests/lab/README.md` before it is run again.

### 10.4 Package

Either fix and test package 1.2.2, or keep it explicitly on HOLD.

Do not use gate PASS=31 as an installability claim until P1B-05 is closed.

If the package stays in scope, also close P1B-06.

### 10.5 Records

Update these files after the final rebuild:

- `REVIEW_HANDOFF_PHASE1B.md`
- `docs/PHASE1B_DESIGN_20260823.md`
- `process.md`
- `patches/README.md`
- `tests/lab/README.md`
- the current status file
- `dist/DO_NOT_DEPLOY.md` if package 1.2.2 stays on HOLD

---

## 11. Required verification

Rebuild the Phase 1B patch from the builder.

Report the new SHA-256 value and line count.

Run these local checks:

```bash
cd patches
shasum -a 256 -c rpz_patch_phase1b_v1.sh.sha256
```

```bash
bash patches/build_patch_phase1b.sh
```

```bash
bash tests/check_source_consistency.sh
```

Run the updated Phase 1B regression on the LAB device.

Report PASS, FAIL, and RC.

Run the guarded controlled e2e test once.

Report these values:

- patch apply RC
- patch check RC
- main RC
- raw and parsed counts
- final file sizes and mtimes
- DataGroup revision before and after
- DataGroup size before and after
- handler status and interval
- configuration-save result
- synthetic-file cleanup result

Do not rerun the V4 4096 failure curve.

Phase 1B does not change the V4 payload.

Do not run a synthetic-file e2e test on a customer device.

---

## 12. Customer canary rule

Do not use the reviewed Phase 1B SHA-256 value for a customer canary.

First close P1B-01 through P1B-04.

Package findings do not block a patch-only existing-device canary.

They do block package 1.2.2 deployment.

For the canary, use this sequence:

1. Run the final V4 check.
2. Confirm all three V4 files are the reviewed new versions.
3. Run the final Phase 1B check.
4. Confirm `main.sh` is the supported original version before apply.
5. Apply V4 first if it is not already applied.
6. Apply Phase 1B second.
7. Stop the handler for the controlled real-data test.
8. Do not seed synthetic files on the customer device.
9. Record final checksums, sizes, mtimes, and DataGroup revision before the test.
10. Run `main.sh --force` once with real data.
11. Record the same values after the test.
12. Restore the handler to active/300 and save the configuration.
13. Confirm each normal raw and parsed family is at most 24 after cleanup.

Monitor the canary through at least one later scheduled tick.

Confirm that the count stays bounded and that no cleanup WARN message occurs.

Deploy the next device only after the canary evidence passes.

Do not deploy four devices at the same time.

---

## 13. Final statement

The Phase 1B retention design is the correct next change.

The default normal-path implementation works.

The cleanup scope correctly protects `final/`.

The EXIT trap solves the stalled-update accumulation path.

The current release still has focused safety gaps.

They can be corrected without a larger framework.

The destructive e2e driver is not approved in its current form.

The version 1.2.2 package is not approved in its current form.

CR-10 must be Phase 2 P0.

Close the Phase 1B production findings.

Then run one guarded LAB e2e test.

After that test passes, start one customer canary.

The final Phase 1B decision is CONDITIONAL GO.
