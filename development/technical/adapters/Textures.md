# Metal: textures, block decoding and render diagnostics

| File | Lines | Role |
| --- | ---: | --- |
| `BCTextures.m` | 600 | substitutes uncompressed textures for BC formats on GPUs that cannot sample them, and decodes at upload time |
| `BCDecode.c` | 516 | plain-C BC1–BC7 block decoders plus their tables and a rect dispatcher |
| `BCDecode.h` | 62 | the decoder's whole interface |
| `StorageModes.h` | 14 | `Managed` → `Shared` mapping |
| `RealFunction.h` | 20 | the system function behind a wrapper of the same name |
| `RenderDiagnostics.m` | 40 | per-pass and per-draw accounting, capture mode only |

---

## 1. `BCTextures.m` — 600 lines

### 1.1 The contract (1–26)

The header is the specification, and every rule in it is enforced below. Every Mac GPU
samples BC1–BC7, so a macOS guest creates BC textures unconditionally; on iOS support is
per device (`supportsBCTextureCompression`, iOS 16.4) and an A16 has none — Metal aborts
at the first BC descriptor. So the adapter creates the texture in the uncompressed format
that will hold the decoded texels, and decodes on the CPU. Line 11: `replaceRegion:` both
forms decode immediately. 12–14: a buffer→texture blit is decoded into a staging buffer
**at commit**, the last moment the guest may still write the source. 15–16: texture→texture
copies are clipped to the mip extent because a compressed copy may round up to whole
blocks. 17: views and heap textures too, with heap sizes asked in the stored format.
19–20: the guest keeps seeing the format it asked for; Metal's own code sees the stored
one. 21–25: what is *not* covered, each logged once — readback (`getBytes:` zeros, copies
to a buffer dropped), cross-format copies, CPU-unreadable sources, `MTLIOCommandQueue`,
Metal 4 encoders. 26: on a device with BC support nothing is installed at all.

### 1.2 Telling the guest one thing and Metal another (64–109)

`AKBCTextureInfo` (66–70) holds the requested format and the decoder kind; its presence as
an associated object **is** the marker that a texture was converted. `infoOf` (78–85)
returns it by scanning a short list of registered subclasses (typically one to three), so
the test "was this converted" is an atomic load plus `object_getClass`.

`texturePixelFormat` (100–105) is the mechanism: line 102 answers the **stored** format
when the call is re-entrant or when the immediate caller's return address lies inside the
dyld shared cache — that is, when *Metal itself* is asking, and its validation must see the
truth; line 103–104 answer the **requested** BC format to everyone else. `calledBySystem`
(59–62) is what makes that distinction: it masks the return address to 47 bits (a signed
return address is not comparable as-is) and tests it against the envelope of the shared
cache's `__TEXT` segments, computed once by `findSharedCache` (44–58) from the Mach headers
of `MH_DYLIB_IN_CACHE` images, taking only `__TEXT` and widening it to an envelope.
`textureClass` (106–109) reports the superclass, exactly as KVO does, so the guest never
observes `AKBCTexture_MTLTexture2`.

`insideTexture` (96–98) is a thread-local depth counter raised around every call that must
reach the real texture, so our own re-entrant calls are not re-intercepted.

### 1.3 The immediate decode (114–164)

`uploadDecoded` (117–148) is the body of both `replaceRegion:` forms: read the mip
dimensions with `insideTexture` raised (119–124), clip the region to the mip (125–128),
compute the decoded row stride (130), then split the upload into **bands** whose temporary
is bounded at 4 MiB (131–132) so memory never scales with the texture. Per depth image and
per band (136–147): decode the band (140) — advancing the source by *whole block rows*,
because the guest's `bytesPerRow` is per row of blocks, not per texel row — and upload that
sub-region once through the real implementation with `insideTexture` raised, then free the
band. Allocation failure returns without uploading, leaving the region empty rather than
half-written.

`textureReplaceSlice` (149–154) and `textureReplace` (155–164) call it; the no-slice form
derives `bytesPerImage` as `bytesPerRow × ceil(height/4)` because depth images follow each
other a whole block-image apart.

### 1.4 Readback, views, subclasses (166–293)

There is no BC encoder, so readback cannot be produced and writing decoded texels into the
guest's buffer would overflow it. `zeroBlocks` (168–175) therefore zeroes the *compressed*
size the guest's buffer can hold, logs once, and the getters (176–192) do that.

Views (194–243) follow the same rule as textures: create the view in the stored format,
then convert the result so it too answers the BC format — for all three
`newTextureViewWithPixelFormat…` forms and, guarded by the simulator SDK and iOS 26
availability, the descriptor form, whose descriptor is copied before its format is
rewritten because it belongs to the caller.

