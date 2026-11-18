# Play by touch on iPad (iPad touch and TouchPlay)

> Verified: 2026-11-18 · Source: `upstream/ipad-touch`

**iPad touch** is an interface mode for iPads played with the TouchPlay add-on. TouchPlay draws the
game's touch buttons, and WolkaraForever turns a finger on a button into that button's key. There is
no on-screen controller in this mode and no pointer to steer: each button is a key, the world is
played by touch, and a walk stick appears under your thumb.

## Choose iPad touch

1. Open **Launcher Manager** and choose **Interface Mode**.
2. Pick **iPad touch**. Automatic never picks it; it is always chosen on purpose. It is offered on an
   iPad only.
3. Under the mode row, choose **Install Recommended Add-ons (TouchPlay)**. The Add-On Manager opens
   on the TouchPlay package that ships with the app; press **Install**. Nothing is installed until
   you do.
4. Start the game. TouchPlay saves its button list for WolkaraForever when you log out or type
   `/reload`, so the buttons work by touch from the next game start. Until then the game says "Touch
   buttons not found" and touches are plain clicks.

If the game closes unexpectedly twice in a row in iPad touch, WolkaraForever goes back to iPadOS and
tells you once. Choose iPad touch again to try once more.

## Play by touch

- **Buttons.** A touched button lights up with a soft gold glow. Lifting your finger on it uses it;
  keeping it there fills a ring and then opens its card; sliding off a spell aims it with your
  finger: let go on the ground to cast there, or on another button to stop.
- **The world.** Tap to select, tap again nearby to talk, loot or attack, keep a finger still to see
  what is under it, drag to look around, and pinch with two fingers to zoom. A touch right at the
  screen's edge does nothing.
- **Walking.** Put a thumb in the outer third of the screen on the side away from your spells, below
  the top band of cards: the walk stick appears under it. To keep running, slide up past the ring
  onto the lock above it and hold for a moment, then let go; touch the stick area or the lock again
  to stop. Walking uses the game's own W, S, A and D keys, so keep those bound to moving.
- **Windows.** With a game window open (bags, character, a vendor), the buttons rest: a tap is a plain
  click and a still finger is a right click. The walk stick keeps working in its own corner.
- **Only in the world.** On the login and character screens every touch is the game's own plain touch.
  TouchPlay tells WolkaraForever when you enter or leave the world.
- **Toolbar.** The toolbar stays at the top centre, in a band TouchPlay keeps clear. It has no
  controller buttons in this mode. Its cursor button turns a trackpad on instead of direct touch; in
  iPad touch that switch is its own, off until you turn it on there.
- **Leaving the app.** A call, Control Centre or the app switcher lets go of every key a finger was
  holding, so nothing keeps running or casting while you are away.

## Chat and the password

To chat, tap TouchPlay's chat strip (or the toolbar's keyboard button), pick Say, Party, Guild,
Whisper (a reply to the last whisper) or Yell above the keys if you like, type, and press the gold
**Send** or the keyboard's Send key. Tap the game to close the chat without sending. In iPad touch
this is the chat; the review-then-send Chat Composer of the other interfaces is not used here.

At the login screen, the password box brings up the keyboard and the game slides up so the box stays
in sight. Type the password: each key goes into the game's box as you type it, and Return logs in.
Passwords and Face ID AutoFill are not offered here: the game's login refused a filled password.
WolkaraForever never keeps, logs or copies the password. In the account-name box the keyboard's key
reads **Next** and moves to the password box; it never logs in.

## Other interfaces

Nothing here changes iPadOS, iOS or iOS on Duo. Their toolbar, controller overlay, direct touch,
Chat Composer and Add-On Manager are the same as before, and the Launcher Manager card shows the
TouchPlay row only while iPad touch is the mode.
