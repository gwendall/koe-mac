# Koe brand

Koe is a tiny macOS menu bar app: hold a key, talk, and the words land where
you type. Pixel letters, a candy gradient, a little chiptune, one character
with a face. Made by Gwendall: the signature, in the menu, the About line and
the site's footer, is **Made by Gwendall** (gwendall.com).

Koe (声) is Japanese for "voice". Always pair the name with what it does
("Koe - talk, it types"), because the name alone does not say it.

## Name

- Product: **Koe**. In prose, "Koe", never "KOE" or "koe".
- Wordmark: `KOE` set in Silkscreen, uppercase, tracked like all Silkscreen
  (see Type).
- Bundle identifier: `fm.koe.mac`.

Koe is the evening and the voice: a chat bubble on bubblegum, cherry and
violet.

## Voice

Short, plain, friendly. Say what happens to the words, not what the app is.

- Headline: **Talk. It types.**
- One-liner: Hold a key, say it, and your words land where your cursor is.
  On your Mac, offline, in about a tenth of a second.
- A dictation shows no words: a small candy pill low in the middle of the
  screen, five bars in ink. Flat and gray when no voice comes in, dancing
  with the voice, lying down in ink when the key comes up (a wave only if
  the words take over half a second), a pixel check when they land. The words appearing are the confirmation; no "typed" note.
- The pill from the menu bar is for what Koe has to say: copied (with the
  words' first few), no sound, recovered, a permission missing.
- First launch: **HI, I'M KOE** - Hold Fn and talk
- The app speaks the Mac's language, as Wham does.

## Colors

| Token | Value | Use |
| --- | --- | --- |
| bubblegum | `#ff6fae` | gradient start |
| cherry | `#ff7a7a` | gradient middle |
| violet | `#b07bff` | gradient end |
| ink | `#1a0b17` | the outline, text on candy |
| butter | `#fff1b8` | the bubble's face, as on Wham's sun |
| blush | `#ff8fc8` | cheeks and tongue |
| night | `#0f0a14` | dark backgrounds |
| pill | `#141414` | the dark pill |
| glow | `rgba(255, 80, 160, 0.35)` | the glow under candy elements |

The gradient runs from the top left to the bottom right on square things (the
icon), and from left to right on long ones (pills, bars, words): bubblegum,
cherry, violet. Cool or pale gradients were tried and left out: they read as calm or
cold, and butter drowns in peach.

## Type

As Wham: **Silkscreen** (SIL Open Font License 1.1), uppercase, at multiples
of 8 px, tracked -1/8 em; a rounded sans for the rest (SF Pro Rounded in the
app, Nunito on the web).

## The character

A chat bubble, the kind you send: three corners round, the bottom right one
square. In every messaging app your own messages sit on the right with their
tail at the bottom right; Koe is your voice, so its square corner is there.
No tail sticks out, so the bubble stays full and compact and never reads as a
ghost.

App icon, 21 x 21, `#` ink, `o` butter, `p` blush; happy eyes, cheeks, a mouth
open on a laugh. It covers about 60% of the squircle, as Wham's sun does, so
the gradient breathes around it. The source of truth is `scripts/icon.swift`.

```
.....................
.....................
.....................
.....................
.......#######.......
.....##ooooooo##.....
....#ooooooooooo#....
....#ooooooooooo#....
...#ooo#ooooo#ooo#...
...#oo#o#ooo#o#oo#...
...#ooooooooooooo#...
...#opoo#####oopo#...
...#oooo#ppp#oooo#...
....#oooo###ooooo#...
....#oooooooooooo#...
.....##oooooooooo#...
.......###########...
.....................
.....................
.....................
.....................
```

Menu bar sprites, 11 x 11, in the menu bar's ink, the eyes and mouth cut out:

Ready (mouth closed):

```
..#######..
.#########.
###########
###.###.###
###########
###########
####...####
###########
.##########
..#########
...........
```

Listening (mouth open):

```
..#######..
.#########.
###########
###.###.###
###########
####...####
####...####
###########
.##########
..#########
...........
```

Typed (a smile):

```
..#######..
.#########.
###########
###.###.###
###########
###.###.###
####...####
###########
.##########
..#########
...........
```

## Toast

Wham's pill, word for word: 52 pt, the sprite in its round end, the Silkscreen
title over a line in the body face, for messages only. A dictation has its
own small pill low on the screen, bars and no words (see Voice).

## Sound

Wham's wave, in A major instead of E. Two notes up when Koe starts listening
(A5, E6), the same two down when it stops. Nothing when the words are typed:
they show up, and a sound after every dictation would soon wear. A refusal
falls out of the key, as Wham's. The four menu sounds are Wham's, transposed.

## Motion

Wham's springs: things arrive on a spring (ω 16, ζ 0.72), rising a few points
and growing from 0.92; they leave in 0.16 s, easing in. Letters of a title drop
in one after the other, 22 ms apart.
