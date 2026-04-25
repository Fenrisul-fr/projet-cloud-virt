# Pour lancer l'application sur le cluster de vm

# init
Je pars du principe que la config initiale est la même que celle obtenue lors du début de mon projet
A savoir docker/git d'installés et le sous réseau déjà configuré entre les VMs 


# 1 
Pour commencer il faut soit git clone ce dépot sur les VMs soit juste copier le contenu du fichier "setup.sh" 

PENSEZ A MODIFIER L'ADRESSE IP DE LA VM LEADER SI ELLE EST DIFFERENTE ! 

# 2
Le lancer sur la vm leader avec la commande:
. /opt/infra/setup.sh leader

rq: si jamais vault ne se configure pas bien, se réferer au "readme.md" dans le dossier vault et suivre les étapes une à une.

# 3
suivre les instructions à l'écran et lancer en mode worker sur les autres VMs

. /opt/infra/setup.sh worker

# 4 
Maintenant, vous pouvez lancez l'application avec
. /opt/infra/deploy.sh


# Pour utiliser l'application

aller sur :
https://web.pailhe.maurice-cloud.fr/





# Points importants
Pour relancer l'application après un crash ou reboot, vault se reverrouille
il faut "vault operator unseal" sur la vm qui a crash pour la reconnecter au raft et qu'elle puisse lancer les applications

Je n'ai pas eu le temps de mettre en place de logs via open telemetry ou de sauvegarde de snapshots sur vault





# Rq
Vault a été compliqué à configurer (d'où l'utilisation des CA car problèmes d'authentifications entre VMs) 
J'ai une version fonctionnelle sans sécurisation des tokens ou on peut enlever la partie "identity" et "vault" dans les jobs nomads et remplacer par une partie "env" où on écrit les crédentials à la main. Il faut aussi supprimer la partie vault dans les configs nomad.hcl.
(Normalement c'est sensé fonctionner avec vault donc je laisse la version finale uniquement)





