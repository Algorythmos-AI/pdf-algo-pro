# VoiceOver script

The manual accessibility pass run on a device before every TestFlight build that reaches testers
beyond the owner, and before every release. The automated audits check each screen on the
simulator, at the default and an accessibility text size ([testing strategy](../testing-strategy.md),
"Accessibility tests"). They cannot tell whether a journey makes sense when heard rather than seen,
so this script checks that. It is the "Manual VoiceOver and Dynamic Type pass" in the release
checklist ([release management](../release-management.md)) and bar item B7 on the TestFlight tracking
issue ([#47](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/47)).

Owner: Quality and Design · Reviewed: each milestone, and whenever a screen or journey is added

## Before you start

- Use an iPhone on the build under test, installed from TestFlight.
- Delete the app and install it again, so onboarding appears.
- Turn on VoiceOver: Settings → Accessibility → VoiceOver, or triple-click the side button if the
  Accessibility Shortcut is set.
- Gestures used below:
  - swipe right or left to move to the next or previous item;
  - double-tap to activate;
  - two-finger scrub (a Z shape) to go back or close a sheet;
  - rotate two fingers to open the rotor.
- About 20 minutes. Note the build number, the device and the iOS version in the sign-off table.

## What passes

On every screen, each check holds:

1. Every control is announced with a name and a role ("Import a PDF, button"). None is only
   "button", an image name, or a symbol name such as "doc.viewfinder".
2. Swiping moves in reading order: top to bottom, leading to trailing, with the navigation bar first.
3. Decorative images are skipped.
4. When a sheet opens, focus moves into it and stays there. When it closes, focus returns to the
   screen that opened it.
5. Changes you cause are announced or reachable at once (a new answer, an added note, an error).

Record anything that fails as an issue with the `accessibility` label, with the step number.

## The script

### 1. Onboarding

1. The first screen is announced with its heading, "What do you do with PDFs most often?".
2. Swipe through the choices: the four AI choices come first ("Chat with PDF", "Summarise
   document", "Extract data with AI", "Analyse contract"), then the other tasks. Each says whether
   it is selected, and choices not in this version say they are coming later.
3. Select two choices, then activate "Continue". Home opens and the choice you made first is the
   first of its actions.

### 2. Home and the library

1. Home reads "PDF Algo Pro", then "Your library, No documents yet" as one heading, then the
   actions (Import, Scan), the line about what can be done, and "Try a sample". The app's mark is
   not read: the name beside it says the same.
2. Each section reads its name and how many documents it holds, for example "All documents,
   0 documents". The footer reads "Your documents stay on this device." and "Built by
   Algorythmos"; the company's mark beside those words is not read as well.
3. Activate "All documents". The empty state reads its heading, "No documents yet", and the three
   actions. Activate "Try a sample". The sample opens in the reader.
4. Go back to the library. The sample's row reads its title, and the rotor's Actions item offers
   the row's swipe actions, Favourite among them. Favourite it, and check that the row now says so.
5. Go back to Home. "Continue reading" is a heading and the sample is under it; the counts now read
   "All documents, 1 document" and "Favourites, 1 document".
6. Open Settings from the toolbar, then close it with a two-finger scrub.

### 3. Reader

1. Open the sample. The page indicator reads "Page 1 of 3".
2. Swipe into the page: VoiceOver reads the page's text line by line.
3. More → "Go to page": type 3 and activate "Go". The indicator reads "Page 3 of 3".
4. More → "Contents": the entries are read in order. Activate one and check that the page changes.
5. More → "Pages": each thumbnail reads "Page 1", "Page 2", "Page 3". Activate "Page 2".
6. More → "Find": the system find bar opens. Search for "invoice" and move between matches.
7. More → "Read aloud": the current page is read aloud. Then More → "Stop reading".

### 4. Markup and signing

1. Markup → "Add note": the alert's text field is focused. Type a note and activate "Add".
   Markup → "Undo" is now available.
2. Markup → "Text box": type text and activate "Add".
3. Markup → "Draw": the page is covered by "Drawing area", and "Done" appears in the toolbar.
   Activate "Done" to leave drawing. Drawing itself is a pointer task; record whether leaving it is
   clear.
4. Markup → "Signature": the sheet opens with focus inside it. "Clear" and "Save and place" are
   read as dimmed until something is drawn. Type your name in "Your name" and activate "Place
   typed signature". The sheet closes and Markup → "Undo" is available.
5. Selecting an annotation is a tap on the page. Record whether VoiceOver reaches the text box
   added in step 2. If it doesn't, turn VoiceOver off, tap the text box, and turn VoiceOver on again.
   The selection bar reads what it is ("Text box"), then "Edit text", "Delete" and "Done". Activate
   "Delete".

### 5. Scan

1. In the library, activate "Scan". The screen explains that text is recognised on this device.
2. "Scan with camera" opens the system camera. Its own VoiceOver guidance should describe the
   document edges. Cancel.
3. "Choose images" opens the photo picker. Cancel. "Cancel" in the toolbar closes the screen.

### 6. Assistant

1. In the reader, activate "Ask", then "Ask a question". Focus lands in the sheet.
2. Type "What is the total due?" and send it. The answer is reachable at once, with its tier badge
   and its sources.
3. The citation reads "Source: page 2", with the hint "Opens the page and highlights the passage".
   Activate it: the sheet closes and the reader shows page 2.
4. Ask "Who won the match?". The answer is "Not found in this document", with its explanation.

### 7. Settings

1. The first stop reads "PDF Algo Pro, Version …" as one item. Each toggle reads its title and
   state: "Hide AI features", and "Document text in Spotlight" under Privacy and security. The
   tiles before the titles are not read.
2. Turn on "Hide AI features", close Settings and open the sample: the reader has no Ask button.
   Turn the setting back off.
3. Under Storage, "Version history" and its size read as one item, for example "Version history,
   2.8 MB".
4. "Report a problem" opens Mail, or, with no mail account, offers "Copy the report".
5. Open "About". It reads the app's name and version as a heading, then "Privacy Policy", "Terms of
   Use" and "Support" as links, "Share PDF Algo Pro", and "Built by Algorythmos,
   algorythmos.com" as one link.

### 8. Largest text size

1. Settings → Accessibility → Display & Text Size → Larger Text: turn on Larger Accessibility Sizes
   and choose the largest size.
2. Repeat steps 1.1, 2.1, 3.1, 4.4, 6.2 and 7.1 without VoiceOver. Nothing is clipped or overlaps,
   and everything can be reached by scrolling. A title shortened in the navigation bar is expected.
3. Restore the text size.

## Sign-off

| Build | Device and iOS | Date | Run by | Result and issues |
|---|---|---|---|---|
| | | | | |
