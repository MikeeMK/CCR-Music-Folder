try {
    Write-Host '=== CustomCarRadio - Desinstallation CCRAgent ===' -ForegroundColor Cyan

    # Trouver Steam
    $steamPath = $null
    try {
        $steamPath = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -Name 'SteamPath' -EA Stop).SteamPath -replace '/', '\'
    } catch {
        $steamPath = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -Name 'InstallPath' -EA Stop).InstallPath
    }
    Write-Host "Steam trouve: $steamPath"

    # Collecter toutes les bibliotheques Steam
    $libraries = @($steamPath)
    $vdf = Join-Path $steamPath 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
        $vdfContent = Get-Content $vdf -Raw
        [regex]::Matches($vdfContent, '"path"\s+"([^"]+)"') | ForEach-Object {
            $p = $_.Groups[1].Value -replace '\\\\', '\'
            if ($p -ne $steamPath) { $libraries += $p }
        }
    }

    # Trouver Project Zomboid
    $pzPath = $null
    foreach ($lib in $libraries) {
        $candidate = Join-Path $lib 'steamapps\common\ProjectZomboid'
        if (Test-Path (Join-Path $candidate 'ProjectZomboid64.json')) {
            $pzPath = $candidate
            break
        }
    }
    if (-not $pzPath) { throw "Project Zomboid introuvable dans vos bibliotheques Steam." }
    Write-Host "Project Zomboid trouve: $pzPath"

    $ccrDir    = Join-Path $env:USERPROFILE 'Zomboid\CCR_install'
    $backupDir = Join-Path $ccrDir 'CCRAgent_backup'

    # --- Supprimer le JAR ---
    $dstJar = Join-Path $ccrDir 'CCRAgent.jar'
    if (Test-Path $dstJar) {
        Remove-Item $dstJar -Force
        Write-Host 'CCRAgent.jar supprime.' -ForegroundColor Green
    } else {
        Write-Host 'CCRAgent.jar deja absent.' -ForegroundColor Yellow
    }

    # --- Restaurer ProjectZomboid64.json ---
    $jsonPath   = Join-Path $pzPath 'ProjectZomboid64.json'
    $jsonBackup = Join-Path $backupDir 'ProjectZomboid64.json'
    if (Test-Path $jsonBackup) {
        Copy-Item $jsonBackup $jsonPath -Force
        Write-Host 'ProjectZomboid64.json restaure (original).' -ForegroundColor Green
    } elseif (Test-Path $jsonPath) {
        $c = Get-Content $jsonPath -Raw -Encoding UTF8
        if ($c -match 'CCRAgent') {
            $c = [regex]::Replace($c, '\s*"-javaagent:[^"]*CCRAgent\.jar",?', '')
            $c = [regex]::Replace($c, ',(\s*\])', '$1')
            [System.IO.File]::WriteAllText($jsonPath, $c, [System.Text.Encoding]::UTF8)
            Write-Host 'ProjectZomboid64.json : javaagent retire (pas de backup).' -ForegroundColor Yellow
        } else {
            Write-Host 'ProjectZomboid64.json : javaagent deja absent.' -ForegroundColor Yellow
        }
    }

    # --- Restaurer ProjectZomboid64.bat ---
    $batPath   = Join-Path $pzPath 'ProjectZomboid64.bat'
    $batBackup = Join-Path $backupDir 'ProjectZomboid64.bat'
    if (Test-Path $batBackup) {
        Copy-Item $batBackup $batPath -Force
        Write-Host 'ProjectZomboid64.bat restaure (original).' -ForegroundColor Green
    } elseif (Test-Path $batPath) {
        $batContent = Get-Content $batPath -Raw -Encoding UTF8
        if ($batContent -match '-javaagent:') {
            $batContent = $batContent -replace ' -javaagent:"?[^"\s]*CCRAgent\.jar"?', ''
            [System.IO.File]::WriteAllText($batPath, $batContent, [System.Text.Encoding]::UTF8)
            Write-Host 'ProjectZomboid64.bat : javaagent retire (pas de backup).' -ForegroundColor Yellow
        } else {
            Write-Host 'ProjectZomboid64.bat : javaagent deja absent.' -ForegroundColor Yellow
        }
    }

    # --- Supprimer le dossier CCR_install entier ---
    if (Test-Path $ccrDir) {
        Remove-Item $ccrDir -Recurse -Force
        Write-Host "Dossier CCR_install supprime." -ForegroundColor Gray
    }

    Write-Host ''
    Write-Host 'Desinstallation terminee ! Fichiers PZ remis a leur etat original.' -ForegroundColor Cyan

} catch {
    Write-Host ''
    Write-Host "ERREUR: $_" -ForegroundColor Red
}

Read-Host "`nAppuyez sur Entree pour fermer"
