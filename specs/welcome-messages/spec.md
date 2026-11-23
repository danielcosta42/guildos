# Several welcome messages, one drawn each time (issue #419)

## Why
Asked on Discord (suggestions, "Multiple welcome messages"): the welcome an officer writes for whoever
joins the guild went out word for word for every newcomer, and read as a bot. The officer wants to
write a few and have one drawn each time.

## What
- The welcome in guild chat when someone joins (Recruitment > Recruiting > Welcome Message) holds up
  to 10 messages (`Recruitment.WELCOME_MAX`). Each row has its Save and Remove; "Add message" opens
  an empty row under the last. The last message left cannot be removed.
- Each welcome draws one (`Recruitment.PickWelcome`), never the one sent last (`recruitment.welcomeLast`)
  while there is another. The draw stays until it is sent, so the Forever popup shows the line its
  click posts; a send the game refuses keeps it; a draw taken off the list is drawn again.
- The texts are checked as before (`ChatTextProblem`, #270), and the rules' invitation (#407) ends
  whichever is drawn. There are no placeholders today: every text goes as written.
- Storage: `recruitment.welcomeMessages` is the list; its first is also `recruitment.welcomeMessage`,
  the setting before #419, which wins for the first place. Initialize writes the list from it (the
  welcome the officer had becomes the first, nothing lost); a client from before #419, or
  `/gos recruit welcome msg`, keeps reading and writing that first one. The welcome is not synced
  between officers: each sends from their own settings, as before.
- `/gos recruit status` says how many more there are.

## Acceptance
- [x] The officer keeps several welcomes; the one they had is the first.
- [x] Each welcome draws one, never the previous one when there is more than one.
- [x] The same checks and the rules' invitation apply to every one.
- [x] Locales in the 10 languages; `tools/welcome-many.lua`, `tools/recruiting-layout.lua`.
