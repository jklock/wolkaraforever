# Supported source-built enablement

## Goal

Support two clone-from-source installation lanes without distributing a prebuilt IPA:

1. an Xcode-installed integrated build using Developer service; and
2. a locally packaged unsigned Diagnostics IPA, re-signed by the user's sideloading tool and
   launched with External JIT, that is fully functional through the normal game experience.

## Implementation

- Remove release automation and release-note links that publish or advertise a prebuilt IPA.
- Promote the existing Tolkara-backed `package_ipa.sh` flow into one clearly named, provider-neutral
  WolkaraForever IPA builder. It must produce a rootless, generic, unsigned Diagnostics IPA and
  structurally verify it before sideloading.
- Certify **AltStore Classic** and **SideStore** as the two supported sideload providers. Document
  each provider's full lifecycle: package, sideload/re-sign, JIT enablement, runtime proof,
  seven-day free-ID renewal, changed bundle identifiers, and recovery. SideStore requires
  LocalDevVPN for install, update, and refresh; AltStore Classic uses AltServer over USB or Wi-Fi
  for those operations. The StikDebug JIT route requires LocalDevVPN with either provider.
- Distinguish those provider/JIT prerequisites from WolkaraForever's Developer-service tunnel;
  neither tunnel is silently required by the other lane.
- Keep Developer-service enrollment exclusive to the integrated lane. Local signing remains an
  advanced engineering route, not a third customer workflow.
- State physical evidence by device, OS, signing tier, game build, and execution mode. Simulator
  Duo evidence remains UI evidence only, never proof of sideloading, JIT, Metal, or phone hardware.

## Verification

- Cover malformed packages, rootless packaging, missing JIT, attached debuggers, unavailable
  arenas, changed bundle identifiers, and successful runtime evidence in focused script tests.
- Run the required iPhone Duo and iPad Pro M5 simulator suites.
- Validate both source-built lanes on the available paid physical device through install, launch,
  JIT enablement, login, world entry, ordinary in-world input/rendering, restart, and recovery.
  The External-JIT IPA is not accepted merely because an arena becomes executable; it must complete
  the same normal user journey as the integrated build. Describe the free-ID lane's seven-day
  lifecycle and capability limits without presenting paid-device observations as free-tier evidence.
- Run the External-JIT acceptance sequence once through AltStore Classic and once through SideStore,
  recording the provider, JIT enabler, LocalDevVPN state, signing tier, source SHA, device, OS, and
  game build with each result.

