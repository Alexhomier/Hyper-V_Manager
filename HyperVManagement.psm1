# Crée une nouvelle machine virtuelle avec les spécifications données (nom, taille de RAM, taille de disque).
function New-VMCreation {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [string]$VMnom,  # Nom de la machine virtuelle à créer.

        [Parameter(Mandatory=$true)]
        [int]$VMTailleRAM,  # Taille de la RAM en MB.

        [Parameter(Mandatory=$true)]
        [int]$VMTailleDisque  # Taille du disque en GB.
    )
    Process {
        Write-Host "Création VM: $VMNom"  # Affiche le nom de la VM en cours de création.
        $path = "C:\Hyper_V\$VMNom\"  # Définit le chemin du dossier de la VM.
        New-VM -Name $VMNom -MemoryStartupBytes ($VMTailleRam * 1MB) -Path "$path\$VMNom"  # Crée la VM avec la RAM spécifiée.
        New-VHD -Path "$path\$VMNom.vhdx" -SizeBytes ($VMTailleDisque * 1GB) -Dynamic  # Crée un disque dur virtuel dynamique.
        Add-VMHardDiskDrive -VMName $VMNom -Path "$path\$VMNom.vhdx"  # Attache le disque dur à la VM.
    }
}

# Supprime une machine virtuelle spécifiée par son nom.
function VMSuppression {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [string]$VMnom  # Nom de la VM à supprimer.
    )
    Process {
        Write-Host "Suppression de la VM: $VMNom"  # Annonce la suppression de la VM.
        Stop-VM -Name $VMNom -Force  # Arrête la VM de force.
        Remove-VM -Name $VMNom -Force  # Supprime la VM de force.
        $path = "C:\Hyper_V\$VMNom\"  # Chemin du dossier de la VM.
        Remove-Item -Path $path -Recurse -Force  # Supprime le dossier et tous les fichiers associés.
        Write-Host "VM $VMNom supprimé"  # Confirme la suppression de la VM.
    }
}

# Clone une VM existante vers une nouvelle VM avec un nouveau nom.
function VMClone {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [string]$VMSourceNom,  # Nom de la VM source à cloner.

        [Parameter(Mandatory=$true)]
        [string]$VMCloneNom  # Nom de la nouvelle VM clonée.
    )
    Process {
        try {
            $vmSourceDetails = Get-VM -Name $VMSourceNom  # Récupère les détails de la VM source.
            if ($null -eq $vmSourceDetails) {
                throw "VM source '$VMSourceNom' introuvable."  # Lance une exception si la VM source n'est pas trouvée.
            }

            if ($vmSourceDetails.State -ne 'Running' -and $vmSourceDetails.State -ne 'Saved') {
                throw "La VM source doit être en état Running ou Saved pour cloner."  # Lance une exception si l'état de la VM source n'est pas adéquat pour le clonage.
            }

            $nouveauChemin = "C:\Hyper_V\$VMCloneNom\"  # Chemin pour la nouvelle VM.
            New-Item -Path $nouveauChemin -ItemType Directory -Force  # Crée le dossier pour la nouvelle VM.

            $memoryBytes = $vmSourceDetails.MemoryStartupBytes  # Récupère la quantité de RAM de la VM source.
            if ($null -eq $memoryBytes -or $memoryBytes -le 0) {
                $memoryBytes = 2GB  # Assigne une valeur par défaut si la RAM n'est pas récupérable.
                Write-Host "Impossible de récupérer la quantité de mémoire de la VM source. Utilisation de la valeur par défaut de 2048 MB."
            }
            
            New-VM -Name $VMCloneNom -MemoryStartupBytes $memoryBytes -Path $nouveauChemin  # Crée la nouvelle VM.

            $disques = $vmSourceDetails | Get-VMHardDiskDrive | Get-VHD  # Récupère les disques durs de la VM source.
            foreach ($disque in $disques) {
                $disquePath = $disque.Path  # Chemin du disque dur source.
                while ($disque.ParentPath) {  # Vérifie si le disque est un disque de différenciation.
                    $disquePath = $disque.ParentPath  # Remonte au disque parent.
                    $disque = Get-VHD -Path $disque.ParentPath
                }
                
                $nomDisqueClone = $VMCloneNom + "_" + [System.IO.Path]::GetFileNameWithoutExtension($disquePath) + ".vhdx"  # Nom du nouveau disque cloné.
                $nouveauDisquePath = "$nouveauChemin\$nomDisqueClone"  # Chemin du nouveau disque cloné.
                if (Test-Path $nouveauDisquePath) {
                    Remove-Item $nouveauDisquePath -Force  # Supprime le disque cloné s'il existe déjà.
                }
                Copy-Item -Path $disquePath -Destination $nouveauDisquePath  # Copie le disque source vers le chemin du disque cloné.
                New-VHD -Path $nouveauDisquePath -ParentPath $disquePath -Differencing  # Crée un disque de différenciation.
                Add-VMHardDiskDrive -VMName $VMCloneNom -Path $nouveauDisquePath  # Attache le disque à la nouvelle VM.
            }

            Write-Host "VM '$VMCloneNom' clonée avec succès à partir de '$VMSourceNom'."  # Confirme le succès du clonage.
        } catch {
            Write-Error "Erreur lors du clonage de la VM: $_"  # Gère les erreurs lors du clonage.
        }
    }
}

