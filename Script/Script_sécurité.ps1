# Comptes inactifs depuis plus de 30 jours
$DaysInactive = 30
$InactiveDate = (Get-Date).AddDays(-$DaysInactive)

$InactiveUsers = Get-ADUser -Filter {LastLogonDate -lt $InactiveDate -and Enabled -eq $true} -Properties LastLogonDate | 
                 Select-Object Name, SamAccountName, LastLogonDate | 
                 Sort-Object LastLogonDate

$ReportPath = "C:\Audit\Comptes_Inactifs_$(Get-Date -Format 'yyyyMMdd').csv"
$InactiveUsers | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8

Write-Host "Rapport des comptes inactifs genere : $ReportPath"


# Doublons de noms et emails
$AllUsers = Get-ADUser -Filter * -Properties DisplayName, Mail

# Doublons de noms complets
$DuplicateNames = $AllUsers | Group-Object DisplayName | Where-Object { $_.Count -gt 1 }
$DuplicateNames | ForEach-Object {
    Write-Warning "Doublon detecte pour le nom : $($_.Name)"
    $_.Group | Select-Object SamAccountName, DisplayName
}

# Doublons d'adresses email
$DuplicateEmails = $AllUsers | Where-Object { $_.Mail } | Group-Object Mail | Where-Object { $_.Count -gt 1 }
$DuplicateEmails | ForEach-Object {
    Write-Warning "Doublon d'email detecte : $($_.Name)"
    $_.Group | Select-Object SamAccountName, Mail
}

# Export CSV
$DuplicateReport = "C:\Audit\Doublons_AD_$(Get-Date -Format 'yyyyMMdd').csv"
$DuplicateNames + $DuplicateEmails | Export-Csv -Path $DuplicateReport -NoTypeInformation -Encoding UTF8

# Surveiller les connexions entre 20h et 6h
$AfterHoursStart = 20
$AfterHoursEnd = 6

$RecentLogons = Get-ADUser -Filter {LastLogonDate -gt (Get-Date).AddDays(-1)} -Properties LastLogonDate

foreach ($User in $RecentLogons) {
    if ($User.LastLogonDate) {
        $Hour = $User.LastLogonDate.Hour
        if ($Hour -ge $AfterHoursStart -or $Hour -le $AfterHoursEnd) {
            Write-Warning "Connexion en dehors des heures normales : $($User.SamAccountName) a $($User.LastLogonDate)"
            # Envoyer une alerte par email
            Send-MailMessage -To "security@pourlesvieux.fr" -Subject "Alerte Connexion" -Body "Utilisateur $($User.Name) connecte a $($User.LastLogonDate)" -From "noreply@pourlesvieux.fr" -SmtpServer "smtp.pourlesvieux.fr"
        }
    }
}


# Trouver les utilisateurs avec trop de privileges

Get-ADUser -Filter * -Properties MemberOf | Where-Object {
    $_.MemberOf -match "Domain Admins|Enterprise Admins|Schema Admins" -and $_.Enabled -eq $true
} | Select-Object Name, SamAccountName


# Detecter les modifications recentes de GPO

Get-WinEvent -LogName "Microsoft-Windows-GroupPolicy/Operational" -MaxEvents 20 | 
Where-Object { $_.Id -eq 4016 } | 
Select-Object TimeCreated, Message


# Verifier les services vulnerables

Get-Service | Where-Object { 
    $_.StartType -eq "Automatic" -and $_.Status -eq "Running" -and $_.Name -match "TermService|Spooler|WinRM"
} | Select-Object Name, DisplayName




