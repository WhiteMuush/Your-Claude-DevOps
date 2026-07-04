# Config Claude Code

Config perso de Claude Code : règles, skills, hooks, mémoire. Sert à réinstaller le même setup sur une autre machine.

## Contenu

- `CLAUDE.md` : règles globales (profil étudiant, pédago adaptatif, dyslexie, format, git, token)
- `skills/` : 23 skills (9 DevOps + 14 dev/superpowers)
- `hooks/` : scripts du mode caveman (activate, mode-tracker, statusline, stats)
- `settings.json` : config Claude Code (modèle, hooks, thème, marketplace caveman)
- `memory/` : mémoire persistante (index + fichiers)

## Ce qui n'est PAS ici (volontaire)

Secrets et données privées exclus : `.credentials.json`, historique, transcripts de sessions, caches. Ne jamais les commit.

## Installation sur une nouvelle machine

1. Cloner ce repo quelque part, puis copier les fichiers dans `~/.claude/` :

   ```bash
   cp CLAUDE.md ~/.claude/
   cp settings.json ~/.claude/
   cp -r skills/* ~/.claude/skills/       # créer ~/.claude/skills d'abord si absent
   cp -r hooks/* ~/.claude/hooks/
   mkdir -p ~/.claude/projects/-home-USER/memory && cp memory/* ~/.claude/projects/-home-USER/memory/
   ```

2. **IMPORTANT, chemins en dur.** `settings.json` référence `/home/white/.claude/hooks/...`.
   Si le user de la nouvelle machine n'est pas `white`, remplacer partout `/home/white` par le vrai home :

   ```bash
   sed -i "s#/home/white#$HOME#g" ~/.claude/settings.json
   ```

   Idem pour le chemin `memory/` (dossier `-home-USER` dérivé du home).

3. Le plugin **caveman** se réinstalle seul : `settings.json` déclare le marketplace `JuliusBrussee/caveman` et l'active. Au prochain lancement de Claude Code, il est récupéré automatiquement. Sinon, manuel :

   ```
   /plugin marketplace add JuliusBrussee/caveman
   /plugin install caveman
   ```

4. Relancer Claude Code. Le mode caveman s'active via le hook SessionStart.

## Notes

- Skills DevOps source : `khalilbenaz/claude-skills-collection` (dossier `devops-skills`)
- Skills dev source : `obra/superpowers` (dossier `skills`), hooks superpowers non inclus
- Les "—" ont été retirés de tous les skills (préférence perso)
