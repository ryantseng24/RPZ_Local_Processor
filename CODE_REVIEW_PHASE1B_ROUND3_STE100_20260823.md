# RPZ Local Processor Phase 1B Review, Round 3

**Review date:** 2026-08-23

**Review type:** Short confirmation review

**Reviewed handoff:** `REVIEW_HANDOFF_PHASE1B.md`

**Reviewed handoff SHA-256:**
`6845f3c5428b367c18639bcf49370bd53a84ab76ee39dce4b1e083375fcc1959`

**Reviewed production patch:** `patches/rpz_patch_phase1b_v1.sh`

**Reviewed patch SHA-256:**
`aa97950e8a45541b8f48bcdfa4d20c495db6d9ef4989724d064dd3470058c785`

**Production patch runtime decision:** GO

**Controlled e2e driver decision:** GO for the named LAB only

**Single-device customer canary:** CONDITIONAL GO

**Release-record decision:** HOLD until P1B-07 text corrections are complete

**Version 1.2.2 package decision:** NO-GO and HOLD

**CR-10 decision:** Phase 2 P0. It does not block Phase 1B.

**Language:** ASD-STE100-style English

This document uses short sentences and consistent terms.

This document is not a formal STE compliance certificate.

The iRule code is not in this review.

---

## 1. Executive decision

The new Phase 1B payload corrects P1B-08.

The new exact family selector does not mix `alpha` and `alpha_beta`.

The new LAB regression confirms this result on Bash 4.2.

The reviewer reproduced all 112 regression assertions.

The reviewer reproduced all eight F12 assertions.

The new e2e driver corrects the remaining P1B-01 conditions.

It checks each synthetic-file creation.

It records a created file before the mtime operation.

It checks each mtime operation.

It verifies all 120 synthetic files.

It requires exactly 24 files in each seeded family.

It does not accept zero files.

It keeps the manifest when a file remains.

It reports handler-restore and configuration-save failures.

P1B-01 is closed.

P1B-08 is closed.

No runtime finding is open in the Phase 1B patch.

The patch sidecar is correct.

The embedded `main.sh` is correct.

The builder is deterministic.

The project gate returns `PASS=31 FAIL=0`.

The reviewed patch can be the Phase 1B artifact for a single-device canary.

However, P1B-07 is not fully closed.

The remaining P1B-07 conditions are documentation conditions.

They do not change the shell runtime result.

The handoff still contains old function names and old e2e values.

The design document still contains an old test plan and an old status line.

The patch README still calls 403 MB a hard limit.

The current status file still says that implementation is pending in one location.

Correct these records before the canary handoff.

These text-only corrections do not require a patch rebuild.

They do not require another 112-assertion run.

They do not require another destructive e2e run.

If no source or test file changes, a fourth runtime review is not necessary.

The version 1.2.2 package remains outside the patch rollout.

Do not deploy that package.

---

## 2. Finding disposition

| Finding | Round 3 status | Result |
|---|---|---|
| P1B-01 | CLOSED | The e2e driver now gates synthetic files, exact counts, cleanup, patch check, and recovery messages. |
| P1B-02 | CLOSED | The KEEP value is bounded before arithmetic. |
| P1B-03 | CLOSED | Unsafe glob metacharacters cannot become family selectors. |
| P1B-04 | CLOSED | Count and age deletion failures produce accurate WARN messages. |
| P1B-05 | ACCEPTED HOLD | The installer still accepts only version 1.2.1. Package 1.2.2 remains NO-GO. |
| P1B-06 | PACKAGE HOLD | The old package had xattr headers. The latest package needs an artifact-specific record. This does not block patch-only rollout. |
| P1B-07 | OPEN, Low | Current documents still have several stale statements. This is the only open Phase 1B finding. |
| P1B-08 | CLOSED | Exact timestamp-shaped family selection and F12 prevent valid-prefix overlap. |

No Critical finding is open.

No High finding is open.

No Medium runtime finding is open.

