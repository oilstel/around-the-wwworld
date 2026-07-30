# Around the wwworld

A small macOS browser for keeping your friends' websites close.

- **Around the world** walks the frame on its own, a couple of seconds a site.
- **Frames** can be exported as JSON and sent to someone, or dropped onto the
  window to load.
- **Notes** are stored in the JSON export. Right click a favicon to add them.
- **Dense mode** packs the favicons edge to edge; frames too full for the frame
  either turn pages or shrink the favicons to fit.

This software is based on a past `<iframe>` frame website by
[Laurel Schwulst](https://laurelschwulst.com/).

It's free. If you'd like to keep this and other things like
it going, you can support my work on
[Patreon](https://www.patreon.com/elliottcost).

## Building

Open `Web browser.xcodeproj` in Xcode and run. It targets macOS 14 and up, and
has no dependencies.

The project is set to sign with its author's Apple developer team, so you'll
want to point `DEVELOPMENT_TEAM` at your own — in Xcode, under Signing &
Capabilities — or turn signing off, before it will build on your machine.

## License

[PolyForm Noncommercial 1.0.0](LICENSE) — free to use, change and pass on for
anything that isn't commercial. Personal use, hobby projects, schools and
charities are all fine; selling it, or building it into something you sell,
isn't.

The name and icon aren't covered by that; if you ship your own version, please
give it a name of its own, and credit
[Elliott Cost](https://elliott.computer/) and
[Laurel Schwulst](https://laurelschwulst.com/).

A software by [Bell Kiosk](https://bellkiosk.website/), 2026.
