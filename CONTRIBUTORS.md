# Contributors

> **Reviewed 2026-11-08.**

WolkaraForever credits the people whose work it carries. [NOTICE.md](NOTICE.md) holds the
licence text and the reference material; this page holds the people. Every name below has
commits or an integrated pull request behind it, and its row says which part of the project
that work is and where the work lives today — in `main`, in the vendored engine, or in the
history.

| Contributor | Work | Where it lives |
| --- | --- | --- |
| **John Klockenkemper** ([@jklock](https://github.com/jklock)) | Maintainer. The product layer in `wolkaraforever/`, the maintained patch set and `overlay.map`, the tools that prepare, gate, install and test, and review of every path in [`.github/CODEOWNERS`](.github/CODEOWNERS). | `main` |
| **Vasilii Kharitonov** | Tolkara: Mach-O loading, guest memory, native execution, and the macOS API translation layer the client actually runs on. | `platform/`, authored before the vendor split |
| **Alexander Kharitonov** | Tolkara: the three executable-memory backends as execution modes of the build, generic builds with no particular application, reading an application's own nib on the device, and the suites and tooling around them. | `platform/`, authored before the vendor split |
| **Javier Lasso** ([@fJavierLasso](https://github.com/fJavierLasso)) | Wolkara: the WoW-first launcher, the on-device CDN lifecycle, and the mobile-input direction this repository continues. | `wolkaraforever/`, authored before it became a layer |
| **[@pookee](https://github.com/pookee)** | The iPhone form factor and its touch input: direct touch (tap a left click, hold a right click, drag the camera, pinch to zoom), the folding top toolbar, the compact on-screen gamepad, French for the app and for the game language, and the Interface mobile add-on. | History: integrated in PR #20, rolled back with that batch by `1e50c7a` |

The upstream lineage is retained rather than renamed: Tolkara is vendored byte-identical to
[upstream](https://github.com/tolkara/tolkara) under `platform/`, and Wolkara's history is
part of this repository's own. See [Credit and lineage](README.md#credit-and-lineage) and
[NOTICE.md](NOTICE.md).

## Automation and assistance

Two identities in the history are not people and are not listed above:
`Repo Assistant <assistant@wolkara.local>` prepared commits mechanically, and
`Co-Authored-By: Claude` trailers record that a commit was prepared with AI assistance. They
say how a change was made, not who is answerable for it; the human author of the commit is.

## How a contribution is credited

- A commit you authored or co-authored that reaches `main` puts you here. `Co-Authored-By:`
  in the commit trailer is enough, and it is the mechanism pull requests already use.
- A compatibility report or a bounded device result that changes the code or a documented
  claim is credited the same way, when the person wants to be named.
- Work you contribute that is later rolled back or superseded stays here: the record is of
  the contribution, not of the current tree.
- If your change is derived from someone else's code, add its licence to
  [NOTICE.md](NOTICE.md). Contribution credit and licence attribution are different records
  and both are required.

Do not add a name for someone who has not agreed to be listed, and do not list an email
address: a GitHub handle or a name is the whole entry.
