# Importation des modules necessaires
Import-Module ActiveDirectory
Import-Module GroupPolicy

# Parametres de configuration globaux
$Domain = "pourlesvieux.fr"
$BaseDN = "DC=pourlesvieux,DC=fr"
$SharedFolderRoot = "C:\Partages"
$Password = ConvertTo-SecureString "Azerty06!" -AsPlainText -Force

# Definition des etablissements avec leur type (siege ou non)
$Etablissements = @(
    @{Nom = "Siege"; CodeDepartement = "06"; IsSiege = $true},
    @{Nom = "Gabres"; CodeDepartement = "06"; IsSiege = $false},
    @{Nom = "hermitage"; CodeDepartement = "83"; IsSiege = $false},
    @{Nom = "Cascade"; CodeDepartement = "94"; IsSiege = $false}
)

# Definition complete des groupes et permissions
$GroupDefinitions = @{
    # Groupes standards
    "Medical" = @("Infirmiers", "Medecin", "Secretaire medical")
    "Medical_Lecture" = @("Aides soignant")
    "Administratif" = @("Tous")
    "Animation_Lecture" = @("Tous")
    "Animation_Full" = @("Cadres", "Animation")
    "Technique_Full" = @("Cadres", "Technique", "Informaticien")
    "Compta_Full" = @("Comptables", "Direction")
    "Cadres_Full" = @("Cadres")
    "Bibles_Lecture" = @("Tous")
    "Bibles_Full" = @("Direction", "Qualiticien")
    
    # Groupes specifiques au siege
    "ComptaSiege_Full" = @("Comptasiege", "Direction")
    "TechniqueSiege_Full" = @("ResponsableTechnique")
    "DGSiege_Full" = @("DG", "DRH")
    "QualiticienSiege_Full" = @("Qualiticien")
}

# Fonction pour creer les permissions NTFS
function Set-FolderPermissions {
    param (
        [string]$FolderPath,
        [string]$GroupName,
        [string]$Permission
    )
    
    $acl = Get-Acl $FolderPath
    $group = New-Object System.Security.Principal.NTAccount("$Domain\$GroupName")
    
    switch ($Permission) {
        "Lecture" {
            $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $group, "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow"
            )
        }
        "ControleTotal" {
            $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $group, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
            )
        }
        "AucunAcces" {
            $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $group, "FullControl", "ContainerInherit,ObjectInherit", "None", "Deny"
            )
        }
    }
    
    $acl.AddAccessRule($accessRule)
    Set-Acl -Path $FolderPath -AclObject $acl
}

# Fonction pour creer la structure AD de base
function Create-ADInfrastructure {
    param (
        [string]$EtablissementName,
        [string]$BaseDN
    )
    
    try {
        # Creation de l'OU principale
        New-ADOrganizationalUnit -Name $EtablissementName -Path $BaseDN -ErrorAction Stop
        
        # Creation des sous-OUs
        New-ADOrganizationalUnit -Name "Groupes" -Path "OU=$EtablissementName,$BaseDN"
        New-ADOrganizationalUnit -Name "Ordinateurs" -Path "OU=$EtablissementName,$BaseDN"
        New-ADOrganizationalUnit -Name "Utilisateurs" -Path "OU=$EtablissementName,$BaseDN"
        
        # Creation de la GPO
        $gpo = New-GPO -Name "GPO_$EtablissementName" -ErrorAction Stop
        $gpo | New-GPLink -Target "OU=$EtablissementName,$BaseDN"
        
        return $true
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityAlreadyExistsException] {
        Write-Warning "L'OU $EtablissementName existe deja"
        return $false
    }
    catch {
        Write-Warning "Erreur lors de la creation de l'infrastructure AD pour $EtablissementName : $_"
        return $false
    }
}