`subclassFor` (245–277) creates one subclass per **concrete** texture class, capped at 32,
named `AKBCTexture_<base>`, adding only those of the ten overridden selectors the base
actually implements (with the base's own type encoding), and publishing the class into the
array before bumping the count so a reader that sees the count never sees a half-written
slot. `converted` (279–293) attaches the info **before** `object_setClass`, so there is no
window in which the subclass is visible without its info; if the subclass cannot be made,
the texture is returned untouched — degradation is an uncompressed texture without the
format lie, never a crash.

### 1.5 Hook table, creation, capability (295–364)

`original` (303–309) walks the receiver's class chain for the hook recorded for that exact
class and selector; `hook` (310–322) refuses to record our own replacement as an
"original" (that would recurse forever) and publishes the original before replacing.

`storedDescriptor` (324–330) copies and rewrites a BC descriptor, returning nil for
non-BC (the "chain unchanged" signal). `newTexture` (332–337) and `newTextureAtOffset`
(339–344) create with the copy and convert the result against the guest's format.
`heapTextureSize` (345–348) asks the size **in the stored format**, so the heap reserves
room for the decoded texels. `supportsBC` (361–364) tells the guest YES and Metal the
device's real answer.

### 1.6 Deferred blit decoding (366–483)

`AKBCUpload` (367–390) is one pending buffer→texture copy: the guest's source buffer (kept
alive by the strong ivar), the staging buffer, the strides, the kind and the clipped
geometry. `-decode` (377–389) first computes the highest byte it will touch and refuses
(lines 380–384) when `contents` is NULL (a `Private` buffer) or the geometry would read past
the source — the bounds check that protects a buffer the guest sized for compressed data —
then decodes each depth image into the staging buffer.

`stageUpload` (433–462) clips, allocates a `Shared` staging buffer of exactly the decoded
size, attaches the upload to the owning command buffer's list (found through the blit
encoder's owner, 453–460) and re-issues the copy from the staging buffer. If there is no
owner it decodes immediately and proceeds (454).

`commitCommandBuffer` (417–429) is where all queued uploads decode: one associated-object
lookup for the common case of a frame with no BC streaming (418), the association cleared
first so a second commit cannot decode twice (420), the list copied under its own lock
(421–422), the decodes run on the committing thread **before** any work is submitted
(423), and the completion handler captures the pending list so the staging buffers stay
alive until the GPU is done (424–426) — which matters for command buffers created with
unretained references.

### 1.7 Copies, install, setting (485–600)

`reinterpreted` (486–491) is the rule for copies: neither side converted, or both converted
to the same texel size, is an ordinary copy; anything else is a bit reinterpretation of
decoded texels and is dropped with one log. `copyTextureRegion` (493–510) also clips width
and height to the smaller mip remainder, because a compressed region may legally overhang
into whole blocks while an uncompressed one may not. Texture→buffer copies are dropped with
a log (521–535).

`fallbackSetting` (558–565) reads `TOLKARA_BC_FALLBACK`: `auto` (default), `on` (force, for
testing on a capable device), `off`, and anything else logs and falls back to auto rather
than guessing. `AKInstallBCTextureFallback` (572–600) runs once; on a device that can sample
BC it returns without installing anything unless forced. It locates the shared cache, hooks
the four device entry points (586–589), and creates throwaway command buffers to discover
the concrete command-buffer classes (590–595), then creates and ends one blit encoder so the
encoder class is hooked before the guest asks for one (596–597).

---

## 2. `BCDecode.c` — 516 lines

Plain C, no Metal dependency, tested on the Mac by `tests/test_bc_decode.c`.

- **Format arithmetic (6–63).** `AKBCKindOfPixelFormat` maps each BC format to a kind
  (sRGB variants share the kind, because only the transfer function differs).
  `AKBCDecodedPixelFormat` answers the sRGB question first so sRGB-ness is preserved, then
  picks the container: RGBA8 for BC1/2/3/7, R8 for BC4, RG8 for BC5, RGBA16Float for BC6H.
  `AKBCBlockBytes` (8 or 16) and `AKBCTexelBytes` (1, 2, 4 or 8) are what make every size
  computation in `BCTextures.m` correct without per-format special cases.
- **BC1/2/3 colour (65–95).** Endpoints split 5/6/5 and expanded by bit replication (the
  exact expansion hardware uses), a four-entry palette, four-colour mode when `c0 > c1` and
  three-colour plus punch-through otherwise, interpolants in 64ths with a `+32` round before
  the shift — the form Apple GPUs produce.
- **The 8-byte interpolated channel (97–132).** `sevenths`/`fifths` give the weights in
  64ths; eight-value and six-value modes; signed variants use `divide_rounded` because C's
  `/` truncates toward zero and would bias negative interpolants, and clamp at −127 (the
  literal endpoints are −127/127, not −128).
- **Bit reader (136–144).** Two 64-bit loads make the whole 128-bit block addressable; a
  zero-width read consumes nothing (so modes without a field need no special case), and
  reads beyond 128 bits return 0.
