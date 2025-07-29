# cfn/ - CloudFormation テンプレート

このディレクトリには、CloudFormationによるインフラ構築のテンプレートが含まれています。

## ファイル構成

```
cfn/
├── vpc-ec2-demo.yml                  # VPC + EC2のCloudFormationテンプレート（プライベートサブネット + SSM）
└── README.md                         # このファイル
```

## インフラ構成

このテンプレートは以下のリソースを作成します：

### ネットワーク
- **VPC**: 10.0.0.0/16 のCIDRブロック
- **プライベートサブネット**: 10.0.1.0/24 (us-east-1a)
- **VPCエンドポイント**: SSM、SSMMessages、EC2Messages用（インターフェース型）

### セキュリティ
- **VPCエンドポイント用セキュリティグループ**: EC2からのHTTPS(443)通信を許可
- **EC2インスタンス用セキュリティグループ**: VPCエンドポイントへのHTTPS(443)通信を許可

### コンピュート
- **EC2インスタンス**: t3.micro、Amazon Linux 2（最新AMI）
- **IAMロール**: AmazonSSMManagedInstanceCore ポリシーを付与
- **インスタンスプロファイル**: EC2にIAMロールを関連付け

### 特徴
- **完全プライベート環境**: インターネットゲートウェイやNATゲートウェイなし
- **SSM接続**: VPCエンドポイント経由でSystems Manager Session Managerを使用
- **セキュア**: 最小権限の原則に基づくセキュリティグループ設定

## CloudFormationテンプレートの実行

**重要**: このテンプレートはus-east-1リージョンで実行してください。

### 1. テンプレートの検証
```bash
aws cloudformation validate-template \
    --template-body file://vpc-ec2-demo.yml \
    --region us-east-1
```

### 2. スタックの作成
```bash
aws cloudformation create-stack \
    --stack-name vpc-ec2-demo \
    --template-body file://vpc-ec2-demo.yml \
    --capabilities CAPABILITY_IAM \
    --region us-east-1
```

### 3. 作成状況の確認
```bash
# スタック全体の状況
aws cloudformation describe-stacks \
    --stack-name vpc-ec2-demo \
    --region us-east-1

# リソース個別の状況
aws cloudformation describe-stack-resources \
    --stack-name vpc-ec2-demo \
    --region us-east-1

# スタックイベントの確認
aws cloudformation describe-stack-events \
    --stack-name vpc-ec2-demo \
    --region us-east-1
```

### 4. EC2インスタンスへの接続
```bash
# Session Manager経由でEC2に接続
aws ssm start-session --target <instance-id> --region us-east-1

# インスタンスIDの確認
aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=demo-instance" \
    --query "Reservations[*].Instances[*].InstanceId" \
    --output text \
    --region us-east-1
```

### 5. スタックの削除
```bash
aws cloudformation delete-stack \
    --stack-name vpc-ec2-demo \
    --region us-east-1
```

## CloudFormationの特徴

- **宣言的記述**: 欲しい状態を記述するだけ
- **依存関係の自動解決**: リソース間の作成順序を自動判定
- **並行処理**: 独立したリソースは同時作成で効率化
- **自動ロールバック**: エラー時は自動で元の状態に復旧
- **スタック管理**: 関連リソースをまとめて管理・削除
- **再現性**: 同じテンプレートで何度でも同じ環境を作成

## 注意事項

- **リージョン**: このテンプレートはus-east-1リージョン専用です
- **他リージョンでの使用**: 他のリージョンで使用する場合は以下を変更してください：
  - VPCエンドポイントのサービス名（`com.amazonaws.us-east-1.*` の部分）
  - アベイラビリティゾーン（`us-east-1a` の部分）
- **権限**: IAMロールの作成のため、`--capabilities CAPABILITY_IAM`フラグが必要です
- **AWS CLI設定**: AWSプロファイルでus-east-1リージョンが設定されていることを確認してください