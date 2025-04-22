# Importer le module Active Directory
Import-Module ActiveDirectory
 
# Definir les parametres communs
$Password = ConvertTo-SecureString "Azerty06!" -AsPlainText -Force
$Domain = "pourlesvieux.fr"
 
# Configuration des etablissements et departements
$Etablissements = @{
    "Gabres"     = "06"
    "Hermitage"  = "83"
    "Cascade"    = "94"
    "Siege"      = "06"
}
 
# Creation des OU principales formatees
foreach ($etablissement in $Etablissements.Keys) {
    $dept = $Etablissements[$etablissement]
    $ouName = "$etablissement($dept)"
    $ouPath = "OU=$ouName,DC=pourlesvieux,DC=fr"
   
    # Creer l'OU principale avec le departement
    try {
        New-ADOrganizationalUnit -Name $ouName -Path "DC=pourlesvieux,DC=fr" -ErrorAction Stop
        Write-Host "OU $ouName creee"
    } catch {
        Write-Warning "L'OU $ouName existe deja "
    }
 
    # Creer les sous-OU
    $subOUs = @("Utilisateurs", "Groupes", "Ordinateurs")
    foreach ($subOU in $subOUs) {
        try {
            New-ADOrganizationalUnit -Name $subOU -Path $ouPath -ErrorAction Stop
            Write-Host "Sous-OU $subOU creee dans $ouName"
        } catch {
            Write-Warning "La sous-OU $subOU existe deja  dans $ouName"
        }
    }
 
    # Creer les groupes departementaux
    $groupes = @("Administratif", "Cadres", "Compta", "Animation", "Medical", "Technique")
    foreach ($groupe in $groupes) {
        $nomGroupe = "$groupe$dept"
        try {
            New-ADGroup -Name $nomGroupe `
                        -GroupCategory Security `
                        -GroupScope Global `
                        -Path "OU=Groupes,$ouPath" `
                        -ErrorAction Stop
            Write-Host "Groupe $nomGroupe cree"
        } catch {
            Write-Warning "Le groupe $nomGroupe existe deja "
        }
    }
}
 
# Definir les regles d'appartenance aux groupes
$groupMappings = @{
    "Administratif" = "AS|ASH|secretaire|Maitresse de Maison|Directeur|DRH|Qualiticien"
    "Cadres"        = "cadres|cadre|Directeur|DRH|Qualiticien|responsable"
    "Compta"        = "Comptable"
    "Animation"     = "Animation"
    "Medical"       = "Medecin|Psychologue|IDE|Infirmier"
    "Technique"     = "technique|Informaticien"
}
 
# Importer le CSV et creer les utilisateurs
$users = Import-Csv -Path "./users.csv" -Delimiter ","
 
foreach ($user in $users) {
    $baseEtablissement = $user.ETABLISSEMENT
    $dept = $Etablissements[$baseEtablissement]
    $ouName = "$baseEtablissement($dept)"
    $fonction = $user.FONCTION
   
    # Formater le nom d'utilisateur
    $username = ($user.PRENOM.ToLower() + "." + $user.NOM.ToLower()) -replace '[eeÃªÃ«]','e' -replace '[Ã Ã¢Ã¤]','a' -replace '[Ã®Ã¯]','i' -replace '[Ã´Ã¶]','o' -replace '[Ã¹Ã»Ã¼]','u'
    $userOU = "OU=Utilisateurs,OU=$ouName,DC=pourlesvieux,DC=fr"
 
    # Creer l'utilisateur
    try {
        New-ADUser -GivenName $user.PRENOM `
                   -Surname $user.NOM `
                   -Name "$($user.PRENOM) $($user.NOM)" `
                   -SamAccountName $username `
                   -UserPrincipalName "$username@$Domain" `
                   -AccountPassword $Password `
                   -Enabled $true `
                   -PasswordNeverExpires $false `
                   -ChangePasswordAtLogon $true `
                   -Path $userOU `
                   -ErrorAction Stop
       
        Write-Host "Utilisateur $username cree dans $ouName"
 
        # Determiner les groupes
        $groupsToAdd = @()
        foreach ($groupe in $groupMappings.Keys) {
            if ($fonction -match $groupMappings[$groupe]) {
                $groupsToAdd += "$groupe$dept"
            }
        }
 
        # Ajouter aux groupes (en evitant les doublons)
        $groupsToAdd = $groupsToAdd | Select-Object -Unique
        foreach ($groupe in $groupsToAdd) {
            try {
                Add-ADGroupMember -Identity $groupe -Members $username -ErrorAction Stop
                Write-Host "  Ajoute au groupe $groupe"
            } catch {
                Write-Warning "Erreur d'ajout au groupe $groupe : $_"
            }
        }
 
    } catch {
        Write-Warning "Erreur lors de la creation de $username : $_"
    }
}
Write-Host "Script execute avec succes !"