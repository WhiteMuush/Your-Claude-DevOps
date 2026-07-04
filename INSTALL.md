# Installation guidée par Claude

Sur la nouvelle machine :

1. Cloner ce repo et ouvrir un terminal dedans :

   ```bash
   git clone https://github.com/WhiteMuush/Your-Claude-Teacher.git
   cd Your-Claude-Teacher
   ```

2. Lancer Claude Code dans ce dossier.

3. Coller ce prompt :

---

> Tu es dans mon repo de config Claude Code (`Your-Claude-Teacher`). Installe cette config sur la machine actuelle.
>
> Étapes :
> 1. Lis le `README.md` et le script `install.sh` pour comprendre ce qui doit être copié dans `~/.claude/`.
> 2. Le script écrit dans `~/.claude/`, donc le gate de sécurité t'empêchera de le lancer toi-même. Ne force pas : donne-moi la commande exacte à exécuter moi-même, préfixée par `!`, soit `! bash install.sh`.
> 3. Une fois que je l'ai lancée, vérifie que l'install est bonne : `~/.claude/CLAUDE.md` présent, `~/.claude/skills` contient 23 dossiers, `~/.claude/hooks` contient les scripts caveman, et la mémoire est dans `~/.claude/projects/<clé>/memory`.
> 4. Dis-moi si le plugin caveman est actif. S'il ne l'est pas, rappelle-moi les commandes `/plugin marketplace add JuliusBrussee/caveman` puis `/plugin install caveman`.
> 5. Confirme quand tout est en place et dis-moi de relancer Claude Code pour activer le mode caveman.

---

## Alternative sans Claude

Tu peux tout faire toi-même, sans prompt :

```bash
bash install.sh
```

Puis relancer Claude Code.
