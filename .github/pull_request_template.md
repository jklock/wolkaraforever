## Change

Describe the user-visible or technical behavior changed.

## Boundary

- [ ] No direct edit to `platform/`; any platform change is a patch/overlay and passes the layer gate.
- [ ] No game data, credentials, signing material, pairing records, device identifiers, or generated output is included.
- [ ] No game automation, integrity workaround, or runtime inspection beyond the project policy is introduced.

## WolkaraForever UI review

- [ ] This PR does not touch protected UI paths, or it has a review record in
  `development/reviews/ui/` with classification `none`, `additive`, or `ui-contract-amendment`.
- [ ] Existing launcher/control elements and existing golden screenshots are unchanged.
- [ ] Any new optional UI state has a setting/default-state explanation, localized text, named
  golden baseline, and iPhone Duo + iPad Pro 13-inch (M5) evidence.
- [ ] Any visible launcher/control claim has physical iPad Pro 12.9-inch (5th generation)
  Device Hub evidence and ends at normal launcher home with the app running.

## Verification

Commands run and results:

```text
```

Device evidence, if applicable: source SHA, device, iPadOS, client build, execution mode, and
what a person observed.

## Documentation and risk

- [ ] Documentation is updated, or no documentation change is needed.
- [ ] Remaining gaps, deferred checks, and risks are listed below.

<!-- State “none” when there are no remaining gaps. -->