P1B-07 is a release-record condition only.

---

## 3. Independent artifact evidence

### 3.1 Identity values

The reviewed values are:

| File | Identity | Lines |
|---|---|---:|
| `REVIEW_HANDOFF_PHASE1B.md` | SHA-256 `6845f3c5428b367c18639bcf49370bd53a84ab76ee39dce4b1e083375fcc1959` | 148 |
| `patches/rpz_patch_phase1b_v1.sh` | MD5 `e44052005a176071f8049d4a8a9ab948` | 591 |
| `patches/rpz_patch_phase1b_v1.sh` | SHA-256 `aa97950e8a45541b8f48bcdfa4d20c495db6d9ef4989724d064dd3470058c785` | 591 |
| `patches/build_patch_phase1b.sh` | MD5 `8cadfaa994ebfe13a2f55348b0723f36` | 303 |
| `scripts/main.sh` | MD5 `d1e1f688d939a5a5e87282605d0e3eed` | 353 |
| `tests/lab/f5_patch_1b_test.sh` | MD5 `64ee04a13fbc68372e70a3ef9338078b` | 365 |
| `tests/lab/f5_e2e_1b_controlled.sh` | MD5 `84f57120eda3b1d19756a86f43670a98` | 173 |

The handoff identity table agrees with these values.

### 3.2 Syntax, sidecar, and embedded payload

The reviewed shell files passed `bash -n`.

The Phase 1B sidecar returned RC=0.

The extracted embedded `main.sh` was byte-for-byte equal to `scripts/main.sh`.

The patch MD5 table agrees with the source payload.

### 3.3 Deterministic build

The reviewer used a clean temporary tree.

The tree contained only the required builder and source inputs.

The builder returned RC=0.

The builder reported:

```text
Total lines: 591
Embedded lines: 357
Tool logic lines: 234
SHA-256: aa97950e8a45541b8f48bcdfa4d20c495db6d9ef4989724d064dd3470058c785
```

The rebuilt patch was byte-for-byte equal to the reviewed patch.

The rebuilt sidecar was byte-for-byte equal to the reviewed sidecar.

### 3.4 Project gate

The reviewer ran `tests/check_source_consistency.sh`.

The result was:

```text
PASS=31
FAIL=0
RC=0
```

The gate confirmed the V4 artifact set.

The gate confirmed the Phase 1B artifact set.

The package checks in this gate are content-consistency checks.

They are not package-installability checks.

---

## 4. P1B-08 confirmation

### 4.1 Source result

The new code defines a fixed timestamp glob.

It has exactly eight date digits and six time digits.

The new function is `prune_family()`.

The function receives these separate values:

- directory
- literal family prefix
- literal extension
- KEEP count

The family prefix is inside a quoted shell expansion.

The timestamp glob is outside that quote.

Thus, the prefix is literal and the timestamp is the only pattern part.

For family `alpha`, the character after `alpha_` must be a digit.

The file `alpha_beta_20260801_000001.txt` has `b` at that position.

It cannot match the `alpha` selector.

The raw selector also uses the exact generated filename shape.

This is the requested minimal correction.

### 4.2 Permanent regression

F12 creates these families:

```text
alpha
alpha_beta
```

It creates 30 files in each family.

It checks these results:

- cleanup RC=0
- `alpha=24`
- `alpha_beta=24`
- newest `alpha` file remains
- oldest excess `alpha` file is absent
- newest `alpha_beta` file remains
- oldest excess `alpha_beta` file is absent
- `final/` remains unchanged

### 4.3 Independent LAB result

The reviewer ran the complete updated regression on BIG-IP Bash 4.2.

The result was:

```text
PASS=112
FAIL=0
RC=0
```

All eight F12 assertions passed.

P1B-08 is closed.

---

## 5. P1B-01 confirmation

### 5.1 Identity guards

The driver still requires all four initial controls:

- exact `--lab-only` argument
- exact hostname `cdns.ryantseng.work`
- exact confirmation string
- initial handler state active/300

