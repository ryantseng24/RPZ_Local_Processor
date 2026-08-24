# RPZ Local Processor V4 Patch Review, Round 2

**Review date:** 2026-08-22

**Input document:** `REVIEW_HANDOFF_V4.md`

**Reviewed patch:** `patches/rpz_patch_sigpipe_v4.sh`

**Reviewed patch SHA-256:**
`d058b2cfa57bd374632021af52e5fbf6c536d4351f7bbf8d14c42e7f2fa66578`

**Decision:** CONDITIONAL GO

**Next action:** Close R2-V4-01 through R2-V4-03 before the customer canary.

**Language:** ASD-STE100-style English

This document uses short sentences and consistent terms.

This document is not a formal STE compliance certificate.

The iRule code is not in this review.

---

## 1. Executive decision

The 4096-byte SIGPIPE correction is correct.

The V4 production patch is small enough for this task.

The embedded runtime files did not change in this review round.

The provider dependency rule is correct.

The pure-original backup rule is correct.

The builder is deterministic after a source commit.

The project gate now validates V4.

The checksum instructions now use the correct directory.

The reviewer reproduced the 66 LAB assertions.

The reviewer also ran a new controlled end-to-end test.

The new test did not have the `pgrep` self-match problem.

The test changed the DataGroup revision from 16 to 17.

The test finished with the handler active at 300 seconds.

Two small release defects remain.

The SOP states acceptance values, but it does not record all of them.

Rollback validates the backup, but it does not validate the current target files.

One builder comment also gives an unsupported production-source statement.

Do not add the V3 transaction framework.

Do not add recovery staging.

Do not add a self-test command to the production patch.

Use the small changes in Section 7.

Then start with one customer canary.

---

## 2. First-round finding status

| First-round finding | Round 2 result | Reason |
|---|---|---|
| V4-01 | PARTIAL PASS | The handler sequence and passive-test rule are correct. The LAB e2e test passed. The written SOP does not record the pre-test values or the `main.sh` exit status. |
| V4-02 | PASS WITH NEW CONDITION | The dependency rule and pure-original backup gate work. A new target-validation gap exists in rollback. See R2-V4-02. |
| V4-03 | PASS | A clean rebuild produced the exact release SHA-256 value. |
| V4-04 | PASS | The gate validates V4 and returns PASS=26, FAIL=0, RC=0. |
| V4-05 | PASS | The documented checksum command returns RC=0 from `patches/`. |

The original five changes are materially correct.

This review does not request a new architecture.

---

## 3. Independent evidence

### 3.1 Artifact integrity

The local sidecar check returned RC=0.

Output:

```text
rpz_patch_sigpipe_v4.sh: OK
```

The patch has 866 lines.

The patch MD5 is:

```text
22eae35545f25a9a6ecdfb63853d9b4e
```

The three embedded payload MD5 values agree with the tracked source:

| File | MD5 |
|---|---|
| `utils.sh` | `b8294149dc978305e19bcd83fcb650e6` |
| `parse_rpz.sh` | `cefa71b6623632dd51c60a51cdf72196` |
| `generate_datagroup.sh` | `9599755a54db53652c070cd70ae92652` |

### 3.2 Syntax and project gate

The following four files passed `bash -n`:

- `patches/rpz_patch_sigpipe_v4.sh`
- `patches/build_patch_v4.sh`
- `tests/check_source_consistency.sh`
- `tests/lab/f5_patch_v4_test.sh`

The project gate returned:

```text
PASS=26  FAIL=0
RC=0
```

The gate checked the V4 embedded files.

The gate checked the V4 MD5 table.

The gate checked the V4 SHA-256 sidecar.

The gate found only one current patch in `patches/`.

V3 is in `patches/archive/`.

### 3.3 Deterministic builder

The reviewer copied only these items to a temporary clean tree:

- the three new source files
- `build_patch_v4.sh`

The builder returned RC=0.

The builder produced:

```text
PASS: bash -n
PASS: round-trip x3
PASS: no placeholder remains
Total lines: 866
Embedded lines: 608
Tool logic lines: 258
SHA-256: d058b2cfa57bd374632021af52e5fbf6c536d4351f7bbf8d14c42e7f2fa66578
```

The generated file was byte-for-byte equal to the reviewed patch.

This result closes V4-03.

### 3.4 LAB regression test

The LAB device was `10.8.34.223`.

The LAB test file SHA-256 was:

```text
6f5ce4e26033987d693f9875cce45d28bb47b69392ec4c2983dddea46118bea7
```

This value agrees with the local test file.

The reviewed patch SHA-256 also agreed on the LAB device.

The reviewer ran:

```text
bash /var/tmp/f5_patch_v4_test.sh /var/tmp/rpz_patch_sigpipe_v4.sh
```

The result was:

```text
PASS=66  FAIL=0
RC=0
```

The test included all eight original/new combinations.

The three invalid provider combinations returned RC=2.

The mixed backup returned RC=2.

The pure-original backup returned RC=0.

All apply and rollback fault-injection cases passed.

No test fixture remained after the test.

### 3.5 Controlled end-to-end test

The handoff reports a 122-second wait timeout.

The reported cause is correct.

The parent `bash -c` command line contained the production script path.

The broad `pgrep -f` expression matched that parent command.

The reviewer did not use a large `bash -c` command.

The reviewer uploaded one test script to `/var/tmp`.

The process command line contained only the test-script path.

The test script had an EXIT recovery action for the handler.

The independent result was:

```text
Handler before: active / 300
Revision before: 16
WAIT_QUIET=PASS
MAIN_RC=0
The dnsxdump diagnostic line was present.
The processing-complete line was present.
Revision after: 17
The final-file mtime increased.
The configuration save completed.
Handler after: active / 300
CONTROLLED_E2E=PASS
```

This evidence closes the runtime and concurrency part of V4-01.

The 122-second timeout is a test-harness defect.

It is not a production patch defect.

Do not put the complete SOP in one remote `bash -c` command.

Use separate interactive commands or a script file.

### 3.6 LAB final state

The reviewer removed the two temporary review scripts.

The reviewer removed all review fixtures.

The production scripts on the LAB device have the three new MD5 values.

The V4 `check` command returns RC=0.

The handler is active.

The interval is 300 seconds.

The `/config` file system is 5 percent used.

The pure-original backup remains at:

```text
/var/tmp/rpz_patch_backup_20260822_232957
```

Its three files pass `md5sum -c`.

---

## 4. Findings

## R2-V4-01 — Medium — The SOP does not produce all required acceptance evidence

### Location

- `patches/README.md`, lines 71 through 101

### Condition

The SOP tells the operator to run `main.sh --force`.

The SOP then states that the exit status must be zero.

The SOP does not tell the operator to save `$?` immediately.

An interactive shell does not show the exit status by default.

The next command replaces `$?`.

The SOP states that the final-file times must change.

The SOP does not record the final-file times before the test.

The SOP states that the DataGroup revision must increase.

The SOP does not record the revision before the test.

The first-round requirement also includes the DataGroup size.

The current `grep` expression does not show `size`.

### Effect

The operator can run a correct test but produce incomplete evidence.

The operator can also accept a test without proof of RC=0.

The operator cannot make a direct before-and-after revision comparison from the SOP output.

### Required change

Keep the manual, line-by-line SOP.

Do not add a deployment framework.

Before `main.sh --force`, record these values:

1. The final-file times.
2. The DataGroup revision.
3. The DataGroup size.
4. The DataGroup last-update time.

Immediately after `main.sh --force`, save and print the exit status.

For example:

```bash
bash /config/snmp/RPZ_Local_Processor/scripts/main.sh --force
MAIN_RC=$?
echo "main.sh RC=$MAIN_RC"
```

Then record the same file and DataGroup values again.

Require these results:

- `MAIN_RC=0`
- the two diagnostic strings are present
- the final-file times increase
- the revision increases
- the DataGroup size is nonzero and reasonable
- the handler finishes in the active state
- the handler interval is 300 seconds