# Fonction pour creer les dossiers partages avec permissions
function Create-SharedFolders {
    param (
        [string]$EtablissementName,
        [string]$CodeDepartement,
        [bool]$IsSiege
    )
    
    if (-not $IsSiege) {
        # Dossiers pour les etablissements normaux
        $dossiers = @{
            "DossierUtillisateur_$CodeDepartement" = @{}
            "Medical_$CodeDepartement" = @{
                "Medical" = "ControleTotal"
                "Medical_Lecture" = "Lecture"
            }
            "Administratif_$CodeDepartement" = @{
                "Administratif" = "ControleTotal"
            }
            "Animation_$CodeDepartement" = @{
                "Animation_Lecture" = "Lecture"
                "Animation_Full" = "ControleTotal"
            }
            "Technique_$CodeDepartement" = @{
                "Tous" = "AucunAcces"
                "Technique_Full" = "ControleTotal"
            }
            "Compta_$CodeDepartement" = @{
                "Tous" = "AucunAcces"
                "Compta_Full" = "ControleTotal"
            }
            "Cadres_$CodeDepartement" = @{
                "Cadres_Full" = "ControleTotal"
                "Tous" = "AucunAcces"
            }
            "Bibles_$CodeDepartement" = @{
                "Bibles_Lecture" = "Lecture"
                "Bibles_Full" = "ControleTotal"
            }
        }
    }
    else {
        # Dossiers specifiques pour le siege
        $dossiers = @{
            "Administratif_$CodeDepartement" = @{
                "Administratif" = "ControleTotal"
            }
            "Compta_$CodeDepartement" = @{
                "ComptaSiege_Full" = "ControleTotal"
                "Tous" = "AucunAcces"
            }
        }
    }

    foreach ($dossier in $dossiers.Keys) {
        $fullPath = Join-Path -Path $SharedFolderRoot -ChildPath $dossier
        
        try {
            if (-not (Test-Path $fullPath)) {
                New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
                Write-Host "Dossier cree : $fullPath"
            }
            
            # Application des permissions
            foreach ($group in $dossiers[$dossier].Keys) {
                Set-FolderPermissions -FolderPath $fullPath -GroupName $group -Permission $dossiers[$dossier][$group]
            }
        }
        catch {
            Write-Warning "Erreur lors de la creation/config du dossier $dossier : $_"
        }
    }
}

# Fonction pour configurer les acces transversaux du siege
function Configure-SiegeAccess {
    param (
        [string]$SiegeCodeDep,
        [array]$OtherEtablissements
    )
    
    foreach ($otherEtab in $OtherEtablissements) {
        $otherCodeDep = $otherEtab.CodeDepartement

        # Acces Compta pour le siege
        $comptaPath = Join-Path -Path $SharedFolderRoot -ChildPath "Compta_$otherCodeDep"
        Set-FolderPermissions -FolderPath $comptaPath -GroupName "ComptaSiege_Full" -Permission "ControleTotal"

        # Acces Technique pour le responsable technique
        $techPath = Join-Path -Path $SharedFolderRoot -ChildPath "Technique_$otherCodeDep"
        Set-FolderPermissions -FolderPath $techPath -GroupName "TechniqueSiege_Full" -Permission "ControleTotal"

        # Acces DG/DRH (sauf medical)
        $excludedFolders = @("Medical_$otherCodeDep")
        Get-ChildItem $SharedFolderRoot -Directory | Where-Object {
            $_.Name -like "*_$otherCodeDep" -and $_.Name -notin $excludedFolders
        } | ForEach-Object {
            Set-FolderPermissions -FolderPath $_.FullName -GroupName "DGSiege_Full" -Permission "ControleTotal"
        }

        # Acces Qualiticien (lecture seule sauf Administratif et Bibles)
        Get-ChildItem $SharedFolderRoot -Directory | Where-Object {
            $_.Name -like "*_$otherCodeDep"
        } | ForEach-Object {
            if ($_.Name -in @("Administratif_$otherCodeDep", "Bibles_$otherCodeDep")) {
                Set-FolderPermissions -FolderPath $_.FullName -GroupName "QualiticienSiege_Full" -Permission "ControleTotal"
            }
            else {
                Set-FolderPermissions -FolderPath $_.FullName -GroupName "QualiticienSiege_Full" -Permission "Lecture"
            }
        }
    }
}

