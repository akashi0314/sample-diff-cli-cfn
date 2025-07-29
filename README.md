# CloudFormation vs AWS CLI インフラ構築比較デモ

新入社員向けのCloudFormationとAWS CLI直接実行の学習用比較プロジェクトです。

## 🎯 概要

同じAWSインフラ構成を **CloudFormation** と **AWS CLI** の2つの方法で構築し、Infrastructure as Code (IaC) と直接実行の違いを体験できる教育用プロジェクトです。

### 学習目標
- CloudFormationの宣言的インフラ定義を理解
- AWS CLIによる手続き的リソース作成を体験
- IaCのメリット・デメリットを実践的に学習
- 運用・保守性の違いを比較

## 🏗️ 構築対象アーキテクチャ

| リソース | 設定値 | 説明 |
|---------|--------|------|
| **VPC** | 10.0.0.0/16 | 仮想プライベートクラウド |
| **プライベートサブネット** | 10.0.1.0/24 | 完全プライベート環境 |
| **VPCエンドポイント** | SSM関連3つ | インターネット不要でSSM接続 |
| **セキュリティグループ** | 最小権限設定 | EC2とVPCエンドポイント用 |
| **EC2インスタンス** | t3.micro, Amazon Linux | SSM管理対象サーバー |
| **IAMロール** | SSM接続権限 | Systems Manager用権限 |

### 環境仕様

| 項目 | 設定値 |
|------|--------|
| **推奨リージョン** | us-east-1 (バージニア北部) |
| **アベイラビリティゾーン** | us-east-1a |
| **インスタンスタイプ** | t3.micro (無料利用枠対象) |
| **AMI** | Amazon Linux 2/2023 最新版 |
| **接続方式** | SSM Session Manager (完全プライベート) |
| **インターネット接続** | なし (VPCエンドポイント経由) |

## 📁 プロジェクト構成

```
sample-diff-cli-cfn/
├── README.md                          # このファイル
├── cli/                              # AWS CLI直接実行版
│   ├── README.md                      # CLI版詳細ドキュメント
│   ├── create.sh                      # メイン実行スクリプト
│   ├── config.env                     # 設定ファイル
│   ├── cli-resource-ids.json          # リソース追跡ファイル（自動生成）
│   ├── cli-creation-info.txt          # 構築結果情報（自動生成）
│   └── .gitignore                     # Git除外設定
└── cfn/                              # CloudFormation版
    ├── README.md                      # CloudFormation版詳細ドキュメント
    └── vpc-ec2-demo.yml               # CloudFormationテンプレート
```

## 🚀 使い方

### 事前準備

1. **AWS CLI インストール・設定**
```bash
# AWS CLI認証確認
aws sts get-caller-identity --region us-east-1

# プロファイル使用の場合
aws configure --profile your-profile
```

2. **必要ツールのインストール**
```bash
# jq (JSON処理ツール) - CLI版で必要
# Ubuntu/Debian: sudo apt-get install jq
# CentOS/RHEL: sudo yum install jq
# macOS: brew install jq
```

### CloudFormation版での実行

**推奨**: 本番環境やチーム開発では CloudFormation を使用

```bash
cd cfn/

# 1. テンプレート検証
aws cloudformation validate-template \
    --template-body file://vpc-ec2-demo.yml \
    --region us-east-1

# 2. スタック作成
aws cloudformation create-stack \
    --stack-name vpc-ec2-demo \
    --template-body file://vpc-ec2-demo.yml \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# 3. 作成完了待機
aws cloudformation wait stack-create-complete \
    --stack-name vpc-ec2-demo \
    --region us-east-1

# 4. 接続情報取得
aws cloudformation describe-stacks \
    --stack-name vpc-ec2-demo \
    --query 'Stacks[0].Outputs' \
    --region us-east-1

# 5. SSM接続
aws ssm start-session --target <instance-id> --region us-east-1

# 6. 削除
aws cloudformation delete-stack \
    --stack-name vpc-ec2-demo \
    --region us-east-1
```

### AWS CLI版での実行

**学習目的**: AWSサービスの詳細動作理解に最適

```bash
cd cli/

# 実行権限付与
chmod +x create.sh

# 1. 基本実行
./create.sh

# 2. プロファイル指定実行
./create.sh --profile your-profile

# 3. リージョン指定実行  
./create.sh --region us-east-1

# 4. プロファイル+リージョン指定
./create.sh --profile your-profile --region us-east-1

# 5. 作成したリソース確認
cat cli-resource-ids.json | jq
cat cli-creation-info.txt

# 6. SSM接続
aws ssm start-session --target <instance-id> --region us-east-1

# 7. リソース削除
./create.sh --delete

# 8. ヘルプ表示
./create.sh --help
```

