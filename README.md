# VOD Recovery TV

Version Apple TV (SwiftUI natif, Liquid Glass) de VodRecovery, simplifiée :

1. **Explorer une chaîne** : nom de la chaîne, favoris épinglés et historique.
2. **Choisir un stream** dans la grille des streams récents (Twitch + vodvod.top).
3. La VOD est **retrouvée automatiquement** (URL CDN reconstruite), le son coupé est
   **restauré** et les **segments sont vérifiés** ; les manquants sont retirés.
4. **Lire** dans le lecteur intégré (reprise automatique), ou ouvrir dans **VLC** / **Infuse**.

Le projet Xcode est généré par XcodeGen (`project.yml`) ; la CI GitHub Actions
produit une IPA non signée, installée sur l'Apple TV avec atvloadly.

Icônes : `python3 scripts/make_icons.py .`