There is no bypass flag.

### 5.2 Synthetic-file gates

The new `seed_one()` function refuses an existing path.

It checks file creation.

It adds the created path to the manifest before `touch -d`.

It checks `touch -d`.

Thus, an mtime failure cannot leave an untracked new file.

The driver then verifies all 120 manifest entries.

It verifies that each entry is a regular file.

It verifies that each mtime is more than two days old.

The first e2e incident condition is now gated.

### 5.3 Patch and acceptance gates

The driver records apply RC.

It records check RC separately.

It also checks the expected check text.

The driver requires exactly 24 files in all four seeded families.

Zero files cannot pass.

### 5.4 Cleanup and recovery

The driver checks for manifest entries after removal.

It clears the manifest only when no entry remains.

The EXIT path retries remaining manifest entries.

The EXIT path reports a handler-restore failure.

The EXIT path reports a configuration-save failure.

The normal path still checks save, handler status, and interval.

### 5.5 Test evidence

The handoff reports five refusal cases with RC=2.

It reports zero state change for each case.

The handoff reports one pre-existing-path injection case.

That case returned RC=1 before the first synthetic-file write.

It restored handler active/300.

It kept the DataGroup revision unchanged.

The handoff reports one successful e2e result:

```text
PASS=20
FAIL=0
revision 22 -> 23
DataGroup size=2243094
```

The reviewer independently repeated three no-change refusal cases.

The results were:

```text
missing --lab-only: RC=2
missing confirmation: RC=2
wrong confirmation: RC=2
```

The independent before-and-after values were:

```text
main.sh MD5: d1e1f688d939a5a5e87282605d0e3eed -> same
DataGroup revision: 23 -> 23
handler: active/300 -> active/300
```

The reviewer did not repeat the destructive successful e2e.

The source correction is direct.

The producer evidence includes the required injection and successful runs.

The LAB state agrees with that evidence.

An additional destructive run would only increase the real revision again.

P1B-01 is closed.

The driver remains LAB-only.

Do not copy this driver to a customer device.

---

## 6. P1B-07 — Low — Documentation correction is incomplete

### Status

P1B-07 is partially corrected.

The artifact identity table is current.

Process Section 22 is marked as historical.

Process Section 24 contains the new response.

The regression header is current.

STATUS Section 11 is marked as implemented.

Several current statements are still stale.

### 6.1 Handoff conditions

`REVIEW_HANDOFF_PHASE1B.md`, line 78, still names `prune_by_count()`.

The final function is `prune_family()`.

Lines 93 through 95 still describe only F1-F7 and T1-T2.

The final regression contains F1-F12 and T1-T4.

Lines 98 and 99 still describe the old e2e deletion and revision values.

The final e2e result is revision 22 to 23.

### 6.2 Design-document conditions

`docs/PHASE1B_DESIGN_20260823.md`, line 4, says that only review round 1 is complete.

It points only to process Sections 22 and 23.

The final record also needs process Section 24.

Line 38 calls 403 MB a disk upper limit.

Line 168 still names `prune_by_count`.

The final function is `prune_family`.

The test plan at lines 245 through 288 still stops at F7 and T2.

It still accepts `<=24` in the e2e plan.

The final test set includes F8-F12 and T3-T4.

The final seeded-family rule is exactly 24.

Line 319 again calls 403 MB a disk upper limit.

Use `estimated use` instead.

### 6.3 Patch README conditions

`patches/README.md`, line 231, still says `hard disk upper limit`.

This contradicts the P1B-07 response.

The value is an estimate from the current zone count and average file sizes.

Line 257 says F1-F11.

The final regression includes F12.

Line 266 reports revision 21 to 22.

The final e2e result is revision 22 to 23.

Line 273 points only to process Sections 22 and 23.

The final response is in Section 24.

### 6.4 Status-file conditions

`STATUS_20260822.md`, line 247, calls 403 MB a disk upper limit.

