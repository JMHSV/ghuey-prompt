# Ghuey Prompt

<img src=".github/assets/readme-banner.png" width="1280" alt="Ghuey Prompt goose logo. Your prompts, one edge away. Save once. Insert anywhere.">

A native macOS prompt library at the left edge of your screen. Save text from any app, find it when you need it, and insert it where your cursor is. Use it with T3 Code, ChatGPT, Claude, or another app that accepts pasted text.

**macOS 14+ · Apple Silicon and Intel · No account or API key** · [MIT licensed](LICENSE)

[Get started](#build-and-install) · [Shortcuts](#shortcuts-and-controls) · [Templates](#use-reusable-templates) · [Storage and privacy](#storage-and-privacy) · [Contribute](#contribute)

- **Save from anywhere.** Use a global shortcut, the Services menu, or drag text onto the screen edge.
- **Insert without switching apps.** Click a prompt or use a favorite's hotkey.
- **Make prompts reusable.** Fill template fields, attach your clipboard, or stack several prompts.
- **Keep your library with you.** Readable local JSON, optional iCloud Drive sync, and on-device titles when available.

Ghuey Prompt runs in the menu bar, with a SwiftUI shelf and AppKit windows.

## Build and install

You need macOS 14 or later, Xcode 16 or later with Swift 6, and [XcodeGen](https://github.com/yonaskolb/XcodeGen). The optional on-device title generator requires a build with the macOS 26 SDK and a Mac with Apple Intelligence enabled.

1. Install Xcode and open it once to finish its setup.
2. Install XcodeGen. If you use Homebrew, run `brew install xcodegen`.
3. Clone the repository:

	```sh
	git clone https://github.com/JMHSV/ghuey-prompt.git
	cd ghuey-prompt
	```

4. Build and install the app:

	```sh
	make install
	```

`make install` builds a Release app, replaces `/Applications/Ghuey Prompt.app`, registers its Services menu item, and launches it. The Release app supports Apple Silicon and Intel Macs. Builds use ad hoc signing by default.

To build without installing, run `make build`. The app appears at `build/Build/Products/Release/Ghuey Prompt.app`.

## Save and insert your first prompt

1. Complete the welcome tour. Allow Ghuey Prompt in **System Settings → Privacy & Security → Accessibility**.
2. Select text in another app and press **⇧⌥⌘P** to save it.
3. Place your cursor where you want to use the prompt.
4. Press **⌥⌘P**, search for the prompt, and press **Return** to insert it.

You can also save selected text through **Services → Save to Ghuey Prompt**, or drag text onto the left screen edge. To write a prompt from scratch, open the shelf and click **+**.

The pointer can open the shelf too: rest it against the left screen edge, or click the glowing edge hint. The shelf hides when you move away. Use the pin button to keep it open.

## Shortcuts and controls

**⌘** means Command, **⌥** means Option, **⇧** means Shift, and **⌃** means Control.

| Action | Shortcut or control |
| --- | --- |
| Open the shelf and search | **⌥⌘P** |
| Save selected text from another app | **⇧⌥⌘P** |
| Select a prompt | **↑ / ↓** |
| Insert a prompt | Click a card or press **Return** |
| Create a prompt | **⌘N** or the **+** button |
| Add or remove a favorite | **⌘D** or the card's context menu |
| Insert one of the first nine favorites | **⌃⌥1–9**, from any app |
| Stack prompts in click order | **Shift-click** cards, then press **Return** |
| Append the clipboard as a code block | **Option-click** a card |
| Preview the full prompt | Hover over a card |
| Rename, edit, copy, or delete | Right-click a card |
| Undo a deletion | **⌘Z** or **Undo** |
| Dismiss the shelf | **Esc** or click outside it |

Favorites appear first, in the order you added them. Other prompts favor those you've used in the current app. Search matches words in both titles and prompt text, ignoring case and accents.

## Use reusable templates

Add placeholders to a prompt:

```text
Review {{file}} for {{concern}}. Explain the cause before suggesting a change.
```

When you insert the prompt, Ghuey Prompt asks for each value and shows a preview. Press **Tab** to move between fields, then **Return** to insert.

Use `{{clipboard}}` to place your current clipboard contents inside a prompt. This placeholder fills automatically. **Option-click** appends the clipboard in a fenced code block when the prompt has no clipboard placeholder.

## Storage and privacy

The default library file is:

```text
~/Library/Application Support/Ghuey Prompt/prompts.json
```

Choose **Show Prompts File** from the menu bar to find it. Back up this file to preserve your library. Changes made in a text editor appear in the app automatically.

Enable **Sync with iCloud Drive** in the menu bar to use `iCloud Drive/Ghuey Prompt/prompts.json`. Ghuey Prompt merges with an existing library at that location and keeps the previous file as a backup. Enable sync on each Mac to share the library.

Ghuey Prompt does not require an account or an API key. Automatic titles use Apple's on-device model when available. Otherwise, titles come from the saved text. Titles you enter yourself are preserved.

Accessibility access enables the global save shortcut and insertion into other apps. Without it, inserting copies the prompt so you can paste it yourself. Automatic insertion temporarily uses the clipboard and restores its previous contents unless you've copied something else meanwhile.

## Settings and troubleshooting

Click the menu bar icon to change **Reveal at Left Screen Edge**, **Edge Sensitivity**, **Launch at Login**, or **Sync with iCloud Drive**. You can reopen the **Welcome Tour…** from this menu.

- **A prompt copies instead of inserting:** enable Ghuey Prompt under **Privacy & Security → Accessibility**. After an ad hoc rebuild, macOS may require you to remove the old entry and grant access again.
- **A shortcut is unavailable:** another app may already use that key combination. Ghuey Prompt reports registration failures. Free the shortcut in that app, then restart Ghuey Prompt.
- **The Services item is missing:** confirm that the app is in `/Applications`. `make install` refreshes macOS Services registration. Check **System Settings → Keyboard → Keyboard Shortcuts → Services** if the item is disabled.
- **iCloud sync is unavailable:** enable iCloud Drive for your macOS account first.
- **The build uses the wrong developer tools:** select your full Xcode installation, for example with `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`.

## Develop

`project.yml` defines the app and test targets. XcodeGen creates `GhueyPrompt.xcodeproj`, which is excluded from Git along with build products.

| Command | Result |
| --- | --- |
| `make project` | Generate the Xcode project |
| `make build` | Build the Release app |
| `make test` | Run the XCTest suite |
| `make install` | Build, install, register Services, and launch |
| `make icon` | Regenerate the app and menu bar icon assets |
| `make clean` | Remove build products |

For repeated local installs, use your own stable signing identity to retain Accessibility permission across builds:

```sh
make install SIGN_IDENTITY="Apple Development: Your Name (TEAMID)"
```

The source is organized by responsibility:

- `GhueyPrompt/App/` connects the app lifecycle, menu bar, settings, and actions.
- `GhueyPrompt/Model/` owns prompt storage, search, merge rules, titles, and templates.
- `GhueyPrompt/System/` handles macOS integration, including hotkeys, screen edges, clipboard transfer, and file changes.
- `GhueyPrompt/UI/` contains the shelf, editor, preview, and template form.
- `GhueyPromptTests/` tests library persistence, search, templates, merging, migration, and shelf behavior.

To regenerate the repository's header and social preview from the app icon, run `swift scripts/make-repo-art.swift`.

## Contribute

Use [GitHub Issues](https://github.com/JMHSV/ghuey-prompt/issues/new/choose) to report a bug or suggest a feature. For a bug, include your macOS version, the app you were using, and steps that reproduce the problem.

For code changes, describe the problem and the resulting behavior in your pull request. Run `make test` and check the behavior in the real app before submitting. Keep changes focused on saving, finding, and using prompts.

## License

[MIT](LICENSE).
