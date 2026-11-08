# Contributors

> **Reviewed 2026-11-08.**

WolkaraForever credits, and gives repository access to, the people whose work it carries.
This page is the single record of who they are: every row is a GitHub account, and the row
says what that person did and what access the account holds here. [NOTICE.md](NOTICE.md)
holds the licence text and the reference material; this page holds the people.

## Roster

| Contributor | Access | Contribution |
| --- | --- | --- |
| **John Klockenkemper** ([@jklock](https://github.com/jklock)) | admin | Maintainer. The product layer in `wolkaraforever/`, the maintained patch set and `overlay.map`, the tools that prepare, gate, install and test, and review of every path in [`.github/CODEOWNERS`](.github/CODEOWNERS). |
| **Vasiliy Kharitonov** ([@kh4rit](https://github.com/kh4rit)) | write, invited 2026-11-08 | Tolkara author: Mach-O loading, guest memory, native execution, and the macOS API translation layer the client runs on. The history carries this account as both *Vasilii* and *Vasiliy* Kharitonov. |
| **Alexander Kharitonov** ([@haritos90](https://github.com/haritos90)) | write, invited 2026-11-08 | Tolkara: the three executable-memory backends as execution modes of the build, generic builds for no particular application, reading an application's own nib on the device, and the suites and tools around them. |
| **Javier Lasso** ([@fJavierLasso](https://github.com/fJavierLasso)) | write | Wolkara author: the WoW-first launcher, the on-device CDN lifecycle and the mobile-input direction this repository continues; pull requests #7–#9 here. |
| **pookee** ([@pookee](https://github.com/pookee)) | write | The iPhone form factor and its touch input: direct touch (tap a left click, hold a right click, drag the camera, pinch to zoom), the folding top toolbar, the compact on-screen gamepad, French for the app and for the game language, and the Interface mobile add-on. Pull request #10, and #23 open. |
| **Naosukii** ([@Naosukii](https://github.com/Naosukii)) | write | Add-on and backup managers, config synchronisation, German support, the Metal performance overlay, and USB re-enrolment: the Wolkara pull requests #2–#5. Some of those commits carry the author name *Sinan Arslanoglu* with a different address — one person with two commit identities, not two accounts. |
| **Robin Ebers** ([@robinebers](https://github.com/robinebers)) | write, invited 2026-11-08 | Download progress and recovery of interrupted downloads: pull requests #27 and #28, open. |
| **scarrdi94-ui** ([@scarrdi94-ui](https://github.com/scarrdi94-ui)) | write, invited 2026-11-08 | iPhone Duo layout, typography and quality-of-life refinements: pull request #26, open. |

Every account with a commit in this repository, an opened pull request, or an accepted
invitation has a row. A name that has no GitHub account is not given one here.

The upstream lineage is retained rather than renamed: Tolkara is vendored byte-identical to
[upstream](https://github.com/tolkara/tolkara) under `platform/`, and Wolkara's history is
part of this repository's own. See [Credit and lineage](README.md#credit-and-lineage) and
[NOTICE.md](NOTICE.md).

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
