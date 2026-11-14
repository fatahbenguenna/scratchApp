# Équipe BMAD de ScratchApp

Le développement suit la méthode **BMAD** (*Breakthrough Method for Agile AI-Driven Development*) :
des agents spécialisés produisent, dans l'ordre, les artefacts de planification, puis des stories
autoportantes exécutées par les développeurs et vérifiées par la QA. L'orchestrateur (BMad Master)
coordonne les phases, attribue les stories et fusionne les PR une fois toutes les conditions remplies.

## Les 10 agents

| # | Rôle BMAD | Agent | Responsabilités | Livrables |
|---|---|---|---|---|
| 1 | 📊 Analyst | **Mary** | Analyse de la spec v2.0, brief produit, matrice de traçabilité SF/RM → épopées | `docs/bmad/project-brief.md`, `docs/bmad/traceability.md` |
| 2 | 📋 Product Manager | **John** | PRD : objectifs, exigences fonctionnelles et non fonctionnelles, épopées et stories, ordre de livraison | `docs/bmad/prd.md` |
| 3 | 🎨 UX Expert | **Sally** | Spécification UX : dispositions iPhone/iPad/Mac, composants, gestes, clavier, accessibilité | `docs/bmad/front-end-spec.md` |
| 4 | 🏗️ Architect | **Winston** | Architecture technique (temps réel audio, modules, flux de données, tests) et **contrats de code** (protocoles, types partagés) | `docs/bmad/architecture.md` + PR d'interfaces |
| 5 | 📝 Product Owner | **Sarah** | Validation croisée des artefacts (checklist PO), arbitrages, découpage en épopées prêtes pour le développement | `docs/bmad/po-validation.md` |
| 6 | 🏃 Scrum Master | **Bob** | Stories détaillées et autoportantes, dépendances, vagues, issues GitHub (kanban) | `docs/stories/*.md`, issues, labels, milestones |
| 7 | 💻 Dev Audio & DSP | **James** | `ScratchCore` (physique, rendu, mixage) et `ScratchAudio` (AVAudioEngine, décodage, session, self-test) | Code + tests, PR par story |
| 8 | 💻 Dev UI | **Léa** | `ScratchUI` : disque et gestes, commandes, table de mixage, forme d'onde, dispositions, clavier Mac, accessibilité | Code + tests, PR par story |
| 9 | 💻 Dev Plateforme | **Hugo** | `ScratchLibrary` (import, copie, SHA-256, dédoublonnage, préférences), intégration de l'app, cycle de vie, CI | Code + tests, PR par story |
| 10 | 🧪 QA / Test Architect | **Quinn** | Revue de chaque PR au regard des critères d'acceptation, tests manquants, décision de gate (PASS / CONCERNS / FAIL), recette | Commentaires de revue, `docs/qa/gates/*.yml` |

## Déroulement

```
Spec v2.0 ─▶ Mary (brief, traçabilité)
          ─▶ John (PRD) ─┐
          ─▶ Sally (UX) ─┼─▶ Sarah (validation PO) ─▶ Bob (stories + kanban)
          ─▶ Winston (architecture + contrats de code) ┘
                                                        │
              ┌─────────────────────────────────────────┘
              ▼
   Vagues de stories :  James ∥ Léa ∥ Hugo  ─▶  PR  ─▶  CI Linux + macOS  ─▶  Quinn (gate)
                                                                         ─▶  fusion sur main
```

## Définition de « terminé » (DoD) d'une story

1. Code conforme à l'architecture et aux conventions (`CONTRIBUTING.md`).
2. Tous les critères d'acceptation de la story sont satisfaits ; chacun a un test lorsqu'il est testable automatiquement.
3. Rapport CI ✅ : Linux et macOS (tests, build macOS, build iOS, self-test, lancement).
4. Gate QA **PASS**, ou **CONCERNS** accepté par le PO avec une issue de suivi.
5. PR fusionnée sur `main` (squash) et issue fermée.

## Règles de travail en parallèle

- Chaque développeur travaille dans son propre clone ou worktree, sur une branche `story/…`.
- Avant d'ouvrir ou de mettre à jour une PR : rebaser sur `origin/main`.
- Les contrats publics (protocoles et types partagés de l'architecture) ne changent que par une story dédiée ou avec l'accord de l'architecte.
- Les fichiers d'un module appartiennent à l'agent du module. Une modification transverse se signale dans la PR.
