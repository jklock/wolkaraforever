# Chat Composer plan

## Outcome

Toolbar microphone, keyboard microphone and mapped-controller entry share one
native Composer with visible draft text, explicit Send/Cancel, optional configured
destinations, and exactly-once guest delivery.

## Why

Today keyboard text, dictation and trigger routing own separate portions of the
chat lifecycle. Dictation final text can arrive when chat state is unclear. The
Composer makes ownership explicit: native UI owns the editable draft; the guest
receives committed text only after Send.

## Design

Add `Chat/ChatComposer.{h,m}`. States are idle, opening, listening, editing,
ready, sending, cancelled, failed. Every recognition request has a generation;
callbacks from an old generation are ignored. Composer opens chat once, owns
Escape only when it opened chat, and never retries a failed send.

## Acceptance

Opening, edit-pauses-capture, stale callback, Send, Cancel, background and
disconnect are fixture-covered. Send injects text once, Return once and Escape
once; Cancel sends no text. Existing auto-submit users keep Classic direct until
they opt into review mode.

## Completion gate

Persisted Composer preferences and destinations migrate without altering an
existing Classic-direct user. Turning Composer off cancels ephemeral work,
restores existing entry behavior and never sends draft text. Localize every state
and action; expose VoiceOver labels, state/value and deterministic focus order.
Run voice/touch fixtures and live UI flow on iPad Pro 13-inch (M5) and iPhone
Duo simulators; on Duo verify safe-area keyboard movement, one-column layout and
Dynamic Type. Device Hub may additionally prove controller/mic/keyboard entry,
edit, Send, Cancel, background, disconnect and failed send against a harmless
chat interaction. Record source SHA, both simulator/mode outcomes and physical
status in PR Proof; keep captures local and update docs only with observed facts.
