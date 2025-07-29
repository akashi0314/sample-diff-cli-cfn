#!/bin/bash
# 認証テスト用簡単スクリプト

set -e

echo "=== AWS認証テスト開始 ==="
echo "現在時刻: $(date)"

echo "AWS_SESSION_TOKEN存在確認: ${AWS_SESSION_TOKEN:+設定済み}"
echo "AWS_ACCESS_KEY_ID存在確認: ${AWS_ACCESS_KEY_ID:+設定済み}"

echo "AWS STS呼び出し開始..."
echo "実行コマンド: aws sts get-caller-identity --region us-east-1"

# 直接実行
result=$(aws sts get-caller-identity --region us-east-1 2>&1)
exit_code=$?

echo "AWS STS呼び出し完了"
echo "終了コード: $exit_code"
echo "結果: $result"

if [[ $exit_code -eq 0 ]]; then
    echo "✅ 認証成功"
    
    # jqでパース
    account=$(echo "$result" | jq -r '.Account')
    arn=$(echo "$result" | jq -r '.Arn')
    
    echo "アカウント: $account"
    echo "ARN: $arn"
else
    echo "❌ 認証失敗"
fi

echo "=== テスト完了 ==="