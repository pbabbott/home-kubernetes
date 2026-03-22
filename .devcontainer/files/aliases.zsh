
# Common
alias chimaera="ssh root@192.168.4.192" # Proxmox Host
alias template="ssh firebolt@192.168.6.91"
alias tfhaproxy="ssh root@192.168.6.28"
alias bpi="ssh pi@192.168.4.144"
alias ror="ssh pabbott@192.168.4.124"

# Prod gen 2
alias tfpc1="ssh firebolt@192.168.6.24"
alias tfpw1="ssh firebolt@192.168.6.25"
alias tfpw2="ssh firebolt@192.168.6.26"
alias tfpw3="ssh firebolt@192.168.6.27"

# Non-prod gen 2
alias tfnpc1="ssh firebolt@192.168.6.31"
alias tfnpw1="ssh firebolt@192.168.6.32"
alias tfnpw2="ssh firebolt@192.168.6.33"
alias tfnpw3="ssh firebolt@192.168.6.34"

# Prod gen 1
alias controller="ssh firebolt@192.168.4.193"
alias worker1="ssh firebolt@192.168.4.194"
alias worker2="ssh firebolt@192.168.4.195"
alias worker3="ssh firebolt@192.168.5.81"
alias dumbledore="ssh albus@192.168.4.157"

# Kubernetes
alias k="kubectl"

# Flux
alias fgit="flux reconcile source git flux-system"
alias fks="flux reconcile ks"
alias fksfs="flux reconcile ks flux-system"
alias fksic="flux reconcile ks infra-config"
alias fksictr="flux reconcile ks infra-controllers"
alias fksm="flux reconcile ks monitoring"
alias fall="fgit; fksfs; fksictr; fksic; fksm; fks apps;"
