# Contribuer à ScratchApp

## Processus (BMAD)

1. Chaque tâche est une **story** (`docs/stories/E.S.slug.md`) liée à une **issue GitHub** du kanban.
2. Une branche par story : `story/<E>.<S>-<slug>` depuis `main` à jour.
3. Une PR par story, avec le modèle `.github/pull_request_template.md` et `Closes #<issue>`.
4. La PR est fusionnée (squash) uniquement si : rapport CI ✅ sur Linux et macOS, revue QA approuvée,
   pas de conflit avec `main`.
5. Après fusion, l'issue se ferme et passe en « Done » sur le kanban.

## Conventions

- Code, identifiants et commentaires techniques en **anglais** ; documentation et libellés d'interface en **français**.
- Swift 5.10 (mode de langage 5), SwiftUI, Observation (`@Observable`), iOS 17 / macOS 14 minimum.
- `ScratchCore` et `ScratchLibrary` restent **compilables sous Linux** : pas d'`AVFoundation`, `SwiftUI`,
  `CryptoKit` ni `UIKit/AppKit` dans ces modules.
- Fil de rendu audio : **aucune allocation, aucun verrou bloquant, aucun appel Objective-C/Swift
  susceptible d'allouer** (pas de `print`, pas de tableaux dynamiques, pas de closures capturées à la volée).
  Communication UI → audio par file SPSC sans verrou ; audio → UI par instantané atomique.
- Chaque exigence testable de la story a un test XCTest qui cite son identifiant (SF-xx / RM-xx).
- Messages de commit : `type(scope): résumé` (`feat`, `fix`, `test`, `docs`, `chore`, `refactor`).
