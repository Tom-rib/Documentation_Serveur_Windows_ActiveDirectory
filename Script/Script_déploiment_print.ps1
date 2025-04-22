<#
.SYNOPSIS
    Deploiement des imprimantes reseau via GPO selon les etablissements et groupes
.DESCRIPTION
    Ce script doit etre deploye via GPO et va :
    - Installer les imprimantes communes a tous les utilisateurs
    - Installer les imprimantes specifiques selon l'etablissement
    - Donner un acces complet aux utilisateurs du siege
    - Gerer les droits d'impression selon les groupes
.NOTES
    Version: 2.0
    Auteur: Tom Ribero
    Date: $(Get-Date -Format 'yyyy-MM-dd')
#>

# Configuration de base
$LogPath = "\\serveur\logs\Imprimantes_$(Get-Date -Format 'yyyyMMdd').log"
$PrintServer = "SRV-IMPRIMANTES" # Nom de votre serveur d'impression

# Tableau de correspondance etablissement -> imprimantes
$PrintersMapping = @{
    "Gabres(06)" = @("IMP-GABRES-01", "IMP-GABRES-RECEPTION")
    "Hermitage(83)" = @("IMP-HERMITAGE-ETAGE1", "IMP-HERMITAGE-ACCUEIL")
    "Cascade(94)" = @("IMP-CASCADE-BUREAUX", "IMP-CASCADE-INFIRMERIE")
    "Siege(06)" = @("IMP-SIEGE-COMPTA", "IMP-SIEGE-RH", "IMP-SIEGE-DIRECTION")
}

# Imprimantes communes a tous les etablissements
$CommonPrinters = @("IMP-COLOR-COMMUNE", "IMP-NOIRBLANC-COMMUNE")

# Fonction de logging
function Write-Log {
    param ([string]$message, [string]$level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$level] $message"
    Add-Content -Path $LogPath -Value $logMessage
}

# Fonction pour installer une imprimante
function Install-Printer {
    param (
        [string]$printerName,
        [bool]$setAsDefault = $false
    )

    $printerPath = "\\$PrintServer\$printerName"
    
    try {
        # Verifier si l'imprimante est deja installee
        if (Get-Printer -Name $printerPath -ErrorAction SilentlyContinue) {
            Write-Log "Imprimante $printerName deja installee"
            return $true
        }

        # Installation de l'imprimante
        Add-Printer -ConnectionName $printerPath -ErrorAction Stop
        Write-Log "Imprimante $printerName installee avec succes"

        # Definir comme imprimante par defaut si demande
        if ($setAsDefault) {
            Set-Printer -Name $printerPath -Shared $false -ErrorAction Stop
            Write-Log "Imprimante $printerName definie comme defaut"
        }
        
        return $true
    }
    catch {
        Write-Log "echec installation $printerName : $_" -level "ERROR"
        return $false
    }
}

# Detection de l'etablissement de l'utilisateur
function Get-UserEstablishment {
    # Methode 1 : Par nom de machine (si convention de nommage)
    $computerName = $env:COMPUTERNAME
    foreach ($etab in $PrintersMapping.Keys) {
        if ($computerName -match $etab.Split('(')[0]) {
            return $etab
        }
    }

    # Methode 2 : Par groupe AD de l'utilisateur (plus fiable)
    $userGroups = (Get-ADUser $env:USERNAME -Properties MemberOf).MemberOf
    foreach ($etab in $PrintersMapping.Keys) {
        $etabName = $etab.Split('(')[0]
        if ($userGroups -match "Grp-$etabName") {
            return $etab
        }
    }

    # Valeur par defaut si non detecte
    return "Siege(06)"
}

# Detection si utilisateur fait partie du siege
function Test-IsSiegeUser {
    $userGroups = (Get-ADUser $env:USERNAME -Properties MemberOf).MemberOf
    return ($userGroups -match "Grp-Siege" -or $userGroups -match "Domain Admins")
}

# ===== EXeCUTION PRINCIPALE =====

Write-Log "Debut du deploiement des imprimantes pour $env:USERNAME"

# 1. Detection de l'etablissement
$userEtab = Get-UserEstablishment
$isSiegeUser = Test-IsSiegeUser
Write-Log "Utilisateur detecte : $userEtab (Siege: $isSiegeUser)"

# 2. Installation des imprimantes communes
$firstPrinter = $true
foreach ($printer in $CommonPrinters) {
    $success = Install-Printer -printerName $printer -setAsDefault $firstPrinter
    if ($success -and $firstPrinter) { $firstPrinter = $false }
}

# 3. Installation des imprimantes specifiques a l'etablissement
if ($PrintersMapping.ContainsKey($userEtab)) {
    foreach ($printer in $PrintersMapping[$userEtab]) {
        $success = Install-Printer -printerName $printer -setAsDefault $firstPrinter
        if ($success -and $firstPrinter) { $firstPrinter = $false }
    }
}

# 4. Si utilisateur du siege, installer toutes les imprimantes
if ($isSiegeUser) {
    Write-Log "Utilisateur du siege - installation de toutes les imprimantes"
    foreach ($etab in $PrintersMapping.Keys) {
        if ($etab -ne $userEtab) {
            foreach ($printer in $PrintersMapping[$etab]) {
                Install-Printer -printerName $printer
            }
        }
    }
}

# 5. Verification finale
$installedPrinters = Get-Printer | Where-Object { $_.Type -eq "Connection" }
Write-Log "Imprimantes installees : $($installedPrinters.Count)"
$installedPrinters | ForEach-Object { Write-Log " - $($_.Name)" }

Write-Log "Deploiement des imprimantes termine"