# fukuro-chan

Claude Code の状態（`running` / `waiting` / `idle`）に連動して表情が変わる、デスクトップに常駐する小さなペットです。

- プロンプト送信・ツール実行中 → `running`
- ツール実行の許可待ち（パーミッションダイアログ） → `waiting`
- それ以外（ターン終了・セッション開始/終了） → `idle`

会話の中身やAPIキーは一切扱いません。状態ファイルには `idle` / `running` / `waiting` の1語だけが書き込まれます。

Windows専用です（PowerShell + WinForms）。

## 必要なもの

- Windows + Claude Code CLI（フックに対応したバージョン）
- 自分で用意した表情画像3枚（背景透過PNG）: `idle.png` / `running.png` / `waiting.png`
  - このリポジトリには画像は含まれていません。好きなキャラクターの画像を用意してください

## セットアップ

1. このリポジトリをクローンする
2. `%USERPROFILE%\fukuro-chan\` フォルダを作り、そこに `idle.png` / `running.png` / `waiting.png` を置く
3. リポジトリのフォルダで `install.ps1` を実行する

   ```powershell
   powershell -ExecutionPolicy Bypass -File install.ps1
   ```

   これで以下が行われます:
   - `~/.claude/hooks/fukuro-chan/` にスクリプトを配置
   - 画像からアイコン (`pet.ico`) を生成
   - デスクトップにショートカット (`fukuro-chan.lnk`) を作成
   - `~/.claude/settings.json` にフックを追記（既存の設定は壊しません。再実行しても重複登録されません）

4. デスクトップの `fukuro-chan` ショートカットをダブルクリックして起動

ログイン時に自動起動したい場合は、このショートカットを `shell:startup` フォルダにコピーしてください。

## 使い方

- ドラッグで好きな場所に移動できます
- 右クリック→「終了」で終了します
- サイズを変えたい場合は `~/.claude/hooks/fukuro-chan/pet.ps1` 内の `$targetHeight`（初期値220）を編集してください

## アンインストール

1. デスクトップの `fukuro-chan.lnk` を削除
2. `~/.claude/hooks/fukuro-chan/` フォルダを削除
3. `~/.claude/settings.json` の `hooks` 内から、`fukuro-chan/write-state.sh` を参照している7つのエントリ（`SessionStart` / `SessionEnd` / `UserPromptSubmit` / `PreToolUse` / `PostToolUse` / `Notification` / `Stop`）を削除

## 仕組み

- Claude Code のフックが `write-state.sh` を呼び出し、`~/fukuro-chan/state.txt` に状態を1語書き込みます
- `Notification` フックだけは、中身の `notification_type` が `permission_prompt` のときだけ `waiting` を書き込みます（`idle_prompt` などの他の通知は無視します）
- `pet.ps1` は `state.txt` を1秒ごとに読み、変化があれば表情画像を切り替えます（レイヤードウィンドウ／`UpdateLayeredWindow` を使った本物の半透明合成なので、背景透過PNGの縁が滲みません）
