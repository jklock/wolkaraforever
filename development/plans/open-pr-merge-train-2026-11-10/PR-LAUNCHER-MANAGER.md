# Launcher Manager UI-contract amendment — v1.0.9

Create a new maintainer-authored PR, separate from #23/#26. It is the sole authorized launcher-contract amendment in this train.

Add wow.box.launcherManager in the former wide-grid spacer beside UI Manager and after UI Manager in one-column layout. Add wow.launcher.interfaceMode with iPadOS default and iOS on Duo only. Persist the selection; mode changes never install, disable, remove, or update packages.

Keep the existing recommendation row identifier. Its title is Install Recommended Add-ons (Mac-Ever) for iPadOS and Install Recommended Add-ons (WolkaraRoue) for Duo. Tap opens Add-On Manager, never silent install. Mac-Ever filters CurseForge project 1733200 and retains the existing explicit API-key/install flow. WolkaraRoue shows bundled ZIP version/hash and an explicit transactional local Install action; malformed/unexpected archives fail closed.

Update UI policy, baseline spec, device contract, English/German/French strings, review record, fixture assertions, inventory, and approved screenshots. Test default, selector, missing key, local success/failure, no removal on switch, largest German type, both simulators, test iPad, exact-main release. Rollback: v1.0.8.
