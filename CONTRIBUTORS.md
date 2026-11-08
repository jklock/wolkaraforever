# Contributors

> **Reviewed 2026-11-08.**

This page is the record of who contributes to Wolkara, to WolkaraForever, and to forks of
WolkaraForever — every GitHub account with a commit or a pull request in one of them, pending
pull requests included — and of the access each account holds here. [NOTICE.md](NOTICE.md)
holds the licence text and the third-party references; this page holds the people.

## Roster

| Contributor | Access | Contribution |
| --- | --- | --- |
| **John Klockenkemper** ([@jklock](https://github.com/jklock)) | admin | Maintainer. The product layer in `wolkaraforever/`, the maintained patch set and `overlay.map`, the tools that prepare, gate, install and test, and review of every path in [`.github/CODEOWNERS`](.github/CODEOWNERS). |
| **Javier Lasso** ([@fJavierLasso](https://github.com/fJavierLasso)) | write | Wolkara author: the WoW-first launcher, the on-device CDN lifecycle and the mobile-input direction this repository continues; pull requests #7–#9 here. |
| **Naosukii** ([@Naosukii](https://github.com/Naosukii)) | write | Add-on and backup managers, config synchronisation, German support, the Metal performance overlay, and USB re-enrolment: the Wolkara pull requests #2–#5. Some of those commits carry the author name *Sinan Arslanoglu* with a different address — one person with two commit identities, not two accounts. |
| **pookee** ([@pookee](https://github.com/pookee)) | write | The iPhone form factor and its touch input: direct touch (tap a left click, hold a right click, drag the camera, pinch to zoom), the folding top toolbar, the compact on-screen gamepad, French for the app and for the game language, and the Interface mobile add-on. The `iphone-mobile` branch of their fork `pookee/wolkaraforever`, pull request #23 open, and the earlier #10. |
| **Robin Ebers** ([@robinebers](https://github.com/robinebers)) | write, invited 2026-11-08 | Download progress and recovery of interrupted downloads: the `feature/download-speed`, `feature/duo-mobile` and `fix/retry-interrupted-downloads` branches of their fork `robinebers/wolkaraforever`, and pull requests #27 and #28, open. |
| **scarrdi94-ui** ([@scarrdi94-ui](https://github.com/scarrdi94-ui)) | write | iPhone Duo layout, typography and quality-of-life refinements: the `iphone-duo-layout` branch of their fork `scarrdi94-ui/wolkaraforever`, and pull request #26, open. |
| **andrewfblack** ([@andrewfblack](https://github.com/andrewfblack)) | write, invited 2026-11-08 | 25 commits in their fork `andrewfblack/wolkaraforever`: external game storage and its probes, install records that fail closed, gated game-file tools for external installs, the CI-only unsigned build for untouched upstream source, and the GitHub runner Developer-service build and signing setup. No pull request opened yet. |

Every account with a commit or an opened pull request in Wolkara, in WolkaraForever, or in a
fork of WolkaraForever has a row. An account that contributed only to Tolkara does not: those
commits sit in this history because Wolkara is built on Tolkara, and they predate Wolkara's
first commit on 2026-10-01. Tolkara's authors are credited in [NOTICE.md](NOTICE.md) and in
[Credit and lineage](README.md#credit-and-lineage), which is where their contribution belongs.
A name with no GitHub account is not given one here.

The lineage is retained rather than renamed: Tolkara is vendored byte-identical to
[upstream](https://github.com/tolkara/tolkara) under `platform/`, and Wolkara's history is
part of this repository's own.

## What the access means

`write` is the collaborator role for contributing: push short-lived branches and open pull
requests. `main` is protected by the repository ruleset — pull requests, linear history, a
resolved conversation — so a collaborator's route to `main` is a pull request, never a
direct push. See [repository workflow](development/guides/REPOSITORY_WORKFLOW.md).

An invitation is listed with the date it was sent. The account joins the GitHub collaborator
list when it accepts, so that list and this page can differ in between; this page records
the intent, and `gh api repos/jklock/wolkaraforever/invitations` shows what is still pending.

## Not people

Two identities in the history are not accounts and are deliberately absent from the roster:
`Repo Assistant <assistant@wolkara.local>` prepared commits mechanically, and
`Co-Authored-By: Claude` trailers record that a commit was prepared with AI assistance. They
say how a change was made; the human author of the commit is who answers for it.

## How the roster stays current

- A commit you author or co-author, a pull request you open, or an invitation you accept puts
  you in the table, and the row says which of those it is.
- A compatibility report or a bounded device result that changes the code or a documented
  claim is credited the same way.
- Work that is later rolled back or superseded stays in the roster: the record is of the
  contribution, not of the current tree.
- If your change is derived from someone else's code, add its licence to
  [NOTICE.md](NOTICE.md). Credit and licence attribution are different records; both are
  required.

Name and handle are the whole entry. Do not add an email address, and do not add a person
who has not agreed to be named.
