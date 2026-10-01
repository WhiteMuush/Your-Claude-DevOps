# Installation guidée par Claude

Sur la nouvelle machine :

1. Cloner ce repo et ouvrir un terminal dedans :

   ```bash
   git clone https://github.com/WhiteMuush/Your-Claude-DevOps.git
   cd Your-Claude-DevOps
   ```

2. Lancer Claude Code dans ce dossier.

3. Coller ce prompt :

---

> Tu es dans mon repo de config Claude Code (`Your-Claude-DevOps`). Installe cette config sur la machine actuelle.
>
> Étapes :
> 1. Lis le `README.md` et le script `install.sh` pour comprendre ce qui doit être copié dans `~/.claude/`.
> 2. Le script écrit dans `~/.claude/`, donc le gate de sécurité t'empêchera de le lancer toi-même. Ne force pas : donne-moi la commande exacte à exécuter moi-même, préfixée par `!`, soit `! bash install.sh`.
> 3. Une fois que je l'ai lancée, vérifie que l'install est bonne : `~/.claude/CLAUDE.md` présent, `~/.claude/skills` contient 30 dossiers, et la mémoire est dans `~/.claude/projects/<clé>/memory`.
> 4. Dis-moi si le plugin `i-have-adhd` est actif. S'il ne l'est pas, rappelle-moi les commandes `/plugin marketplace add ayghri/i-have-adhd` puis `/plugin install i-have-adhd`.
> 5. Demande-moi si je veux le workspace herdr (`claude` ouvre Claude à gauche et un shell à droite). Si oui, la commande devient `! bash install.sh --herdr`, et vérifie ensuite que `~/.claude/shell/claude-herdr.zsh` existe et que `~/.zshrc` le source une seule fois.
> 6. Confirme quand tout est en place et dis-moi de relancer Claude Code pour charger le plugin.

---

## Alternative sans Claude

Tu peux tout faire toi-même, sans prompt :

```bash
bash install.sh          # config seule
bash install.sh --herdr  # config + workspace herdr
```

Puis relancer Claude Code.
