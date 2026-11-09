<#
.SYNOPSIS
  Bitwarden デスクトップ版を winget で入れて署名を確認し、Brave の拡張機能ページと
  アカウント作成ページを開くスクリプト（Windows 用）。

.DESCRIPTION
  作業指示の 1〜5 に対応します。
    1. winget があるか確認する
    2. winget で Bitwarden.Bitwarden をユーザー スコープでインストールする（既定 2026.10.4）
    3. Bitwarden.exe の Authenticode 署名を確認する
       → Valid かつ署名者に "Bitwarden Inc." が含まれなければ、起動せずにアンインストールして停止する
    4. Brave で Bitwarden 拡張機能（Chrome ウェブストア）のページを開く（「追加」ボタンは自分で押す）
    5. Brave で Bitwarden のアカウント作成ページを開く
  そのあと、移行（Brave からエクスポート → Bitwarden にインポート）の案内を表示します。

  このスクリプトはパスワード・マスターパスワード・CSV の中身を一切読みません。
  ファイルやログも書き出しません。表示するのはバージョンと署名の情報だけです。

.NOTES
  実行方法（PowerShell を開き、このファイルのあるフォルダーで）:
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
    .\Install-Bitwarden.ps1
  管理者権限は不要です（ユーザー スコープでインストールします）。

  事前確認済みの値（2026-11-09、クラウド側で確認）:
    winget マニフェスト Bitwarden.Bitwarden 2026.10.4（公開日 2026-11-05）
    インストーラー SHA256 = AAEDFEAF73511B9095A5009454BB037A053C9A60E7C5ED23717B7B6047193A13
      → winget はインストール前にこの値と一致するかを自動で検証します。
    署名者 = Bitwarden Inc. (Santa Barbara, California, US) / DigiCert EV コード署名
#>
[CmdletBinding()]
param(
    # インストールしたいバージョン。事前確認済みの値。
    [string]$Version = '2026.10.4',

    # Brave/Chrome 用 Bitwarden 拡張機能の Chrome ウェブストア ID
    # （公式リポジトリ bitwarden/clients の apps/browser/README.md が指しているもの）
    [string]$ExtensionId = 'nngceckbapebfimnlniiiahkandclblb'
)

$ErrorActionPreference = 'Stop'
$PackageId    = 'Bitwarden.Bitwarden'
$ExpectedSigner = 'Bitwarden Inc.'
$ExtensionUrl = "https://chromewebstore.google.com/detail/$ExtensionId"
$SignupUrl    = 'https://vault.bitwarden.com/#/signup'
$ImportUrl    = 'https://vault.bitwarden.com/#/tools/import'
$BravePasswordsUrl = 'brave://settings/passwords'

# ---------------------------------------------------------------- 表示用の小道具
function Write-Step([int]$Number, [string]$Message) {
    Write-Host ''
    Write-Host ("=" * 70) -ForegroundColor DarkGray
    Write-Host ("[{0}] {1}" -f $Number, $Message) -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor DarkGray
}
function Write-Ok([string]$Message)   { Write-Host ("  OK  " + $Message) -ForegroundColor Green }
function Write-Warn2([string]$Message){ Write-Host ("  注意 " + $Message) -ForegroundColor Yellow }
function Write-Bad([string]$Message)  { Write-Host ("  NG  " + $Message) -ForegroundColor Red }
function Write-Note([string]$Message) { Write-Host ("      " + $Message) }

function Wait-Enter([string]$Message) {
    Write-Host ''
    Read-Host ("  >> " + $Message + " （Enter で続行）") | Out-Null
}

# ---------------------------------------------------------------- Bitwarden.exe を探す
function Find-BitwardenExe {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Bitwarden\Bitwarden.exe'),   # ユーザー スコープ（今回の既定）
        (Join-Path $env:ProgramFiles  'Bitwarden\Bitwarden.exe')            # 全ユーザー向けに入っていた場合
    )
    if (${env:ProgramFiles(x86)}) {
        $candidates += (Join-Path ${env:ProgramFiles(x86)} 'Bitwarden\Bitwarden.exe')
    }
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

function Get-FileProductVersion([string]$Path) {
    try { return (Get-Item -LiteralPath $Path).VersionInfo.ProductVersion } catch { return '(不明)' }
}

