# Keyboard and dictation tasks

## 1. Prove committed Unicode delivery

Branch `fix/committed-unicode-input`. First add the composition fixture for é,
combining accent, ñ, ü, emoji, deletion, cancellation and Return. If all pass
end-to-end, make no production code change and record that result. If one fails,
add the smallest adapter seam that delivers committed strings while special keys
remain explicit. Do not inspect guest selection/text or manufacture keycodes.
Run touch-controls and translation-simulation suites, then Device Hub composition
proof.

## 2. Add speech language

Branch `feature/composer-speech-language`. Add only System, en-US, de-DE, fr-FR
and a supported current game-text locale. Validate before persisting; create the
recognizer per capture session; cancel and invalidate the prior generation before
any restart; never reopen chat. Keep on-device recognition mandatory. Gate task
hint/punctuation by SDK availability. Test migration, unsupported locale,
request construction, mid-capture change and stale callbacks; run voice suite
and physical language-switch proof.

## 3. Close the feature

Add migration/rollback fixtures: invalid stored language, unavailable recognizer,
permission denial, audio interruption, Cancel, scene background and feature
disable. Add English/German/French copy and VoiceOver assertions. Run touch-
controls, voice and translation simulation on iPad Pro 13-inch (M5) and iPhone
Duo, then `check_layers.sh`; Duo live QA covers safe-area keyboard movement and
Dynamic Type. Record Device Hub status and, if run, prove Unicode composition,
cursor-safe deletion, language change during capture, error recovery and no
automatic send. Put SHA/simulator/mode and outcomes in PR Proof; keep generated
evidence local and update docs only with observed results.
