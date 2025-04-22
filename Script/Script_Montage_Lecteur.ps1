<#
.SYNOPSIS
    Script de montage des lecteurs reseau pour les utilisateurs
.DESCRIPTION
    Monte les lecteurs reseau selon la structure definie :
    U: Dossier personnel des utilisateurs
    M: Dossier Medical
    S: Administratif/Animation
    P: Compta
    Z: Bibles
    T: Technique
    X: Cadres
.NOTES
    Version: 1.0
    Auteur: VotreNom
    Date: $(Get-Date -Format 'dd/MM/yyyy')
#>

# Import du module necessaire pour les partages reseau
Import-Module SmbShare

# Configuration de base
$Domain = "pourlesvieux.fr"
$BasePath = "\\serveurvieux\pourlesvieux.fr"  # Remplacez par votre serveur reel
$LogPath = "C:\Logs\MountDrives_$(Get-Date -Format 'yyyyMMdd').log"

# Fonction pour logger les actions
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    Add-Content -Path $LogPath -Value $LogMessage
}

# Fonction pour monter un lecteur reseau
function Mount-NetworkDrive {
    param (
        [string]$DriveLetter,
        [string]$NetworkPath,
        [bool]$Persistent = $true,
        [string]$Description = ""
    )

    # Verifier si le lecteur est deja mappe
    if (Test-Path "${DriveLetter}:") {
        Write-Log "Le lecteur ${DriveLetter}: est deja mappe" -Level "WARNING"
        return
    }

    # Verifier si le partage existe
    if (-not (Test-Path $NetworkPath)) {
        Write-Log "Le partage reseau $NetworkPath n'est pas accessible" -Level "ERROR"
        return
    }

    try {
        # Monter le lecteur
        $Result = New-PSDrive -Name $DriveLetter -PSProvider FileSystem -Root $NetworkPath -Persist:$Persistent -Scope Global -Description $Description -ErrorAction Stop
        
        Write-Log "Lecteur ${DriveLetter}: mappe avec succes vers $NetworkPath ($Description)"
        return $true
    }
    catch {
        Write-Log "Erreur lors du mappage de ${DriveLetter}: vers $NetworkPath - $_" -Level "ERROR"
        return $false
    }
}

# Detection du departement de l'utilisateur (a partir du nom de l'ordinateur ou autre methode)
$ComputerName = $env:COMPUTERNAME
$UserDept = "06"  # Valeur par defaut, a adapter selon votre logique

# Exemple de detection du departement a partir du nom de l'ordinateur
if ($ComputerName -match "83") { $UserDept = "83" }
elseif ($ComputerName -match "94") { $UserDept = "94" }

Write-Log "Departement detecte : $UserDept"

# Monter les lecteurs selon la configuration
$DriveMappings = @(
    @{Letter = "U"; Path = "$BasePath\Utilisateurs\$env:USERNAME"; Description = "Dossier personnel" },
    @{Letter = "M"; Path = "$BasePath\Medical_$UserDept"; Description = "Dossier Medical" },
    @{Letter = "S"; Path = "$BasePath\Administratif_$UserDept"; Description = "Administratif/Animation" },
    @{Letter = "P"; Path = "$BasePath\Compta_$UserDept"; Description = "Comptabilite" },
    @{Letter = "Z"; Path = "$BasePath\Bibles_$UserDept"; Description = "Bibles et procedures" },
    @{Letter = "T"; Path = "$BasePath\Technique_$UserDept"; Description = "Documents techniques" },
    @{Letter = "X"; Path = "$BasePath\Cadres_$UserDept"; Description = "Documents cadres" }
)

# Application des mappages
foreach ($Mapping in $DriveMappings) {
    Mount-NetworkDrive -DriveLetter $Mapping.Letter -NetworkPath $Mapping.Path -Description $Mapping.Description
}

# Verification finale
$MappedDrives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.DisplayRoot -like "\\*" }
Write-Log "Recapitulatif des lecteurs mappes :"
$MappedDrives | ForEach-Object {
    Write-Log "  $($_.Name): $($_.DisplayRoot)"
}

# Optionnel : Ajouter au script de login utilisateur
Write-Host "Montage des lecteurs reseau termine"
Write-Host "U: Votre dossier personnel"
Write-Host "M: Dossier Medical"
Write-Host "S: Administratif/Animation"
Write-Host "P: Comptabilite"
Write-Host "Z: Bibles et procedures"
Write-Host "T: Documents techniques"
Write-Host "X: Documents cadres"

# Fin du script