# Fonction pour importer les utilisateurs depuis CSV
function Import-UsersFromCSV {
    param (
        [string]$EtablissementName,
        [string]$BaseDN,
        [securestring]$Password
    )
    
    $CSVPath = "C:\Users\$EtablissementName.csv"
    if (-not (Test-Path $CSVPath)) {
        Write-Warning "Fichier CSV introuvable : $CSVPath"
        return
    }

    $Users = Import-Csv -Path $CSVPath -Delimiter ","
    
    foreach ($User in $Users) {
        $GivenName = $User.Prenom
        $Surname = $User.Nom
        $Function = $User.Fonction
        $Groups = $User.Groupes -split ","
        $UserPrincipalName = "$GivenName.$Surname@$Domain"
        $SamAccountName = "$GivenName.$Surname"
        $DisplayName = "$GivenName $Surname"

        try {
            # Creation de l'utilisateur
            New-ADUser -Name $DisplayName `
                       -GivenName $GivenName `
                       -Surname $Surname `
                       -UserPrincipalName $UserPrincipalName `
                       -SamAccountName $SamAccountName `
                       -AccountPassword $Password `
                       -Enabled $true `
                       -Path "OU=Utilisateurs,OU=$EtablissementName,$BaseDN" `
                       -ErrorAction Stop

            Write-Host "Utilisateur cree : $DisplayName"

            # Ajout aux groupes
            foreach ($Group in $Groups) {
                try {
                    Add-ADGroupMember -Identity $Group -Members $SamAccountName -ErrorAction Stop
                    Write-Host "  - Ajoute au groupe : $Group"
                }
                catch {
                    Write-Warning "  - Impossible d'ajouter $SamAccountName au groupe $Group : $_"
                }
            }
        }
        catch {
            Write-Warning "Erreur lors de la creation de l'utilisateur $DisplayName : $_"
        }
    }
}

# ==============================================
# EXeCUTION PRINCIPALE DU SCRIPT
# ==============================================

# Creation des groupes AD
foreach ($groupName in $GroupDefinitions.Keys) {
    try {
        if (-not (Get-ADGroup -Filter {Name -eq $groupName})) {
            New-ADGroup -Name $groupName -GroupScope Global -Path "OU=Groupes,$BaseDN"
            Write-Host "Groupe cree : $groupName"
        }
    }
    catch {
        Write-Warning "Erreur lors de la creation du groupe $groupName : $_"
    }
}

# Traitement pour chaque etablissement
foreach ($Etablissement in $Etablissements) {
    $EtabName = $Etablissement.Nom
    $CodeDep = $Etablissement.CodeDepartement
    $IsSiege = $Etablissement.IsSiege

    Write-Host "`nTraitement de l'etablissement : $EtabName" -ForegroundColor Cyan

    # 1. Creation de l'infrastructure AD
    $infraCreated = Create-ADInfrastructure -EtablissementName $EtabName -BaseDN $BaseDN

    # 2. Creation des dossiers partages
    Create-SharedFolders -EtablissementName $EtabName -CodeDepartement $CodeDep -IsSiege $IsSiege

    # 3. Configuration des acces transversaux pour le siege
    if ($IsSiege) {
        $otherEtablissements = $Etablissements | Where-Object { -not $_.IsSiege }
        Configure-SiegeAccess -SiegeCodeDep $CodeDep -OtherEtablissements $otherEtablissements
    }

    # 4. Importation des utilisateurs
    Import-UsersFromCSV -EtablissementName $EtabName -BaseDN $BaseDN -Password $Password
}

Write-Host "`nConfiguration terminee avec succes !" -ForegroundColor Green