Keep the mandatory handler restore instructions for both success and failure.

### Acceptance test

Follow only the written SOP on the LAB device.

The transcript must contain the before values.

The transcript must contain `MAIN_RC=0`.

The transcript must contain the after values.

The transcript must show the revision increase.

The transcript must show `status active` and `interval 300`.

---

## R2-V4-02 — Medium — Rollback can overwrite an unknown current target

### Location

- `patches/rpz_patch_sigpipe_v4.sh`, lines 191 through 227
- `patches/build_patch_v4.sh`, generated `do_rollback()` template at line 229
- `tests/lab/f5_patch_v4_test.sh`, rollback cases
- `REVIEW_HANDOFF_V4.md`, line 85

### Condition

Apply validates all current target files before it changes one file.

Rollback does not do this validation.

Rollback validates only the backup files.

The reviewer used an isolated LAB target.

The reviewer added one local change to the target `utils.sh` file.

The target MD5 became unknown.

The V4 `check` command returned RC=2.

The reviewer then used a valid pure-original backup.

Rollback returned RC=0.

Rollback replaced the unknown target without a warning.

Observed result:

```text
CHECK_RC=2
ROLLBACK_RC=0
UTILS_BEFORE=f7cb6a08e03481c21f954af8b9316511
UTILS_AFTER=3cab6cbca952f3780350e9882e5f7c11
```

The handoff states that an unknown file causes rejection.

That statement is not true for rollback.

A missing target has another failure mode.

The reverse-order loop can replace earlier files before `place_file()` detects the missing later target.

### Effect

Rollback can remove an unreviewed local change.

Rollback can start a partial restore when one target file is missing.

The normal canary path does not create this state.

The defect is still in a safety command.

### Required change

Add one target preflight loop to `do_rollback()`.

Run the loop before the first target-file replacement.

Require each current target to be `orig` or `new`.

Return RC=2 for `unknown` or `missing`.

Do not reject a known dependency-violation state in this loop.

A pure-original rollback can repair that known state.

Use the existing `state_of()` function.

This change needs approximately seven lines.

This change is not a transaction framework.

This change is not recovery staging.

### Acceptance test

Add these isolated cases:

1. Set one current target to an unknown MD5.
2. Use a valid pure-original backup.
3. Require rollback RC=2.
4. Require all three current target MD5 values to stay unchanged.
5. Remove one current target.
6. Require rollback RC=2.
7. Require the other two current target MD5 values to stay unchanged.
8. Confirm that normal rollback still returns RC=0.
9. Confirm that rollback from a known dependency-violation state returns RC=0.

---

## R2-V4-03 — Low — The builder gives an unsupported production-source statement

### Location

- `patches/build_patch_v4.sh`, line 12

### Condition

The builder says that the original MD5 values came from four production devices.

The available four-device capture files do not contain script MD5 values.

The older review records also state that four production MD5 collections are still required.

The reviewer verified a different fact.

The three original MD5 values agree with local commit:

```text
27415940f03641ccd920e664797d79447bd91617
```

The local `origin/main` reference has the same commit.

The repository URL is:

```text
https://github.com/ryantseng24/RPZ_Local_Processor.git
```

The original MD5 values are therefore valid for the reviewed GitHub baseline.

They are not proof of the current files on all four customer devices.

### Effect

The comment can make an operator think that production compatibility is already confirmed.

The V4 `check` command correctly prevents this assumption during deployment.

### Required change

Correct the builder comment.

State that the constants are from the reviewed GitHub baseline.

State that each customer device must pass the V4 `check` command before apply.

Do not state that four production MD5 sets were collected unless that evidence is added.

### Acceptance test

Review the new comment.

Confirm that the builder output stays byte-for-byte equal before R2-V4-02 changes it.

For each customer device, run `check` before apply.

Stop if one MD5 value is unknown.

---

## 5. Accepted limits

The V4 patch does not clean old raw or parsed files.

This limit is accepted for the 4096 correction.

Phase 1B owns the retention-policy change.

