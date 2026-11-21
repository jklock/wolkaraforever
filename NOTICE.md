# Notices

> Verified: 2026-11-21 · Source: `8375cbb`

WolkaraForever continues Wolkara by fJavierLasso and uses the Tolkara runtime by Vasilii Kharitonov and Tolkara contributors. The repository retains the applicable MIT license and third-party notices.

The project uses Apple public SDK frameworks, system zlib, and Python standard-library components. It does not include game files, Apple operating-system components, signing material, or extracted system assets. The only certificates in a build are public trust anchors — no private keys — that a build exports from the builder's own Mac (`CompatibilityRootCertificates.plist`), because the game validates Battle.net's certificate against macOS's system root certificates.

The Forever manifest and archive readers were informed by public format references, including TACTSharp. See the source headers and license files for exact attribution obligations.
