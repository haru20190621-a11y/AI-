# Bitwarden セットアップ手順（Windows + Brave）

ハルの PC に Bitwarden のデスクトップ版と Brave 拡張機能を入れ、アカウントを作り、Brave に保存されているパスワードを Bitwarden に移すための手順です。
終わると「スマホと PC でパスワードを安全に共有し、各サービスで次回から自動入力される」状態になります。

このフォルダーには 2 つのファイルがあります。

| ファイル | 役割 |
| --- | --- |
| `Install-Bitwarden.ps1` | PC で実行するスクリプト。インストール → 署名確認 → Brave のページを開く、までを自動でやり、残りは画面の案内に従って手で進めます。 |
| `README.md` | この手順書。 |

## 事前確認済みのこと（2026-11-09、クラウド側で確認）

- winget パッケージ `Bitwarden.Bitwarden` の最新は **2026.10.4**（公開日 2026-11-05）。GitHub 公式リリース `bitwarden/clients` の `desktop-v2026.10.4` と一致。
- インストーラー `Bitwarden-Installer-2026.10.4.exe` の SHA256 は winget マニフェストの値 `AAEDFEAF73511B9095A5009454BB037A053C9A60E7C5ED23717B7B6047193A13` と一致。winget はインストール前にこの値を自動で照合します。
- 署名者は **Bitwarden Inc.（Santa Barbara, California, US）**、DigiCert の EV コード署名証明書（有効期間 2026-04-28 → 2027-07-30）。
- Brave 用の公式拡張機能は Chrome ウェブストア ID `nngceckbapebfimnlniiiahkandclblb`（公式リポジトリ `bitwarden/clients` の `apps/browser/README.md` が指しているもの）。

## 1. スクリプトを PC に持ってきて実行する

1. スタート メニューで「PowerShell」を検索して開きます（管理者権限は不要です）。
2. 次の 3 行を 1 行ずつ貼り付けて Enter を押します。

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/haru20190621-a11y/AI-/claude/gallant-johnson-cm3yvb/bitwarden-setup/Install-Bitwarden.ps1" -OutFile "$env:USERPROFILE\Downloads\Install-Bitwarden.ps1"
```

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

```powershell
& "$env:USERPROFILE\Downloads\Install-Bitwarden.ps1"
```

ブラウザーでダウンロードしたい場合は、GitHub でこのフォルダーの `Install-Bitwarden.ps1` を開き、「Raw」→ 右クリック「名前を付けて保存」で `ダウンロード` フォルダーに保存しても同じです。

## 2. スクリプトが自動でやること

| 手順 | 内容 | 止まる条件 |
| --- | --- | --- |
| 1 | `winget --version` で winget の有無を確認 | winget が無ければ Microsoft Store の「アプリ インストーラー」のページを開いて止まる |
| 2 | `winget install --id Bitwarden.Bitwarden --version 2026.10.4 --exact --scope user` でインストール | 2026.10.4 が無ければ `winget show` で最新版を表示し、入れるかどうかを聞く |
| 3 | `Get-AuthenticodeSignature` で `Bitwarden.exe` の署名を確認 | **Status が Valid でない、または署名者に Bitwarden Inc. が無ければ、起動せずにアンインストールして止まる** |
| 4 | Brave で拡張機能のページを開く | 「Brave に追加」はハルが押す |
| 5 | Brave でアカウント作成ページを開く | メール アドレスとマスター パスワードはハルが決める |

すでに Bitwarden が入っている PC では、インストールを飛ばして署名確認だけ行います。

## 3. 手で進めること（スクリプトの画面にも同じ案内が出ます）

### アカウント作成
- メール アドレスは、いつも使っているものを使います。
- マスター パスワードは **4 語以上の長いフレーズ** にします。忘れると誰も復旧できないので、紙に書いて人目につかない場所に保管します。
- 作成後、Web 保管庫の「設定 → セキュリティ → 2 段階ログイン」で **認証アプリによる 2 段階認証** をオンにし、リカバリー コードも紙に控えます。

### Brave からの移行
1. Brave で `brave://settings/passwords` を開き、「パスワードをエクスポート」で CSV を **デスクトップ** に保存します（Windows の PIN などを聞かれたら入力）。
2. Bitwarden の Web 保管庫で「ツール → データのインポート」を開き、形式に **Brave (csv)** を選んで、その CSV を読み込みます。
3. 読み込みが終わったら CSV を削除し、**ごみ箱も空に** します。Brave 側のパスワードは消さなくて大丈夫です。

### ログインと動作確認
1. Bitwarden デスクトップ アプリにログインします。
2. Brave の Bitwarden 拡張機能にもログインします（ツールバーにピン留めしておくと便利）。
3. どこか 1 つのサイトのログイン画面で、入力欄に Bitwarden のアイコンが出て、クリックで ID とパスワードが入ることを確認します。

## 4. 完了報告

次の 3 つだけを Claude に伝えてください。パスワードや CSV の中身は伝えないでください。

```
インストールしたバージョン : （スクリプトの最後に表示されます）
署名確認                   : Valid / 署名者に Bitwarden Inc. を含む
移行した件数               : （Bitwarden の保管庫に表示された件数）
```

## 5. スマホ側（Android）

Google Play から Bitwarden を入れてログインし、「設定 → 自動入力」をオンにすると、PC と同じパスワードがスマホでも自動入力されます。

## 守ること

- パスワード・マスター パスワード・CSV の中身を、チャット・ファイル・ログに書かない、読まない。スクリプトも読みません。
- 署名確認が Valid かつ Bitwarden Inc. でなければ先に進まない（スクリプトが自動で止めます）。
- 壊す操作はしない。削除するのはエクスポートした CSV だけ。

## Claude に PC 上で付き添ってもらいたいとき

クラウド上の Claude Code セッションからは PC に触れません。PC で Claude デスクトップ アプリの Claude Code を開くか、作業フォルダーで `claude remote-control` を実行すると、その PC 上で Claude が同じ手順を一緒に進められます。