The process guard is best-effort.

This limit is accepted with the documented file order.

One already-running old process can fail once during apply.

The next process uses the new files.

The patch does not provide a multi-file transaction.

This limit is accepted for this hotfix.

The final-file publish is not fully atomic.

That earlier project defect is not part of this V4 patch review.

Only one administrator can run patch commands at one time.

This operational rule remains necessary.

The `pgrep` pattern can match an unrelated command line that contains the script path.

This produces a conservative stop.

It does not cause a file replacement.

No code change is required for this limit.

---

## 6. Direct answers to the handoff questions

### Question 1

V4-03, V4-04, and V4-05 are closed.

The runtime part of V4-01 is closed.

The written evidence part of V4-01 is not closed.

The original V4-02 dependency defect is closed.

R2-V4-02 is a new rollback target-validation defect.

The result stays CONDITIONAL GO.

### Question 2

`dep_violation()` covers the three invalid orig/new combinations.

The pure-original backup gate checks all three backup files before replacement.

The missing path is the current-target preflight in rollback.

### Question 3

The 66-assertion test meets the first-round test intent.

Add the R2-V4-02 target cases.

Do not move these tests into the production patch.

---

## 7. Required Fable5 changes

Use this small change set:

1. Add the current-target preflight to the rollback template in `build_patch_v4.sh`.
2. Rebuild `rpz_patch_sigpipe_v4.sh` and its sidecar.
3. Add the unknown-target and missing-target tests to `f5_patch_v4_test.sh`.
4. Correct SOP step 7 so that it records before values, `MAIN_RC`, and after values.
5. Add DataGroup `size` to the SOP evidence.
6. Correct the unsupported four-production-device comment.
7. Update `REVIEW_HANDOFF_V4.md`, `process.md`, and `STATUS_20260822.md`.

Do not make these changes:

- Do not restore the V3 transaction code.
- Do not restore recovery staging.
- Do not add cleanup to V4.
- Do not add an embedded self-test.
- Do not change the three embedded runtime payload files.
- Do not change any iRule.

---

## 8. Required verification after the changes

Run these local checks:

```bash
cd patches
shasum -a 256 -c rpz_patch_sigpipe_v4.sh.sha256
```

```bash
bash patches/build_patch_v4.sh
```

```bash
bash tests/check_source_consistency.sh
```

Run the updated isolated test on the LAB device.

Report the new assertion count.

Report PASS, FAIL, and RC.

Report the new patch SHA-256 value.

Report the new patch line count.

Verify these specific results:

| Test | Required result |
|---|---|
| Unknown current target plus pure backup | RC=2 and no target changes |
| Missing current target plus pure backup | RC=2 and no other target changes |
| All-new current targets plus pure backup | RC=0 and all-original result |
| Known invalid dependency state plus pure backup | RC=0 and all-original result |
| Eight orig/new check combinations | Five RC=0 and three RC=2 |
| Mixed backup | RC=2 before target changes |
| Project gate | FAIL=0 and RC=0 |
| Sidecar | RC=0 |

The embedded runtime payload does not need a new 4096 failure curve.

The payload did not change.

The controlled e2e test does not need another run for the rollback-only wrapper change.

If the payload changes, run the full function test again.

---

## 9. Customer canary rule

Do not start the customer canary with the reviewed SHA-256 value.

First close R2-V4-01 through R2-V4-03.

Then use one device as the canary.

On that device, run V4 `check` before apply.

The check must show all three original V1.2 MD5 values.

Stop if the check reports an unknown file.

Stop if the check reports a dependency violation.

Do not assume that all four customer devices have the GitHub baseline.

Run the same check separately on each device.

Do not deploy to four devices at the same time.

---

## 10. Final statement

The V4 direction is correct.

The 4096 correction is ready at the runtime level.

The simple ordered-file design is still accepted.

The first-round code corrections work as reported.

The remaining changes are small.

They do not justify a larger shell framework.

Close the three round-two findings.

Then start one customer canary.

The final Round 2 decision is CONDITIONAL GO.