## 📊 CloudFormation vs AWS CLI 比較

| 項目 | CloudFormation | AWS CLI (本実装) |
|------|----------------|---------|
| **記述方法** | 宣言的（YAML） | 手続き的（Bash + AWS CLI） |
| **学習コスト** | 中〜高 | 低〜中 |
| **構築時間** | 並列実行で高速 | 逐次実行で時間要 |
| **エラー処理** | 自動ロールバック | カスタムエラーハンドリング |
| **冪等性** | 保証される | スクリプトで実装済み |
| **依存関係** | 自動解決 | 手動管理（実装済み） |
| **変更管理** | 差分適用 | 既存リソース検出・再利用 |
| **リソース追跡** | スタック単位で自動 | JSONファイルで管理 |
| **削除機能** | 一括削除 | 依存関係考慮の順序削除 |
| **デバッグ** | CloudWatch Logsで確認 | ステップ毎ログ出力 |
| **テンプレート再利用** | パラメータ化で容易 | 設定ファイルで対応 |
| **本番運用** | 推奨 | 学習・プロトタイプ向け |

## 🎓 学習コンテンツ

### 実習課題

#### 基本課題
1. **両方法での環境構築**: 同じ結果が得られることを確認
2. **SSM接続体験**: Session Managerでプライベート環境に接続
3. **リソース確認**: AWSコンソールで作成されたリソースを確認
4. **削除体験**: 各方法でのリソース削除手順を体験

#### 応用課題
1. **設定変更**: `config.env` でインスタンスタイプを変更して再実行
2. **冪等性確認**: 同じスクリプト/テンプレートを複数回実行
3. **エラー対応**: 意図的にエラーを発生させて動作確認
4. **リージョン変更**: us-west-2 等の他リージョンでの実行

#### 発展課題
1. **追加リソース**: S3用VPCエンドポイントの追加実装
2. **マルチAZ**: 複数アベイラビリティゾーンへの展開
3. **モニタリング**: CloudWatch Logs エージェントの設定
4. **セキュリティ強化**: IMDSv2強制、セッションマネージャー制限

### 学習ポイント

#### CloudFormation の利点
- **Infrastructure as Code**: バージョン管理・レビュー可能
- **宣言的記述**: 「何を作りたいか」に集中
- **自動依存関係解決**: 複雑なリソース間関係を自動処理
- **エラー時自動復旧**: 失敗時の自動ロールバック
- **チーム開発**: 標準化されたインフラ定義

#### AWS CLI の利点
- **学習効果**: AWSサービスの詳細動作理解
- **柔軟性**: 複雑な条件分岐・カスタムロジック実装
- **デバッグ容易**: ステップ毎の実行状況確認
- **プロトタイピング**: 迅速な検証・実験

## 🔧 トラブルシューティング

### よくある問題

1. **権限エラー**
```bash
# IAM権限確認
aws iam get-user
aws sts get-caller-identity
```

2. **リージョン設定**
```bash
# 現在のリージョン確認
aws configure get region
export AWS_DEFAULT_REGION=us-east-1
```

3. **jq未インストール（CLI版）**
```bash
# Ubuntu/Debian
sudo apt-get install jq

# Amazon Linux/CentOS
sudo yum install jq

# macOS
brew install jq
```

4. **一時クレデンシャル使用時**
```bash
# 環境変数確認
echo $AWS_ACCESS_KEY_ID
echo $AWS_SECRET_ACCESS_KEY  
echo $AWS_SESSION_TOKEN
```

### サポートされる認証方式

- ✅ デフォルト認証情報（~/.aws/credentials）
- ✅ 環境変数（AWS_ACCESS_KEY_ID等）
- ✅ IAMロール（EC2インスタンス等）
- ✅ AWS SSOプロファイル
- ✅ 一時クレデンシャル（AWS_SESSION_TOKEN）

## 🎯 まとめ

このプロジェクトを通じて以下を習得できます：

1. **CloudFormation**: 本番環境でのIaC実装手法
2. **AWS CLI**: AWSサービスの詳細理解と自動化スクリプト作成
3. **比較理解**: 各手法の適用場面の判断力
4. **実践スキル**: 実際のプロジェクトで活用できる知識

### 推奨学習フロー

1. **AWS CLI版から開始**: AWSサービスの基本理解
2. **CloudFormation版を体験**: IaCの利点を実感
3. **両者を比較**: 適用場面の理解
4. **応用課題に挑戦**: 実践的なスキル向上

---

## 📝 ライセンス

このプロジェクトは教育目的で作成されています。
AWS利用料金が発生する可能性があるため、不要なリソースは削除してください。

**重要**: デモ実行後は必ずリソースを削除し、予期しない課金を避けてください。