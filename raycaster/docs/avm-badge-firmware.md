# avm_badge firmware: checking pack size and updating draft PR #49

The helper script is `raycaster/tools/packsizes.py`, next to this file's folder.

Written 2026-09-30 from what was actually run. The numbers below are measured, not
estimated, and dated: upstream moves, so re-measure before quoting them.

## Status on 2026-09-30

Two branches matter, in your fork (`frans-k/avm_badge`, remote `fork`) and in whatever
clone you keep it in. Its remotes are `origin` = protolux-electronics/avm_badge and
`fork` = frans-k/avm_badge.

| branch | what it is | pushed? |
|---|---|---|
| `raycaster-page` | the draft PR #49 branch, on the OLD upstream base | yes, as `fork/raycaster-page` (ef94a64) |
| `raycaster-page-mp` | upstream `main` merged in, plus relay multiplayer (2 commits) | **no** |

`raycaster-page-mp` only ever existed in a scratch clone made while writing this, in a
temporary directory. If you still have that clone, keep the work with
`git push fork raycaster-page-mp` (a new branch on your fork; it does not touch the PR).
If the clone is gone, the multiplayer part can be rebuilt from `raycaster/lib/relay_wire.ex`
and `relay_link.ex` here, using the firmware's `Badge.Chat.Socket` and `Badge.Chat.Wire`.

## Versions

Their `.tool-versions` pins Erlang 29.0.5 / Elixir 1.20.3-otp-29, which are not installed
here. What worked:

    export ASDF_ELIXIR_VERSION=1.20.4-otp-29 ASDF_ERLANG_VERSION=29.1.1

## Test the pack size (nothing is flashed)

From the root of the tree you want to measure:

    mix deps.get                      # needed whenever upstream's lock changed
    mix atomvm.packbeam               # writes ./avm_badge.avm
    python3 <this repo>/raycaster/tools/packsizes.py avm_badge.avm            # biggest modules, and FITS / OVER
    python3 <this repo>/raycaster/tools/packsizes.py avm_badge.avm aycaster   # just the raycaster modules

Their own checker, with the fork's real partition table (the slot is `main.avm`, 0xA4000 =
671,744 bytes):

    gh api 'repos/protolux-electronics/AtomVM/contents/src/platforms/esp32/partitions-elixir.csv?ref=badge' \
      --jq .content | base64 -d > partitions-elixir.csv
    python3 tools/check_partitions.py partitions-elixir.csv main.avm=avm_badge.avm   # exit 0 = fits

Always measure **against a fresh upstream baseline** in a second worktree, because the
baseline moved by 20 KB in one day:

    git worktree add ../avm_badge-base upstream/main    # or origin/main
    (cd ../avm_badge-base && mix deps.get && mix atomvm.packbeam && stat -f %z avm_badge.avm)

Compatibility (functions AtomVM lacks): `mix atomvm.check`, then compare the flagged set
with upstream's. `lists:sum/1` is missing from the fork's `lists`; `lists:append/2` and
`binary:match/2` are flagged but exist (false positives).

## Before you flash anything

`mix atomvm.esp32.flash` does **not** check the size. It wrote a 706,456-byte image into a
671,744-byte slot without complaint, overwrote the start of `alt.avm`, and the badge
boot-looped (`Guru Meditation Error ... MMU entry fault`). Run the checker above first.
Recovery: flash a build that fits (`mix atomvm.esp32.flash` from an upstream checkout).

## Measured sizes (2026-09-30, packed `avm_badge.avm`, slot 671,744)

| tree | bytes | free |
|---|---|---|
| upstream `main` at my base 886a73b (2026-09-29 morning) | 663,220 | 8,524 |
| upstream `main` 3a56cdf (after the ExAtomVM bump, #44) | 642,564 | 29,180 |
| PR #49 as pushed (ef94a64, old base) | 675,104 | **-3,360 (over)** |
| PR #49 merged onto 3a56cdf | 654,448 | 17,296 |
| ... plus relay multiplayer (`raycaster-page-mp`) | 665,032 | 6,712 |

The multiplayer part is +10,476 bytes: Link 4,992, sprites in the engine 2,100, Room 1,936,
page 1,276, Chat.Socket token 136, Badge 36.

## Update PR #49

The PR is https://github.com/protolux-electronics/avm_badge/pull/49, a draft from
`frans-k:raycaster-page`. Its description still has a section, "This does not fit in
`main.avm` yet", that is now wrong.

1. In the clone with the `fork` remote:

       git fetch origin
       git switch raycaster-page
       git merge origin/main             # merged with no conflicts on 2026-09-30

2. `mix deps.get && mix test` (1,361 passed on the merged tree), `mix atomvm.check`
   compared with upstream, then pack and run the checker as above.
3. `git push fork raycaster-page` updates the PR.
4. Fix the description (read it first, it may have changed):

       gh pr view 49 --repo protolux-electronics/avm_badge --json body --jq .body > body.md
       # replace the "This does not fit in `main.avm` yet" section with the measured numbers
       gh pr edit 49 --repo protolux-electronics/avm_badge --body-file body.md

   Numbers to put in, re-measured first: PR #49 on upstream 3a56cdf = 654,448 bytes,
   17,296 free of 671,744, confirmed by `check_partitions.py`. Drop the note about
   overwriting `alt.avm`, which only applied to the old oversize build. State that
   the size claim was wrong when the PR was opened.
5. **Page only or multiplayer?** Step 1 gives the page-only version. Multiplayer is on
   `raycaster-page-mp` (6,712 free, tried on a badge: joined the relay, 4 playing).
   That is a decision for the maintainers, who have not commented yet: who hosts the
   relay, and whether a public token and a hardcoded relay address (now
   `wss://evilgoat-relay.fly.dev`) belong in their firmware.

## Also stale

`raycaster/README.md` on the goatmire-2026-hacks `main` still says the firmware page
"does not fit yet" with the old 8.5 KB figure. It does fit on today's upstream.
