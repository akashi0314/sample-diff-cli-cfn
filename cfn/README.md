# cfn/ - CloudFormation テンプレート

このディレクトリには、CloudFormationによるインフラ構築のテンプレートが含まれています。

## ファイル構成

```
cfn/
├── vpc-ec2-demo.yaml                 # VPC + EC2のCloudFormationテンプレート
└── README.md                         # このファイル
```

## CloudFormationテンプレートの実行

### 1. テンプレートの検証
```bash
aws cloudformation validate-template --template-body file://vpc-ec2-demo.yaml
```

### 2. スタックの作成
```bash
aws cloudformation create-stack \
    --stack-name vpc-ec2-demo \
    --template-body file://vpc-ec2-demo.yaml
```

### 3. 作成状況の確認
```bash
# スタック全体の状況
aws cloudformation describe-stacks --stack-name vpc-ec2-demo

# リソース個別の状況
aws cloudformation describe-stack-resources --stack-name vpc-ec2-demo

# スタックイベントの確認
aws cloudformation describe-stack-events --stack-name vpc-ec2-demo
```

### 4. スタックの削除
```bash
aws cloudformation delete-stack --stack-name vpc-ec2-demo
```

## CloudFormationの特徴

- **宣言的記述**: 欲しい状態を記述するだけ
- **依存関係の自動解決**: リソース間の作成順序を自動判定
- **並行処理**: 独立したリソースは同時作成で効率化
- **自動ロールバック**: エラー時は自動で元の状態に復旧
- **スタック管理**: 関連リソースをまとめて管理・削除
- **再現性**: 同じテンプレートで何度でも同じ環境を作成