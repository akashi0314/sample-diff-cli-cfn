# CloudFormation デモ

新入社員向けのCloudFormation学習用サンプルです。

## 概要

AWS CLIとCloudFormationの違いを理解するためのデモプロジェクトです。
同じインフラ構成を作成しますが、実装方法が異なることを体験できます。

## デモ環境の設定

### 作成するリソース

| リソース | 設定値 | 説明 |
|---------|--------|------|
| VPC | 10.0.0.0/16 | 仮想プライベートクラウド |
| パブリックサブネット | 10.0.1.0/24 | インターネット接続可能なサブネット |
| インターネットゲートウェイ | - | インターネット接続用 |
| ルートテーブル | 0.0.0.0/0 → IGW | パブリックアクセス用ルーティング |
| セキュリティグループ | SSH (22) 許可 | EC2アクセス用セキュリティ設定 |
| EC2インスタンス | t3.micro, Amazon Linux 2 | 検証用仮想サーバー |

### 環境仕様

| 項目 | 設定値 |
|------|--------|
| AWSリージョン | ap-northeast-1 (東京) |
| アベイラビリティゾーン | ap-northeast-1a |
| インスタンスタイプ | t3.micro (無料利用枠対象) |
| AMI | Amazon Linux 2 最新版 |
| ストレージ | 8GB gp3 (デフォルト) |
| SSH接続 | 任意のIPから許可 (0.0.0.0/0) |

## AWS CLI vs CloudFormation

### AWS CLI の特徴
- コマンドを順次実行
- 依存関係を手動で管理
- エラー時の手動対応が必要

### CloudFormation の特徴  
- 設定を宣言的に記述
- 依存関係を自動解決
- エラー時の自動ロールバック
- 並行処理による高速化

## 使い方

### CloudFormationでのデプロイ
```bash
# テンプレートの検証
aws cloudformation validate-template --template-body file://vpc-ec2-demo.yaml

# スタックの作成
aws cloudformation create-stack \
    --stack-name vpc-ec2-demo \
    --template-body file://vpc-ec2-demo.yaml

# スタックの状況確認
aws cloudformation describe-stacks --stack-name vpc-ec2-demo

# スタックの削除
aws cloudformation delete-stack --stack-name vpc-ec2-demo
```

### AWS CLIでの比較
```bash
# CLI版の実行（比較用）
./create-vpc-ec2-cli.sh

# 作成されたリソースの確認
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=demo-vpc"
```

## 学習のポイント

1. **結果は同じ**: どちらの方法でも同じインフラが作成される
2. **プロセスが違う**: 手順の管理方法が大きく異なる
3. **運用面での違い**: 更新、削除、トラブル対応の容易さ

## 実行環境

- AWS CLI がインストール済み
- 適切なAWS認証情報が設定済み
- ap-northeast-1 リージョンを使用