Lines 250 and 251 still say that user confirmation and implementation are pending.

These lines contradict the completed Section 11 in the same file.

### 6.5 Package-record condition

The newest package seen by the project gate was:

```text
dist/rpz_local_processor_v1.2.2_20260823_071238.tar.gz
SHA-256: 0db3e50f8c0df5e44f8133f7f605fe4dc2be6af17e0992aad04caf2084b510f2
```

The reviewer did not find `LIBARCHIVE.xattr` or `SCHILY.xattr` strings in this raw archive.

The older reviewed package did contain those strings.

`dist/DO_NOT_DEPLOY.md` still gives one generic P1B-06 statement for version 1.2.2.

Make the record artifact-specific.

Do not declare P1B-06 closed only from this local scan.

If the package returns to scope, extract the exact package on F5 GNU tar and record the result.

The installer still contains:

```text
SUPPORTED_VERSIONS="1.2.1"
```

Thus, P1B-05 still makes the package NO-GO.

### Effect

These conditions do not change `main.sh`.

They do not change the patch.

They do not invalidate the 112 regression assertions.

They can confuse a maintainer or an operator.

### Required change

Correct the listed text and evidence values.

Use `estimate` for the 403 MB value.

Use `prune_family()` as the final function name.

Use F1-F12 and T1-T4 as the final regression scope.

Use revision 22 to 23 as the final e2e result.

Use process Sections 22 through 24 as the complete history.

Update the package HOLD record by exact artifact name and SHA-256.

Add a short process record for this confirmation round.

Do not change production source for P1B-07.

---

## 7. LAB final state

The reviewer removed all review-owned temporary files.

The final LAB state was:

```text
V4 check RC=0
Phase 1B check RC=0
main.sh MD5=d1e1f688d939a5a5e87282605d0e3eed
handler status=active
handler interval=300
rpztw revision=23
rpztw size=2243094
/config use=7%
raw count=17
rpztw parsed count=17
phishtw parsed count=17
rpzip parsed count=17
review temporary files=0
```

The count changed from 16 to 17 because a normal handler tick occurred.

The count remains below KEEP=24.

The reviewer did not change the DataGroup revision.

---

## 8. Canary decision

The runtime artifact `aa97950e...` is technically ready for one customer canary.

Complete the P1B-07 text corrections before the operational handoff.

Do not rebuild the patch for text-only corrections.

Do not rerun the destructive e2e for text-only corrections.

After the records are corrected, use this sequence:

1. Verify the exact V4 patch SHA-256.
2. Verify Phase 1B SHA-256 `aa97950e8a45541b8f48bcdfa4d20c495db6d9ef4989724d064dd3470058c785`.
3. Run V4 `check` on the selected customer device.
4. Run Phase 1B `check` on the selected customer device.
5. Stop the handler.
6. Wait for the RPZ process to become quiet.
7. Apply and verify V4.
8. Apply and verify Phase 1B.
9. Run the approved real-data acceptance sequence.
10. Do not seed synthetic files on the customer device.
11. Restore handler active/300.
12. Save the system configuration.
13. Observe at least one later handler tick.
14. Confirm that all temporary-file families remain at or below 24.
15. Confirm that no cleanup WARN message occurs.

Do not deploy all four customer devices together.

Do not use the version 1.2.2 package for the canary.

---

## 9. Final conclusion

The Phase 1B shell implementation is appropriately small.

It is suitable for the F5 runtime constraints.

The exact family selector closes P1B-08.

The fail-closed e2e changes close P1B-01.

The production patch runtime decision is GO.

The controlled e2e driver decision is GO for the named LAB only.

P1B-07 remains open as a Low documentation finding.

Correct P1B-07 before the canary handoff.

No source rebuild is necessary if only documents change.

No additional runtime confirmation is necessary if the patch and test hashes do not change.

Keep package 1.2.2 on HOLD.

Keep CR-10 as Phase 2 P0.

The reviewer did not modify production source code in this round.

The reviewer added only this review document.