# Récupère et affiche des informations sur les ressources (disque ou mémoire) d'une VM spécifique.
function Get-VMRessource {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [string]$NomVM,  # Nom de la VM pour laquelle récupérer les informations.

        [Parameter(Mandatory=$true)]
        [ValidateSet("Disque", "Memoire")]  # Type de ressource à récupérer, 'Disque' ou 'Memoire'.
        [string]$TypeRessource
    )

    # Récupérer la VM
    $vm = Get-VM -Name $NomVM
    if ($vm -eq $null) {
        Write-Error "Aucune VM trouvée avec le nom $NomVM"  # Gère l'erreur si la VM n'est pas trouvée.
        return
    }

    switch ($TypeRessource) {
        "Disque" {
            # Récupérer les disques durs virtuels associés à la VM.
            $disques = $vm | Get-VMHardDiskDrive | Get-VHD

            # Afficher les informations sur chaque disque.
            foreach ($disque in $disques) {
                $tailleTotaleGB = [math]::Round($disque.Size / 1GB, 2)  # Convertit la taille totale en GB.
                $tailleUtiliseeGB = [math]::Round($disque.FileSize / 1GB, 2)  # Convertit la taille utilisée en GB.
                $pourcentageUtilise = [math]::Round(($disque.FileSize / $disque.Size) * 100, 2)  # Calcule le pourcentage utilisé.
                Write-Host "Disque: $($disque.Path)"
                Write-Host "Taille Totale: $tailleTotaleGB GB"
                Write-Host "Taille Utilisée: $tailleUtiliseeGB GB"
                Write-Host "Pourcentage Utilisé: $pourcentageUtilise %"
            }
        }
        "Memoire" {
            # Vérifier si la VM est éteinte avant de récupérer les informations de mémoire.
            if ($vm.State -eq 'Off') {
                Write-Error "Les données de mémoire ne peuvent pas être récupérées car la VM '$NomVM' est éteinte."  # Gère l'erreur si la VM est éteinte.
            } else {
                $tailleAlloueeGB = [math]::Round($vm.MemoryAssigned / 1MB, 2)  # Convertit la mémoire allouée en MB.
                $tailleDemandeeGB = [math]::Round($vm.MemoryDemand / 1MB, 2)  # Convertit la mémoire demandée en MB.
                Write-Host "Mémoire Allouée à la VM '$NomVM': $tailleAlloueeGB MB - Mémoire Demandée: $tailleDemandeeGB MB"
            }
        }
    }
}

# Supprime toutes les VMs inactives (état 'Off').
function VMMassSuppressionInactives {
    [CmdletBinding()]
    Param(
    )

    try {
        $VMsInactives = Get-VM | Where-Object { $_.State -eq 'Off' }  # Récupère toutes les VMs inactives.

    } catch {
        if ($_ -match "l’objet est introuvable") {
            Write-Warning "Il semble y avoir un problème avec l'accès à Hyper-V ou l'objet VM demandé n'existe pas. Veuillez vérifier que le service Hyper-V est actif et que vous disposez des autorisations nécessaires."
        } else {
            Write-Warning "Erreur lors de la récupération des VMs: $_"
        }
    }
        $VMsInactives | Select-Object Name, State  # Affiche les VMs inactives.

        if ($VMsInactives.Count -gt 0) {
            foreach ($vm in $VMsInactives) {
                try {
                    Remove-VM -VM $vm -Force  # Tente de supprimer chaque VM inactive.
                    Write-Host "VM $($vm.Name) supprimé."
                } catch {
                    Write-Warning "Impossible de supprimer la VM $($vm.Name): $_"  # Gère les erreurs lors de la suppression.
                }
            }
        } else {
            Write-Host "Il n'y a aucune VM inactive."  # Indique si aucune VM inactive n'est trouvée.
        }
}
