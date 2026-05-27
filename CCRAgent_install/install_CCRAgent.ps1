try {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $srcJar = Join-Path $scriptDir 'CCRAgent.jar'

    Write-Host '=== CustomCarRadio - Installation CCRAgent ===' -ForegroundColor Cyan

    if (-not (Test-Path $srcJar)) {
        throw "CCRAgent.jar introuvable dans Contents\mods\CustomCarRadio\"
    }

    # Trouver Steam
    try {
        $steamPath = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -Name 'SteamPath' -EA Stop).SteamPath -replace '/', '\'
    } catch {
        $steamPath = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -Name 'InstallPath' -EA Stop).InstallPath
    }

    Write-Host "Steam trouve: $steamPath"

    # Bibliotheques Steam
    $libraries = @($steamPath)
    $vdf = Join-Path $steamPath 'steamapps\libraryfolders.vdf'

    if (Test-Path $vdf) {
        $vdfContent = Get-Content $vdf -Raw
        [regex]::Matches($vdfContent, '"path"\s+"([^"]+)"') | ForEach-Object {
            $p = $_.Groups[1].Value -replace '\\\\', '\'
            if ($p -and $p -ne $steamPath) {
                $libraries += $p
            }
        }
    }

    # Trouver PZ
    $pzPath = $null

    foreach ($lib in $libraries) {
        $candidate = Join-Path $lib 'steamapps\common\ProjectZomboid'
        if (Test-Path (Join-Path $candidate 'ProjectZomboid64.json')) {
            $pzPath = $candidate
            break
        }
    }

    if (-not $pzPath) {
        throw "Project Zomboid introuvable dans vos bibliotheques Steam."
    }

    Write-Host "Project Zomboid trouve: $pzPath"

    # Dossier CCR_install
    $ccrDir = Join-Path $env:USERPROFILE 'Zomboid\CCR_install'

    if (-not (Test-Path $ccrDir)) {
        New-Item -ItemType Directory -Path $ccrDir | Out-Null
    }

    $dstJar = Join-Path $ccrDir 'CCRAgent.jar'
    $dstJarFwd = $dstJar -replace '\\', '/'

    Copy-Item $srcJar $dstJar -Force
    Write-Host "CCRAgent.jar copie vers $dstJar" -ForegroundColor Green

    # Copier les scripts install/uninstall dans CCR_install
    foreach ($f in @('install_CCRAgent.bat','install_CCRAgent.ps1','uninstall_CCRAgent.bat','uninstall_CCRAgent.ps1')) {
        $src = Join-Path $scriptDir $f
        if (Test-Path $src) {
            Copy-Item $src (Join-Path $ccrDir $f) -Force
        }
    }
    Write-Host "Scripts copies dans $ccrDir" -ForegroundColor Green

    # Backup
    $backupDir = Join-Path $ccrDir 'CCRAgent_backup'

    if (-not (Test-Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir | Out-Null
    }

    # ---------------- JSON ----------------
    $jsonPath = Join-Path $pzPath 'ProjectZomboid64.json'
    $jsonBackup = Join-Path $backupDir 'ProjectZomboid64.json'

    if (-not (Test-Path $jsonBackup)) {
        Copy-Item $jsonPath $jsonBackup
        Write-Host "Backup: ProjectZomboid64.json sauvegarde" -ForegroundColor Gray
    }

    $json = Get-Content $jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $agentArg = "-javaagent:$dstJarFwd"

    if (-not $json.vmArgs) {
        $json | Add-Member -MemberType NoteProperty -Name vmArgs -Value @()
    }

    if ($json.vmArgs -contains $agentArg) {
        Write-Host "ProjectZomboid64.json : javaagent deja present" -ForegroundColor Yellow
    }
    else {
        $json.vmArgs = @($agentArg) + @($json.vmArgs)

        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        $jsonText = $json | ConvertTo-Json -Depth 50

        [System.IO.File]::WriteAllText($jsonPath, $jsonText, $utf8NoBom)

        try {
            Get-Content $jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
            Write-Host "ProjectZomboid64.json valide" -ForegroundColor Green
        }
        catch {
            Copy-Item $jsonBackup $jsonPath -Force
            throw "JSON invalide apres modification. Backup restaure."
        }

        Write-Host "ProjectZomboid64.json mis a jour" -ForegroundColor Green
    }

    # ---------------- BAT ----------------
    $batPath = Join-Path $pzPath 'ProjectZomboid64.bat'
    $batBackup = Join-Path $backupDir 'ProjectZomboid64.bat'

    if (Test-Path $batPath) {
        if (-not (Test-Path $batBackup)) {
            Copy-Item $batPath $batBackup
            Write-Host "Backup: ProjectZomboid64.bat sauvegarde" -ForegroundColor Gray
        }

        $batContent = Get-Content $batPath -Raw -Encoding UTF8

        if ($batContent -match [regex]::Escape($agentArg)) {
            Write-Host "ProjectZomboid64.bat : javaagent deja present" -ForegroundColor Yellow
        }
        elseif ($batContent -match '-javaagent:') {
            Write-Host "ProjectZomboid64.bat : un autre javaagent existe deja, modification ignoree" -ForegroundColor Yellow
        }
        else {
            $escapedAgent = '-javaagent:"' + $dstJar + '"'

            $newBatContent = $batContent -replace '(?i)(jre64\\bin\\java\.exe(?:\.exe)?")?\s*', '$0'

            if ($batContent -match '(?i)(jre64\\bin\\java\.exe(?:\.exe)?)(\s+)') {
                $newBatContent = [regex]::Replace(
                    $batContent,
                    '(?i)(jre64\\bin\\java\.exe(?:\.exe)?)(\s+)',
                    "`$1 $escapedAgent`$2",
                    1
                )
            }
            elseif ($batContent -match '(?i)(".*?jre64\\bin\\java\.exe")(\s+)') {
                $newBatContent = [regex]::Replace(
                    $batContent,
                    '(?i)(".*?jre64\\bin\\java\.exe")(\s+)',
                    "`$1 $escapedAgent`$2",
                    1
                )
            }
            else {
                throw "Impossible de trouver jre64\bin\java.exe dans ProjectZomboid64.bat"
            }

            [System.IO.File]::WriteAllText($batPath, $newBatContent, [System.Text.Encoding]::UTF8)
            Write-Host "ProjectZomboid64.bat mis a jour" -ForegroundColor Green
        }
    }
    else {
        Write-Host "ProjectZomboid64.bat introuvable, ignore" -ForegroundColor Yellow
    }

    Write-Host ''
    Write-Host 'Installation terminee ! Lancez Project Zomboid normalement.' -ForegroundColor Cyan
    Write-Host "(Backup originaux dans: $backupDir)" -ForegroundColor Gray
}
catch {
    Write-Host ''
    Write-Host "ERREUR: $_" -ForegroundColor Red
}

Read-Host "`nAppuyez sur Entree pour fermer"