- **Tables (146–233).** Two- and three-subset partitions as bitmasks, anchors (the texel
  whose index is stored with one fewer bit), and weight tables for 2-, 3- and 4-bit indices.
- **BC7 (235–306).** One row per mode (subsets, partition/rotation/selector bits, colour and
  alpha widths, endpoint and shared p-bits, index widths); the mode is the number of leading
  zero bits, eight zeros being the reserved encoding (transparent black); endpoints are read
  channel-major, p-bits become the low bit of every channel, anchors drop a bit, and modes 4
  and 5 swap alpha with a colour channel by rotation.
- **BC6H (308–455).** Fourteen modes expressed as bit-field maps, because each mode's header
  is laid out differently; the mode code is 2 bits extended by 3 only when the first two are
  not 0 or 1; endpoints are delta-transformed modulo the endpoint width; `unquantize` and
  `finish_half` map to half-float; alpha is always 1.0.
- **Dispatch (457–516).** `AKBCDecodeRect` clips partial blocks so exactly `width × height`
  texels are written and never past them, and refuses a stride too small for the rectangle.

---

## 3. The three small headers

`BCDecode.h` (62) is the decoder's interface and states the pixel-format numbers it uses
(it must compile without a Metal header, and `tests/test_bc_textures.m` checks each against
Metal's own constant). `StorageModes.h` (14) is three expressions: `Managed` → `Shared`,
everything else unchanged, with bits 4–7 masked, translated and written back so every other
option bit survives. `RealFunction.h` (20) resolves the system function behind a wrapper:
`dlsym(RTLD_NEXT)` first, then `dlopen(RTLD_NOLOAD)` of the named library, and never the
wrapper itself — the recursion guard is an explicit comparison.

---

## 4. `RenderDiagnostics.m` — 40 lines

Installed by `Presentation.m:127`, *after* the `if (!sample) return;`, so it exists only
under `--sample-native`. It hooks `renderCommandEncoderWithDescriptor:` on the concrete
command-buffer class, then installs eight replacements on the encoder's concrete class
found from a live object (so no class name is assumed): `setRenderPipelineState:` and the
three unindexed and three indexed draw forms. Each draw increments a count and adds
`count × instances` vertices; each pipeline change stores the pipeline's label.

---

## 5. Per-frame cost — evidence

**Nothing in `BCDecode.c`, `BCDecode.h`, `StorageModes.h`, `RealFunction.h` or
`LibraryContainer.h` is per-frame:** they are tables, pure arithmetic, one `dlsym` and one
container rewrite on the library-load path.

**`BCTextures.m` is installed once (`Devices.m:200`) and does nothing unless the device
cannot sample BC or `TOLKARA_BC_FALLBACK` forces it (578–581).** Where it does run, the
cost shapes, from the code's own loop bounds:

| Entry point | Lines | Cost shape |
| --- | --- | --- |
| `-pixelFormat` | 100–105 | constant: one IMP lookup, one 47-bit mask, two compares, one associated-object lookup. The highest-frequency hook in the file. |
| `replaceRegion:` (both forms) | 149–164 → 117–148 | per block, synchronous, with a ≤4 MiB temporary: for a 1920×1080 BC1 plane that is 129 600 block decodes, one 4 177 920-byte `malloc` and 2 real uploads. |
| `copyFromBuffer:…toTexture:` | 433–483 | **one `MTLBuffer` allocation per call** (8 294 400 bytes for 1080p RGBA) plus two `@synchronized` acquisitions; the decode is deferred. |
| `commitCommandBuffer` | 417–429 | **every command buffer**: one associated-object lookup when nothing is staged; when uploads exist, the decodes run on the committing thread before submission. |
| texture→texture copies | 493–520 | constant per call, no pixels: two `infoOf` scans and, only if a side is converted, six property reads and two clamps. |
| `getBytes:` | 168–192 | per block-row `memset` of the compressed size. |
| blit encoder creation | 399–416 → 537–545 | per encoder: seven `hook()` calls, each a lock and a linear scan, plus one `AKBCOwner` allocation. |

**`RenderDiagnostics.m` is per-frame in its entirety**, and expensive per draw: `recordDraw`
does one associated-object lookup and three allocations per draw (two `NSNumber` boxes and
the dictionary store), and `encoder` builds a dictionary with five keys, an `NSArray` and a
`mutableCopy` — four allocations — per render pass. A 1 000-draw pass is roughly 3 000
allocations and 1 000 lookups per frame. It must never be enabled during a timing
measurement, and any measurement taken with `--sample-native` is contaminated by it.

**Verdict.** On a device that samples BC (every M-series iPad), none of this file is
installed. On a device that does not, the decode is real work on the guest's own threads —
but it delays *submission*, not presentation, and it happens only for textures the guest
uploads while the game is already running.
