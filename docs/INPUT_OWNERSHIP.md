# Input ownership

`GameInputPolicy` describes presentation routing from an immutable `GameInputState` snapshot. The shell gathers focus/modal facts and performs effects. Policy decisions are not commands: current source actions, revisions, reader availability and the original keyboard conversion remain authoritative.

## Physical keyboard priority

The order below preserves the shell's existing behaviour. A higher row wins when states overlap.

| Priority | Condition | Owner / result |
|---|---|---|
| 1 | KeyDown Tab | The shell records deliberate traversal before evaluating ownership. |
| 2 | Another Navigator route is current | The overlay owns input, including Escape and F1, even if background game focus returns. |
| 3 | Graphical inspection, without source text entry | KeyDown Escape closes inspection; other keys stay outside the source reader. Classic retains its existing path. |
| 4 | Source text entry and KeyDown Escape | The visible editor's existing submit/replay guard receives it, including while submission is busy. Escape never becomes a raw source key here. |
| 5 | KeyDown F1, with help/submission/navigation/controller work idle | Open help, including from a focused editor or with modifiers. A held F1 does not repeatedly open help. |
| 6 | Entry/search editor focused, help/submission/navigation/controller busy, or key release | Keep input with that owner; do not route to game shortcuts. |
| 7 | Graphical journal and Alt alone (without Ctrl/Meta/Shift) | Describe the registered chapter/global shortcut. The live journal still checks availability, required reports and drafts before acting. |
| 8 | Enter/Space after deliberate Tab traversal, with focus on another control | Let that control activate. Pointer-retained focus preserves original source-key timing. |
| 9 | Modifier key itself, or Ctrl/Meta/Alt still pressed | Leave input to the platform. Shift with a game character proceeds to the original case-sensitive conversion. |
| 10 | Remaining KeyDown/KeyRepeat | Clear traversal intent, convert the key, then offer it to local ledger/journal handlers. Recheck source text entry before forwarding to the original reader. |

Physical source keys can clear pointer drafts through `prepareForSourceInput`; they retain the original immediate task choices and Back hierarchy. Unfocused source text entry still gets the local-handler opportunity, but the shell's final live text check prevents forwarding edits into its hidden reader. The changelog retains its existing physical widget/reader path. A rendered-action revision does not gate raw physical keys.

## Development bridge

The bridge evaluates these stable blocked-reason codes in order:

1. `shell_unavailable`
2. `changelog_open`
3. `modal_open` (help or another Navigator route)
4. `inspection_open` (including Classic and source text entry)
5. `ui_busy` (submission, navigation, opening a journal chapter or controller work)
6. `unconfirmed_draft`
7. `text_editor_focused` (a presentation editor outside source text entry)

The editor replay's `allowSending` allowance relaxes only its own submission flag. The other blockers still apply. Source text replay, action capabilities, pending input and observed revisions retain their existing bridge/console checks.

## Rendered controls

The global rendered-action guard checks help, navigation, controller work and the rendered console revision. Each control/route retains its own source-action, draft, report and availability checks; overlays retain pointer/focus isolation. This boundary permits legitimate controls such as cancellation and text submission without imposing the bridge's restrictions on them.

## Verification

`game_input_policy_test.dart` pins overlapping priorities and channel differences. `text_prompt_focus_test.dart` runs real text readers with an overlay after background focus restoration, F1 from an editor, Escape and in-flight submission. Keyboard, Classic parity, journal and enabled development-bridge regressions establish actual source dispatch and campaign/input/RNG preservation. Run the shared acceptance journey and affected browser checks described in [Testing](TESTING.md) for integrated verification.
