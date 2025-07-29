# CloudFormation vs AWS CLI による AWS インフラ構築比較

## 概要
このドキュメントでは、同じAWSインフラ（VPC + プライベートサブネット + EC2 + SSM）を構築する際の、CloudFormationとAWS CLIの違いを比較します。

---

## 🏗️ 構築対象アーキテクチャ

- **VPC**: 10.0.0.0/16 CIDR
- **プライベートサブネット**: 10.0.1.0/24 CIDR
- **EC2インスタンス**: Amazon Linux 2, t3.micro
- **Systems Manager接続**: 3つのVPCエンドポイント経由
- **セキュリティグループ**: 適切なアクセス制御
- **IAMロール**: SSM管理用権限

---

## 📋 CloudFormation による構築

### メリット ✅
- **宣言的**: 「何を作りたいか」を記述
- **冪等性**: 何度実行しても同じ結果
- **自動依存関係解決**: リソース間の依存を自動処理
- **ロールバック機能**: 失敗時の自動復旧
- **変更管理**: 差分のみ適用
- **テンプレート再利用**: 環境間での使い回し可能

### デメリット ❌
- **学習コスト**: CloudFormation固有の記法
- **デバッグの複雑さ**: エラー時の原因特定が困難
- **制限事項**: すべてのAWSサービスに対応していない場合がある

### 実行方法
```bash
# スタック作成
aws cloudformation create-stack \
  --stack-name demo-vpc-ec2-stack \
  --template-body file://vpc-ec2-demo.yaml \
  --capabilities CAPABILITY_IAM

# 進行状況確認
aws cloudformation describe-stacks --stack-name demo-vpc-ec2-stack

# 完了まで待機
aws cloudformation wait stack-create-complete --stack-name demo-vpc-ec2-stack
```

---

## 🔧 AWS CLI による構築

### メリット ✅
- **直感的**: AWSサービスの直接操作
- **柔軟性**: 複雑な条件分岐やエラーハンドリング
- **デバッグしやすい**: 各ステップで状態確認可能
- **学習効果**: AWSサービスの深い理解につながる

### デメリット ❌
- **手続き的**: 「どのように作るか」を詳細に記述
- **依存関係管理**: 手動で順序を管理
- **エラー処理**: 失敗時の cleanup が複雑
- **再実行の課題**: 冪等性の担保が困難

### 実行スクリプト

AWS CLIによる構築は以下のスクリプトファイルに分離されています：

1. **`config.env`** - 設定ファイル（環境変数）
2. **`create-infrastructure.sh`** - AWS CLI インフラ構築用メインスクリプト
3. **`cloudformation-deploy.sh`** - CloudFormation実行用スクリプト

### スクリプトファイルの使用方法

#### 1. 実行権限の付与
```bash
chmod +x create-infrastructure.sh
chmod +x cloudformation-deploy.sh
```

#### 2. AWS CLI による構築
```bash
# 基本実行
./create-infrastructure.sh

# カスタムオプション
./create-infrastructure.sh --region ap-northeast-1 --profile production
```

#### 3. CloudFormation による構築
```bash
# スタック作成
./cloudformation-deploy.sh

# スタック更新
./cloudformation-deploy.sh --update

# スタック削除
./cloudformation-deploy.sh --delete

# カスタム設定
./cloudformation-deploy.sh -s my-stack -t my-template.yaml --profile production
```

---

## 📊 比較表

| 項目 | CloudFormation | AWS CLI |
|------|----------------|---------|
| **記述方法** | 宣言的（YAML/JSON） | 手続き的（Bash/Python等） |
| **学習コスト** | 中〜高 | 低〜中 |
| **構築時間** | 並列実行で高速 | 逐次実行で時間がかかる |
| **エラー処理** | 自動ロールバック | 手動で cleanup 必要 |
| **可読性** | 高（構造化） | 中（スクリプト次第） |
| **再利用性** | 高（パラメータ化） | 中（変数化が必要） |
| **変更管理** | 差分適用 | 全体を意識した変更 |
| **デバッグ** | 難しい | 容易 |
| **冪等性** | 保証される | 実装次第 |
| **依存関係** | 自動解決 | 手動管理 |

---

## 🎯 学習のポイント

### CloudFormation を選ぶべき場面
- **本番環境**: 安定性と再現性が重要
- **複数環境**: dev/staging/prod での使い回し
- **チーム開発**: インフラのコード化と共有
- **複雑な構成**: 多数のリソースと依存関係

### AWS CLI を選ぶべき場面
- **学習目的**: AWSサービスの動作理解
- **プロトタイピング**: 迅速な検証
- **一時的な構築**: 短期間のテスト環境
- **細かい制御**: 複雑な条件分岐が必要

---

## 💡 実習課題

1. **基本課題**: 両方の方法で同じ環境を構築し、結果を比較
2. **応用課題**: セキュリティグループのルールを1つ追加する際の手順を比較
3. **発展課題**: 環境削除時の手順と安全性を比較

---

## 📚 まとめ

CloudFormationとAWS CLIは、それぞれ異なる強みを持つツールです。

- **CloudFormation**: Infrastructure as Code の実現に最適
- **AWS CLI**: AWSサービスの学習と細かい制御に最適

実際のプロジェクトでは、要件に応じて適切なツールを選択することが重要です。多くの場合、両方を組み合わせて使用することで、最適な結果を得ることができます。