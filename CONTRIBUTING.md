# Contributing

Most useful: API coverage for a new application, a compatibility report, a device result.

## Ground rules

- Never commit third-party application code, assets, shaders, captured memory, page
  containers, or anything copied out of macOS or iPadOS. Tests use our own fixtures in
  `platform/testguest/` and `platform/tests/`.
- Never patch, re-sign or repackage an application's executable. Tolkara signs its own
  code. With Local signing each user builds and signs their own page container, on their
  own machine, for their own iPad.
- No memory access beyond loading, no input automation, no anti-cheat, licence or
  integrity workarounds — see "Policy" in the [README](README.md). That rule is about the
  application, not this repository: fixtures, the device matrix, `pilot.sh` and the app's
  self-tests drive *our* code with synthetic input, and more of that is welcome
  (`wolkaraforever/Shell/SelfTest.h`).
- Never commit signing teams, device identifiers, pairing records, provisioning profiles,
  credentials, or anything from `build/` and `logs/`. Personal settings go in the ignored
  `local.env`.
- If your change is based on someone else's code, say so and add its licence to
  [NOTICE.md](NOTICE.md). Reading public protocol documentation is fine.

## Workflow

```bash
wolkaraforever/tools/test_emulation.sh
```

must pass. It runs with `-Wall -Wextra -Werror` under ASan and UBSan. Add a focused test for
any memory bound, malformed input, protocol failure or adapter behaviour you touch. Tests
are standalone executables or Python `unittest` files named `test_*.{c,m,swift,py}`, under
`platform/tests/` or beside the layer code they cover.

Style: four spaces in source, two in YAML; match the surrounding code and do not reformat
unrelated lines. Keep the module prefixes (`gm_`, `gi_`, `ng_` in the runtime, `AK` in the
translation layer, `TK` in authorization).

Layer work goes in `wolkaraforever/` — a patch if you must change a platform file, an
overlay if it is ours. Never edit `platform/` by hand. See
[wolkaraforever/README.md](wolkaraforever/README.md).

Pull requests should state the problem, the resulting behaviour, the commands you ran with
their results, and what is still untested. A simulator pass does not prove Metal or native
execution; name the device.

## Supporting a new application

1. Build with your executable (`GUEST_EXE`); `build/native-*/SURFACE.md` lists every macOS
   symbol it imports and which are missing.
2. Run it and read `Documents/native-guest.log`. Generated stubs log the first call to each
   unimplemented function.
3. Implement what it needs under `platform/translation/<Framework>/`, with a test.
4. Add a profile under `profiles/` and a row in [COMPATIBILITY.md](COMPATIBILITY.md).