# ---------------------------------------------------------------- Brave を探す
function Find-Brave {
    # Brave は App Paths に登録されるので、まずそこを見る
    foreach ($key in @(
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\brave.exe',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\brave.exe'
    )) {
        try {
            $p = (Get-ItemProperty -LiteralPath $key -ErrorAction Stop).'(default)'
            if ($p -and (Test-Path -LiteralPath $p)) { return $p }
        } catch { }
    }
    foreach ($p in @(
        (Join-Path $env:ProgramFiles  'BraveSoftware\Brave-Browser\Application\brave.exe'),
        (Join-Path $env:LOCALAPPDATA  'BraveSoftware\Brave-Browser\Application\brave.exe')
    )) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    if (${env:ProgramFiles(x86)}) {
        $p = Join-Path ${env:ProgramFiles(x86)} 'BraveSoftware\Brave-Browser\Application\brave.exe'
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Open-InBrave([string]$Url) {
    $brave = Find-Brave
    if ($brave) {
        Start-Process -FilePath $brave -ArgumentList $Url
        return $true
    }
    Write-Warn2 'Brave が見つかりませんでした。既定のブラウザーで開きます。'
    if ($Url -like 'brave://*') {
        Write-Warn2 "brave:// のページは既定のブラウザーでは開けません。Brave のアドレス バーに手で入力してください: $Url"
        return $false
    }
    Start-Process $Url
    return $true
}

# ---------------------------------------------------------------- winget 呼び出し
function Invoke-Winget([string[]]$WingetArgs) {
    Write-Note ("winget " + ($WingetArgs -join ' '))
    # winget の画面出力はそのままコンソールに流し、戻り値は終了コードだけにする
    # （& winget ... と書くと出力が戻り値に混ざって終了コードの判定が壊れる）
    $p = Start-Process -FilePath 'winget' -ArgumentList $WingetArgs -NoNewWindow -Wait -PassThru
    return [int]$p.ExitCode
}

# winget の主な終了コード
$WINGET_ALREADY_INSTALLED = -1978335189   # 0x8A15002B: すでにインストール済み
$WINGET_NO_PACKAGE_FOUND  = -1978335212   # 0x8A150014: 条件に合うパッケージが無い

# ================================================================ 1. winget の確認
Write-Step 1 'winget があるか確認します'

$wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
if (-not $wingetCmd) {
    Write-Bad 'winget が見つかりません。'
    Write-Note 'Microsoft Store で「アプリ インストーラー」を入れてから、もう一度このスクリプトを実行してください。'
    Write-Note '今から Microsoft Store のページを開きます。'
    try { Start-Process 'ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1' } catch { }
    exit 1
}
$wingetVersion = '(バージョン不明)'
try { $wingetVersion = [string](& winget --version | Select-Object -First 1) } catch { }
Write-Ok ("winget " + $wingetVersion)

# ================================================================ 2. インストール
Write-Step 2 ("Bitwarden デスクトップ版 {0} をユーザー スコープでインストールします" -f $Version)

$installedVersion = $null
$exe = Find-BitwardenExe
if ($exe) {
    $installedVersion = Get-FileProductVersion $exe
    Write-Warn2 ("Bitwarden はすでに入っています: {0} (バージョン {1})" -f $exe, $installedVersion)
    Write-Note 'インストールは行わず、このまま署名確認に進みます。'
} else {
    $code = Invoke-Winget @(
        'install', '--id', $PackageId, '--version', $Version, '--exact',
        '--source', 'winget', '--scope', 'user',
        '--accept-package-agreements', '--accept-source-agreements'
    )

    if ($code -eq $WINGET_ALREADY_INSTALLED) {
        Write-Warn2 'winget によると、すでにインストール済みです。署名確認に進みます。'
    } elseif ($code -ne 0) {
        Write-Warn2 ("winget がエラーで終わりました（終了コード {0}）。" -f $code)
        Write-Note ("バージョン {0} が見つからなかった可能性があります。現在 winget にある最新版を表示します。" -f $Version)
        Write-Host ''
        & winget show --id $PackageId --exact --source winget --accept-source-agreements
        Write-Host ''
        Write-Note '上の "Version:" の行が最新版です。'
        $answer = Read-Host '  >> 上の最新版をインストールしますか？ 署名確認はこのあと必ず行います。 (y / N)'
        if ($answer -notmatch '^(y|yes)$') {
            Write-Bad 'インストールを中止しました。winget の出力を Claude に伝えてください。'
            exit 1
        }
        $code = Invoke-Winget @(
            'install', '--id', $PackageId, '--exact',
            '--source', 'winget', '--scope', 'user',
            '--accept-package-agreements', '--accept-source-agreements'
        )
        if ($code -ne 0 -and $code -ne $WINGET_ALREADY_INSTALLED) {
            Write-Bad ("インストールに失敗しました（終了コード {0}）。winget の出力を Claude に伝えてください。" -f $code)
            exit 1
        }
    }

    $exe = Find-BitwardenExe
    if (-not $exe) {
        Write-Bad 'winget は終わりましたが Bitwarden.exe が見つかりません。ここで止まります。'
        Write-Note ('探した場所: ' + (Join-Path $env:LOCALAPPDATA 'Programs\Bitwarden\Bitwarden.exe'))
        exit 1
    }
    $installedVersion = Get-FileProductVersion $exe
    Write-Ok ("インストール完了: {0} (バージョン {1})" -f $exe, $installedVersion)
    Write-Note 'winget はダウンロードしたインストーラーの SHA256 をマニフェストの値と照合してから実行しています。'
}

# ファイルのバージョンは "2026.10.4.0" のように末尾に .0 が付くので、それを除いて比べる
if ($installedVersion -and (($installedVersion -replace '(\.0)+$', '') -ne ($Version -replace '(\.0)+$', ''))) {
    Write-Warn2 ("入っているバージョン {0} は、事前確認した {1} と違います。報告のときに伝えてください。" -f $installedVersion, $Version)
}

# ================================================================ 3. 署名確認
Write-Step 3 'Bitwarden.exe のコード署名を確認します'

$sig = Get-AuthenticodeSignature -FilePath $exe
$status  = [string]$sig.Status
$subject = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { '(署名なし)' }
$issuer  = if ($sig.SignerCertificate) { $sig.SignerCertificate.Issuer }  else { '' }

Write-Note ("ファイル    : " + $exe)
Write-Note ("Status      : " + $status)
Write-Note ("署名者      : " + $subject)
if ($issuer) {
    Write-Note ("発行者      : " + $issuer)
    Write-Note ("有効期間    : {0:yyyy-MM-dd} → {1:yyyy-MM-dd}" -f $sig.SignerCertificate.NotBefore, $sig.SignerCertificate.NotAfter)
    Write-Note ("拇印(SHA1)  : " + $sig.SignerCertificate.Thumbprint)
}
if ($sig.TimeStamperCertificate) {
    Write-Note ("タイムスタンプ: " + $sig.TimeStamperCertificate.Subject)
}

$signatureOk = ($status -eq 'Valid') -and ($subject -like ("*" + $ExpectedSigner + "*"))

if (-not $signatureOk) {
    Write-Bad ("署名確認に失敗しました（Status={0} / 署名者={1}）。" -f $status, $subject)
    Write-Bad 'Bitwarden は起動しません。アンインストールしてここで止まります。'

    # 万一起動していたら止めてからアンインストール
    Get-Process -Name 'Bitwarden' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    $uninstallCode = Invoke-Winget @('uninstall', '--id', $PackageId, '--exact', '--source', 'winget', '--accept-source-agreements')
    if ($uninstallCode -eq 0) {
        Write-Ok 'アンインストールしました。'
    } else {
        Write-Warn2 ("アンインストールに失敗しました（終了コード {0}）。「設定 → アプリ」から Bitwarden を削除してください。" -f $uninstallCode)
    }

    Write-Host ''
    Write-Host '  === Claude への報告（この内容をそのまま伝えてください） ===' -ForegroundColor Yellow
    Write-Host ("  バージョン : {0}" -f $installedVersion)
    Write-Host ("  署名確認   : 失敗（Status={0} / 署名者={1}）→ アンインストール済み" -f $status, $subject)
    exit 2
}

Write-Ok ("署名は有効で、署名者は {0} です。" -f $ExpectedSigner)

# ================================================================ 4. Brave 拡張機能ページ
Write-Step 4 'Brave で Bitwarden 拡張機能のページを開きます'
Write-Note ("拡張機能 ID : " + $ExtensionId)
Write-Note 'ページが開いたら「Brave に追加」→「拡張機能を追加」を自分で押してください。'
Write-Note '追加できたら、アドレス バー右のパズル アイコンから Bitwarden を「ピン留め」しておくと使いやすくなります。'
Wait-Enter '拡張機能のページを開きます'
Open-InBrave $ExtensionUrl | Out-Null

# ================================================================ 5. アカウント作成ページ
Write-Step 5 'Bitwarden のアカウント作成ページを開きます'
Write-Note 'メール アドレスは、いつも使っているものを自分で選んでください。'
Write-Note 'マスター パスワードは「4 語以上の長いフレーズ」がおすすめです。'
Write-Note '  忘れると誰も復旧できません。紙に書いて、人目につかない場所に保管してください。'
Write-Note '  （このスクリプトも Claude も、マスター パスワードを聞いたり記録したりしません）'
Write-Note '作成できたら Web 保管庫の「設定 → セキュリティ → 2 段階ログイン」で、'
Write-Note '  認証アプリによる 2 段階認証をオンにし、リカバリー コードも紙に控えてください。'
Wait-Enter 'アカウント作成ページを開きます'
Open-InBrave $SignupUrl | Out-Null

# ================================================================ 6. 移行の案内
Write-Step 6 'Brave のパスワードを Bitwarden に移す（ここからは手作業です）'
Write-Note '(a) Brave の「パスワード」設定を開き、右上の「…」または歯車から「パスワードをエクスポート」を選びます。'
Write-Note '    Windows の PIN などを聞かれたら入力し、CSV は「デスクトップ」に保存してください。'
Write-Note '(b) Bitwarden の Web 保管庫で「ツール → データのインポート」を開き、形式に「Brave (csv)」を選んで、'
Write-Note '    さっきの CSV を読み込みます。'
Write-Note '(c) 読み込みが終わったら、デスクトップの CSV を削除し、ごみ箱も空にしてください。'
Write-Note '    （CSV の中身は Claude もこのスクリプトも読みません。Brave 側のパスワードは消さなくて大丈夫です）'
$answer = Read-Host '  >> Brave のパスワード設定と Bitwarden のインポート ページを今開きますか？ (Y / n)'
if ($answer -notmatch '^(n|no)$') {
    Open-InBrave $BravePasswordsUrl | Out-Null
    Start-Sleep -Seconds 1
    Open-InBrave $ImportUrl | Out-Null
}

# ================================================================ 7. ログインと動作確認
Write-Step 7 'デスクトップ アプリと拡張機能にログインして、自動入力を試す'
Write-Note 'スタート メニューから Bitwarden を起動してログインし、Brave の Bitwarden 拡張機能にもログインしてください。'
Write-Note 'どこか 1 つのサイト（例: いつも使う通販やメール）のログイン画面を開き、'
Write-Note '  入力欄に Bitwarden のアイコンが出て、クリックで ID とパスワードが入ることを確認してください。'
$answer = Read-Host '  >> 今 Bitwarden デスクトップ アプリを起動しますか？ (Y / n)'
if ($answer -notmatch '^(n|no)$') {
    Start-Process -FilePath $exe
}

# ================================================================ 8. 報告
Write-Step 8 '完了報告（この 3 行だけ Claude に伝えてください）'
Write-Host ''
Write-Host ("  インストールしたバージョン : {0}" -f $installedVersion)
Write-Host ("  署名確認                   : {0} / 署名者に「{1}」を含む" -f $status, $ExpectedSigner)
Write-Host  '  移行した件数               : （Bitwarden の保管庫に表示された件数を読み上げてください）'
Write-Host ''
Write-Note 'スマホ（Android）側は Google Play から Bitwarden を入れてログインし、'
Write-Note '「設定 → 自動入力」をオンにすると、PC と同じパスワードがスマホでも自動入力されます。'
Write-Host ''
exit 0
